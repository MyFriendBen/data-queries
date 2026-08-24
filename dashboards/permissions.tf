# =============================================================================
# Metabase Permissions Groups
# =============================================================================
#
# Groups control which dashboards and data each Metabase user can access.
# A user can belong to more than one group.
#
# Group structure:
#   - Global: access to everything (global collection + all tenant collections)
#   - Per-tenant (e.g. "NC", "CO"): access to that white label's collection only
#
# To limit a user to a specific white label, add them to that tenant's group.
# To give someone access to all dashboards, add them to the Global group.
#
# NOTE: The built-in "All Users" group (id = 1) is intentionally given
# minimal/no collection permissions so that access is controlled exclusively
# through these custom groups.
# =============================================================================

# --- Global group -----------------------------------------------------------

resource "metabase_permissions_group" "global" {
  name = "Global Viewers"
}

# --- Per-tenant groups -------------------------------------------------------
#
# One group per white-label tenant. When a new state is added (new tenant in
# var.tenants), a new group is automatically created here with the correct
# collection permission set below - no additional manual steps required.

resource "metabase_permissions_group" "tenant" {
  for_each = var.tenants

  name = "${each.value.display_name} Viewers"
}

# --- Per-tenant editor groups ------------------------------------------------
#
# Parallel to viewer groups but with write collection access. Data permissions
# remain identical to viewer groups.

resource "metabase_permissions_group" "tenant_editor" {
  for_each = var.tenants

  name = "${each.value.display_name} Editors"
}

# --- CU Denver referrer viewer group ------------------------------
# CU Denver is a referrer inside the CO white label, not a tenant. This group is
# view-only: read on the CU Denver collection (below) and NO ad-hoc DB query
# access anywhere (the dashboard cards are pre-scoped to referrer=cudenver, so
# viewers cannot broaden the scope). Members are added manually in the Metabase
# UI (local logins — existing pattern).
resource "metabase_permissions_group" "cu_denver" {
  name = "CU Denver Viewers"
}

# --- CPAL referrer viewer group -----------------------------------
# CPAL (Child Poverty Action Lab) is a referrer inside the TX white label, not
# a tenant — same pattern as CU Denver. View-only: read on the CPAL collection
# and NO ad-hoc DB query access (cards are pre-scoped to CPAL referrer codes).
# Members are added manually in the Metabase UI.
resource "metabase_permissions_group" "cpal" {
  name = "CPAL Viewers"
}

# =============================================================================
# Collection Permissions Graph
# =============================================================================
#
# Controls which groups can see which collections (dashboards).
#
# Rules:
#   - Global group        → read on Global collection AND all tenant collections
#   - Tenant viewer group → read-only on their own tenant collection only
#   - Tenant editor group → write on their own tenant collection only
#   - All Users (1)       → no access to any collection (default deny)
#
# The collection_graph is a singleton in Metabase. It must be imported on first
# use rather than created from scratch:
#
#   terraform import metabase_collection_graph.graph 1
#
# =============================================================================

resource "metabase_collection_graph" "graph" {
  # Ignore Administrators (id=2) and any manually created groups so they don't
  # cause graph errors. See local.ignored_group_ids for the full derivation.
  ignored_groups = local.ignored_group_ids

  permissions = concat(
    # --- Global group: read access to the global collection ------------------
    [
      {
        group      = metabase_permissions_group.global.id
        collection = metabase_collection.global.id
        permission = "read"
      }
    ],

    # --- Global group: read access to every tenant collection ----------------
    [
      for key, col in local.tenant_collection_map : {
        group      = metabase_permissions_group.global.id
        collection = col.id
        permission = "read"
      }
    ],

    # --- Global group: read on the CU Denver referrer collection -------------
    # cu_denver is a referrer overlay, not a tenant, so it isn't in
    # tenant_collection_map above — grant it to global explicitly so super users
    # (Global Viewers) can see every dashboard.
    [
      {
        group      = metabase_permissions_group.global.id
        collection = metabase_collection.cu_denver.id
        permission = "read"
      }
    ],

    # --- Global group: read on the CPAL referrer collection ------------------
    [
      {
        group      = metabase_permissions_group.global.id
        collection = metabase_collection.cpal.id
        permission = "read"
      }
    ],

    # --- Per-tenant group: read-only access to their own collection ----------
    [
      for key, tenant in var.tenants : {
        group      = metabase_permissions_group.tenant[key].id
        collection = local.tenant_collection_map[key].id
        permission = "read"
      } if contains(keys(local.tenant_collection_map), key)
    ],

    # --- Per-tenant editor group: write access to their own collection --------
    [
      for key, tenant in var.tenants : {
        group      = metabase_permissions_group.tenant_editor[key].id
        collection = local.tenant_collection_map[key].id
        permission = "write"
      } if contains(keys(local.tenant_collection_map), key)
    ],

    # --- CU Denver referrer group: read on the CU Denver collection only ------
    [
      {
        group      = metabase_permissions_group.cu_denver.id
        collection = metabase_collection.cu_denver.id
        permission = "read"
      }
    ],

    # --- CPAL referrer group: read on the CPAL collection only ----------------
    [
      {
        group      = metabase_permissions_group.cpal.id
        collection = metabase_collection.cpal.id
        permission = "read"
      }
    ]
  )
}

