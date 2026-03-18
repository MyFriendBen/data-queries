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
  name = "Global"
}

# --- Per-tenant groups -------------------------------------------------------
#
# One group per white-label tenant. When a new state is added (new tenant in
# var.tenants), a new group is automatically created here with the correct
# collection permission set below - no additional manual steps required.

resource "metabase_permissions_group" "tenant" {
  for_each = var.tenants

  name = each.value.display_name
}

# =============================================================================
# Collection Permissions Graph
# =============================================================================
#
# Controls which groups can see which collections (dashboards).
#
# Rules:
#   - Global group  → read+write on Global collection AND all tenant collections
#   - Tenant group  → read-only on their own tenant collection only
#   - All Users (1) → no access to any collection (default deny)
#
# The collection_graph is a singleton in Metabase. It must be imported on first
# use rather than created from scratch:
#
#   terraform import metabase_collection_graph.graph 1
#
# =============================================================================

resource "metabase_collection_graph" "graph" {
  # Ignore the Administrators group (id = 2) - its permissions cannot be changed.
  ignored_groups = [2]

  permissions = concat(
    # --- Global group: write access to the global collection -----------------
    [
      {
        group      = metabase_permissions_group.global.id
        collection = metabase_collection.global.id
        permission = "write"
      }
    ],

    # --- Global group: write access to every tenant collection ---------------
    [
      for key, col in local.tenant_collection_map : {
        group      = metabase_permissions_group.global.id
        collection = col.id
        permission = "write"
      }
    ],

    # --- Per-tenant group: read-only access to their own collection ----------
    [
      for key, tenant in var.tenants : {
        group      = metabase_permissions_group.tenant[key].id
        collection = local.tenant_collection_map[key].id
        permission = "read"
      } if contains(keys(local.tenant_collection_map), key)
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
#   - All Users (1)  → no query access to any database (baseline deny for everyone)
#   - Global group   → full query access (query-builder-and-native) to all databases
#   - Tenant group   → query-builder access to their own tenant DB only;
#                      no access to all other DBs
#
# This closes the gap that collection permissions alone cannot address: without
# this, a user scoped to the NC group can still browse the CO database directly
# via the Metabase query builder. This resource enforces data source isolation
# at the Metabase permission layer (in addition to PostgreSQL RLS).
#
# ⚠️  IMPORTANT — this resource is a singleton and must be imported before the
#    first apply (just like the collection graph):
#
#      terraform import metabase_permissions_graph.graph 1
#
# ⚠️  TRADE-OFF: The provider sends the *complete* graph to Metabase on every
#    apply. Every group × database pair must be listed here. Missing pairs are
#    sent as nil and will cause a 400 error. If a new built-in/sample database
#    appears in Metabase (e.g. after an upgrade), add it to ignored_groups or
#    enumerate it here.
#
# =============================================================================

locals {
  # All managed database IDs in one place for easy reuse across permission rules.
  all_db_ids = concat(
    [metabase_database.postgres.id],
    [for k, db in metabase_database.tenant_postgres : db.id],
    var.bigquery_enabled ? [metabase_database.bigquery[0].id] : []
  )

  # Databases that exist in Metabase but are NOT managed by Terraform
  # (e.g. Metabase's built-in H2 sample database). Must be included in the
  # complete graph to avoid a 400 from the API.
  unmanaged_db_ids = [1, 2]

  # Every database ID that must appear in the graph (managed + unmanaged).
  all_known_db_ids = concat(local.all_db_ids, local.unmanaged_db_ids)
}

resource "metabase_permissions_graph" "graph" {
  # Only ignore the Administrators group (id = 2) — its permissions cannot be
  # changed via the API. All other groups are explicitly enumerated below.
  ignored_groups = [2]

  # advanced_permissions = false uses the free-tier permission model (view_data
  # is always "unrestricted"; access is controlled via create_queries).
  advanced_permissions = false

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
      }
    ],

    # --- Global group: full access to all managed databases ------------------
    [
      for db_id in local.all_db_ids : {
        group          = metabase_permissions_group.global.id
        database       = tonumber(db_id)
        view_data      = "unrestricted"
        create_queries = "query-builder-and-native"
      }
    ],
    # Global group on unmanaged DBs: no access needed, but must be listed
    [
      for db_id in local.unmanaged_db_ids : {
        group          = metabase_permissions_group.global.id
        database       = tonumber(db_id)
        view_data      = "unrestricted"
        create_queries = "no"
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
          }
        ],
        # All other managed databases: no access
        [
          for db_id in local.all_db_ids : {
            group          = metabase_permissions_group.tenant[tenant_key].id
            database       = tonumber(db_id)
            view_data      = "unrestricted"
            create_queries = "no"
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
          }
        ]
      )
    ])
  )
}
