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
      for key, col in local.tenant_collection_map : {
        group      = metabase_permissions_group.tenant[key].id
        collection = col.id
        permission = "read"
      }
    ]
  )
}

# =============================================================================
# Data Permissions Graph
# =============================================================================
#
# NOTE: We intentionally do NOT manage metabase_permissions_graph here.
#
# Reasons:
#   1. The provider sends the *complete* graph to Metabase on every apply,
#      including pre-existing group/database pairs (e.g. Metabase's built-in
#      sample databases). Any pair not listed in our config is sent with
#      view_data = nil, causing a 400 error from the API.
#
#   2. Data isolation is already enforced at the database level via
#      row-level security (RLS) — each tenant DB user can only see their
#      own white-label data. Metabase data permissions would be a redundant
#      second layer.
#
#   3. Collection permissions (managed by metabase_collection_graph above)
#      are sufficient to control which dashboards each group can see.
#
# If data-level permissions are needed in the future (e.g. to restrict
# which groups can run ad-hoc queries), import the graph and explicitly
# enumerate *all* group/database pairs including Metabase built-ins:
#
#   terraform import metabase_permissions_graph.graph 1
#
# =============================================================================