# =============================================================================
# Data Permissions Graph
# =============================================================================
#
# Controls which groups can query which databases in the Metabase query builder.
#
# Rules:
#   - All Users (1)       → no query access to any database (baseline deny for everyone)
#   - Global group        → full query access (query-builder-and-native) to all managed databases; no access to unmanaged databases
#   - Tenant viewer group → query-builder access to their own tenant DB only; no access elsewhere
#   - Tenant editor group → same as viewer group (write collection access ≠ elevated DB access)
#
# This closes the gap that collection permissions alone cannot address: without
# this, a user scoped to the NC group can still browse the CO database directly
# via the Metabase query builder. This resource enforces data source isolation
# at the Metabase permission layer (in addition to PostgreSQL RLS).
#
# IMPORTANT — this resource is a singleton and must be imported before the
#    first apply (just like the collection graph):
#
#      terraform import metabase_permissions_graph.graph 1
#
# TRADE-OFF: The provider sends the complete graph to Metabase on every
#    apply. Every group × database pair must be listed here. Missing pairs are
#    sent as nil and will cause a 400 error. If a new built-in/sample database
#    appears in Metabase (e.g. after an upgrade), add it to ignored_groups or
#    enumerate it here.
#
# =============================================================================

# Fetch all database and group IDs from Metabase to discover unmanaged ones.
#
# We use /api/database and /api/permissions/group directly rather than the
# metabase_permissions_graph data source because that data source crashes when
# any group has schema-level (object-style) create-queries permissions — a bug
# in flovouin/terraform-provider-metabase that affects create-queries but not
# view-data. See: https://github.com/flovouin/terraform-provider-metabase/issues
data "external" "metabase_ids" {
  program = ["python3", "${path.module}/scripts/get_metabase_ids.py"]

  query = {
    metabase_url = var.metabase_url
    username     = var.metabase_admin_email
    password     = var.metabase_admin_password
  }
}

locals {
  # All managed database IDs in one place for easy reuse across permission rules.
  all_db_ids = concat(
    [metabase_database.postgres.id],
    [for k, db in metabase_database.tenant_postgres : db.id],
    var.bigquery_enabled ? [metabase_database.bigquery[0].id] : []
  )

  # Databases that exist in Metabase but are NOT managed by Terraform
  # (e.g. Metabase's built-in H2 sample database). Derived dynamically so the
  # list stays correct across environments and Metabase upgrades.
  unmanaged_db_ids = setsubtract(
    toset([for id in jsondecode(data.external.metabase_ids.result.db_ids) : tostring(id)]),
    toset([for id in local.all_db_ids : tostring(id)])
  )

  # Every database ID that must appear in the graph (managed + unmanaged).
  all_known_db_ids = concat(local.all_db_ids, tolist(local.unmanaged_db_ids))

  # All managed group IDs (groups created by Terraform)
  all_managed_group_ids = concat(
    [1], # All Users group
    [metabase_permissions_group.global.id],
    [metabase_permissions_group.cu_denver.id],
    [metabase_permissions_group.cpal.id],
    [for k, g in metabase_permissions_group.tenant : g.id],
    [for k, g in metabase_permissions_group.tenant_editor : g.id]
  )

  # Groups that exist in Metabase but are NOT managed by Terraform.
  # Discovered dynamically so that groups created manually in the Metabase UI
  # are automatically ignored — Terraform neither reads nor updates their
  # permissions. Excludes Administrators (id = 2) since it's always ignored.
  unmanaged_group_ids = setsubtract(
    setsubtract(
      toset([for id in jsondecode(data.external.metabase_ids.result.group_ids) : tostring(id)]),
      toset([for id in local.all_managed_group_ids : tostring(id)])
    ),
    toset(["2"])
  )

  # All groups to ignore across both graph resources: Administrators (id=2) plus
  # any unmanaged groups. Centralised here so collection_graph and
  # permissions_graph stay in sync automatically.
  ignored_group_ids = concat([2], [for id in local.unmanaged_group_ids : tonumber(id)])
}

resource "metabase_permissions_graph" "graph" {
  # Ignore Administrators (id=2) and any unmanaged groups — see local.ignored_group_ids.
  ignored_groups = local.ignored_group_ids

  # advanced_permissions = false uses the free-tier permission model (view_data
  # is always "unrestricted"; access is controlled via create_queries).
  advanced_permissions = true

  permissions = concat(
    # --- All Users (group 1): no query access to any database ----------------
    # Baseline deny. Every user starts with no query builder access.
    # Must cover ALL databases (managed + unmanaged) to satisfy the API.
    [
      for db_id in local.all_known_db_ids : {
        group          = 1
        database       = tonumber(db_id)
        view_data      = "unrestricted" # required by free-tier Metabase
        create_queries = "no"
        download       = { schemas = "full" }
        data_model     = null
      }
    ],

    # --- Global group: full access to all managed databases ------------------
    [
      for db_id in local.all_db_ids : {
        group          = metabase_permissions_group.global.id
        database       = tonumber(db_id)
        view_data      = "unrestricted"
        create_queries = "query-builder-and-native"
        download       = { schemas = "full" }
        data_model     = null
      }
    ],
    # Global group on unmanaged DBs: no access needed, but must be listed
    [
      for db_id in local.unmanaged_db_ids : {
        group          = metabase_permissions_group.global.id
        database       = tonumber(db_id)
        view_data      = "unrestricted"
        create_queries = "no"
        download       = { schemas = "full" }
        data_model     = null
      }
    ],

    # --- Per-tenant groups: query-builder on own DB only ---------------------
    # For each tenant, grant access to their own DB and explicitly deny all others.
    flatten([
      for tenant_key, tenant in var.tenants : concat(
        # Own database: allow query builder
        [
          {
            group          = metabase_permissions_group.tenant[tenant_key].id
            database       = tonumber(metabase_database.tenant_postgres[tenant_key].id)
            view_data      = "unrestricted"
            create_queries = "query-builder"
            download       = { schemas = "full" }
            data_model     = null
          }
        ],
        # All other managed databases: no access
        [
          for db_id in local.all_db_ids : {
            group          = metabase_permissions_group.tenant[tenant_key].id
            database       = tonumber(db_id)
            view_data      = "unrestricted"
            create_queries = "no"
            download       = { schemas = "full" }
            data_model     = null
          }
          if tonumber(db_id) != tonumber(metabase_database.tenant_postgres[tenant_key].id)
        ],
        # Unmanaged databases: no access
        [
          for db_id in local.unmanaged_db_ids : {
            group          = metabase_permissions_group.tenant[tenant_key].id
            database       = tonumber(db_id)
            view_data      = "unrestricted"
            create_queries = "no"
            download       = { schemas = "full" }
            data_model     = null
          }
        ]
      )
    ]),

    # --- Per-tenant editor groups: query-builder on own DB only ---------------
    # Identical to viewer data perms — write collection access ≠ elevated DB access.
    flatten([
      for tenant_key, tenant in var.tenants : concat(
        # Own database: allow query builder
        [
          {
            group          = metabase_permissions_group.tenant_editor[tenant_key].id
            database       = tonumber(metabase_database.tenant_postgres[tenant_key].id)
            view_data      = "unrestricted"
            create_queries = "query-builder"
            download       = { schemas = "full" }
            data_model     = null
          }
        ],
        # All other managed databases: no access
        [
          for db_id in local.all_db_ids : {
            group          = metabase_permissions_group.tenant_editor[tenant_key].id
            database       = tonumber(db_id)
            view_data      = "unrestricted"
            create_queries = "no"
            download       = { schemas = "full" }
            data_model     = null
          }
          if tonumber(db_id) != tonumber(metabase_database.tenant_postgres[tenant_key].id)
        ],
        # Unmanaged databases: no access
        [
          for db_id in local.unmanaged_db_ids : {
            group          = metabase_permissions_group.tenant_editor[tenant_key].id
            database       = tonumber(db_id)
            view_data      = "unrestricted"
            create_queries = "no"
            download       = { schemas = "full" }
            data_model     = null
          }
        ]
      )
    ]),

    # --- CU Denver referrer group: NO query access to any database -----------
    # View-only via collection read; the dashboard cards are pre-scoped to
    # referrer=cudenver, so no query-builder access is granted anywhere.
    # Must cover ALL databases (managed + unmanaged) to satisfy the API.
    [
      for db_id in local.all_known_db_ids : {
        group          = metabase_permissions_group.cu_denver.id
        database       = tonumber(db_id)
        view_data      = "unrestricted"
        create_queries = "no"
        download       = { schemas = "full" }
        data_model     = null
      }
    ],

    # --- CPAL referrer group: NO query access to any database -----------------
    # Same rationale as CU Denver: view-only via collection read; cards are
    # pre-scoped to CPAL referrer codes, so no query-builder access is granted
    # anywhere.
    [
      for db_id in local.all_known_db_ids : {
        group          = metabase_permissions_group.cpal.id
        database       = tonumber(db_id)
        view_data      = "unrestricted"
        create_queries = "no"
        download       = { schemas = "full" }
        data_model     = null
      }
    ]
  )
}
