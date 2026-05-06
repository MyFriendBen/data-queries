# MFB Data Dashboards

Metabase infrastructure deployed through terraform with multi-tenant analytics.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- BigQuery service account key (see [BigQuery Setup](#bigquery-setup) below)

### Setup Steps

**1. Start Metabase containers**

```bash
bash ./setup-metabase.sh
```

This will:

- Start Metabase and PostgreSQL containers via Docker Compose
- Wait for Metabase to be ready (may take 1-2 minutes)
- Check if initial setup is complete

**2. Complete Metabase initial setup**

Open http://localhost:3001 in your browser (or the URL shown by the setup script) and complete the setup wizard:

- Create admin account
- Skip database connection (we'll configure with Terraform)
- Complete the initial setup

**3. Create tenant database users with row-level security**

Each tenant needs a dedicated database role whose name encodes the `white_label_id`. RLS uses **username-based filtering** — the policy extracts the `white_label_id` from the connecting role's name. Only roles matching the `wl_<state>_<white_label_id>_ro` convention see their tenant's data; non-conforming roles get zero rows.

**Important:** Before running these commands:
- Replace `white_label_id` values with the correct IDs from your MyFriendBen database
- Update the database name (`mfb`) and credentials to match your local setup

```bash
# Set password as environment variable (keeps it out of shell history)
export DB_PASSWORD="secure_password"

psql -h localhost -U postgres -d mfb << EOF
-- Create role for North Carolina (white_label_id = 5)
CREATE ROLE wl_nc_5_ro WITH LOGIN PASSWORD '$DB_PASSWORD';
GRANT CONNECT ON DATABASE mfb TO wl_nc_5_ro;
GRANT USAGE ON SCHEMA analytics TO wl_nc_5_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO wl_nc_5_ro;

-- Create role for Colorado (white_label_id = 1)
CREATE ROLE wl_co_1_ro WITH LOGIN PASSWORD '$DB_PASSWORD';
GRANT CONNECT ON DATABASE mfb TO wl_co_1_ro;
GRANT USAGE ON SCHEMA analytics TO wl_co_1_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO wl_co_1_ro;
EOF

unset DB_PASSWORD
```

**4. Configure Terraform variables**

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with:
# - Your Metabase admin credentials (from step 2)
# - Database credentials for each tenant (from step 3)
# - GCP project ID for BigQuery
# Note: BigQuery key path defaults to ./secrets/bigquerykey.json (no need to set if using default location)
```

**5. Initialize and run Terraform**

> **Running locally?** This project is configured to use HCP Terraform (Terraform Cloud) by default. To run locally instead, use the gitignored `local_override.tf` file (see [Local Terraform State for Development](#local-terraform-state-for-development) below) — this overrides the backend without touching `main.tf`, so there's no risk of accidentally committing a broken cloud config.

The setup requires a specific sequence because the singleton permission graphs (`metabase_collection_graph` and `metabase_permissions_graph`) must be imported *after* Metabase has created the default groups and databases — which only happens on the first `apply`.

Run these commands in order:

```bash
# Step 1: Install providers
terraform init

# Step 2: Create databases, groups, collections, and cards.
# This also triggers Metabase to sync schemas and create its built-in groups/objects.
terraform apply -auto-approve

# Step 3: Import the permissions graph singleton into Terraform state.
# (Must happen after apply so Metabase's default groups and databases exist.)
terraform import metabase_permissions_graph.graph 1

# Step 4: Re-import the collection graph singleton.
# The first apply may have left it in an inconsistent state — remove and re-import.
terraform state rm metabase_collection_graph.graph
terraform import metabase_collection_graph.graph 1

# Step 5: Final apply to reconcile any remaining state differences.
terraform apply -auto-approve
```

Terraform will wait for Metabase to sync database schemas before creating cards and dashboards. This is configurable via `database_sync_wait_seconds` in terraform.tfvars (default: 60s, recommend 30s for local dev).

When complete, view your dashboards at http://localhost:3001!

> **Already imported?** If you see `Error: Resource already managed by Terraform` on an import, that resource is already in state — skip that import. Verify with:
> ```bash
> terraform state list | grep -E "collection_graph|permissions_graph"
> ```
> Both `metabase_collection_graph.graph` and `metabase_permissions_graph.graph` (without the `data.` prefix) should be present before the final apply.

### Development Environment Configuration

By default, the setup uses:
- **Port 3001** for Metabase web interface
- **Database credentials:** username `metabase`, password `metabase`, database name `metabase`

These defaults are fine for local development since the database is only accessible on your machine.

**To customize:** Edit `docker-compose.yml` directly:
- **Port:** Line 9 - change `"3001:3000"` to use a different port
- **Database credentials:** Lines 12, 14-15 (Metabase config) and lines 36-38 (PostgreSQL config)

## Managing User Access

Access to Metabase dashboards is controlled through **permission groups**. Terraform creates and configures these groups automatically — the only ongoing manual task is assigning users to the right group(s) in the Metabase UI.

### Groups

| Group | Access |
|---|---|
| **Global Viewers** | All dashboards: Global collection + every tenant collection + all databases |
| **North Carolina Viewers** | NC collection and NC database only |
| **Colorado Viewers** | CO collection and CO database only |
| *(new tenant)* | `<Display Name> Viewers` — automatically created for every entry in `var.tenants` |

A user can belong to more than one group. For example, a user who manages both NC and CO can be in both the NC and CO groups.

### Assigning Users to Groups

1. In Metabase, go to **Admin → People**
2. Click on a user and select **Edit groups**
3. Add them to the appropriate group(s)

The Terraform output `tenant_group_ids` lists the numeric ID of each tenant group, and `global_group_id` lists the Global group ID — useful when scripting bulk user assignments via the Metabase API.

### Permission Model

Both collection and data permissions are managed by Terraform:

| Group | Collections | Query Builder (Data Sources) |
|---|---|---|
| **Global Viewers** | `read` on Global + all tenant collections | Full access (`query-builder-and-native`) to all databases |
| **Tenant Viewers** (e.g. NC Viewers) | `read` on their own collection only | `query-builder` access to their own tenant DB only; no access to all others |
| **All Users (built-in)** | No access | No access (baseline deny for all databases) |

Data isolation is enforced at two layers:
1. **Metabase data permissions** (managed here) — tenant group users cannot access other tenants' databases via the query builder.
2. **PostgreSQL RLS** — within a given database connection, users can only see rows matching their own `white_label_id`.

## Adding New Tenants

### 1. Add Tenant to Configuration

Edit `terraform.tfvars`:

```hcl
# Add new tenant
tenants = {
  nc = { name = "nc", display_name = "North Carolina" }
  co = { name = "co", display_name = "Colorado" }
  tx = { name = "tx", display_name = "Texas" }  # ← New tenant
}

# Add tenant database credentials
# Convention: wl_<state>_<white_label_id>_ro — RLS policy extracts white_label_id from the username
tenant_db_credentials = {
  nc = { username = "wl_nc_5_ro",  password = "secure_password" }
  co = { username = "wl_co_1_ro",  password = "secure_password" }
  tx = { username = "wl_tx_40_ro", password = "secure_password" }  # ← New credentials
}
```

### 2. Add Tenant Collection Resource

Edit `metabase.tf` to add a new collection resource. Collections must be created sequentially to avoid a Metabase race condition.

**Why sequential creation?** Metabase's API has a race condition when creating multiple collections concurrently. Each collection creation updates an internal `collection_permission_graph_revision` table, and parallel requests can attempt to insert the same revision ID, causing a duplicate key error. Using Terraform's `for_each` to create collections in parallel triggers this issue. The workaround is to create each collection as a separate resource with chained `depends_on` to ensure sequential creation.

Add a new collection resource that depends on the last existing one:

```hcl
# In metabase.tf - add after the last tenant collection resource

resource "metabase_collection" "tenant_collection_tx" {
  name       = "Texas"
  depends_on = [metabase_collection.tenant_collection_co]  # ← Chain to previous
}
```

Then add it to the `tenant_collection_map` local:

```hcl
locals {
  tenant_collection_map = {
    nc = metabase_collection.tenant_collection_nc
    co = metabase_collection.tenant_collection_co
    tx = metabase_collection.tenant_collection_tx  # ← Add new entry
  }
}
```

> **Note on permissions:** The `metabase_permissions_group.tenant`, collection permission entries, and data permission entries in `permissions.tf` all use `for_each`/`for` over `var.tenants`, so the new group, its collection permissions, and its data source permissions are all created automatically. No changes to `permissions.tf` are needed.

### 3. Create Database Role

Create a new database role with row-level security (see Quick Start step 3 for detailed instructions).

**Note:** Check your MyFriendBen database to find the correct `white_label_id` for the new tenant.

```bash
# Set password as environment variable (keeps it out of shell history)
export DB_PASSWORD="secure_password"

psql -h localhost -U postgres -d mfb << EOF
-- Create role for Texas (white_label_id = 40)
CREATE ROLE wl_tx_40_ro WITH LOGIN PASSWORD '$DB_PASSWORD';
GRANT CONNECT ON DATABASE mfb TO wl_tx_40_ro;
GRANT USAGE ON SCHEMA analytics TO wl_tx_40_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO wl_tx_40_ro;
EOF

unset DB_PASSWORD
```

### 4. Deploy New Tenant

```bash
terraform plan   # Review changes
terraform apply  # Deploy new configuration
```

Terraform will automatically:
- Create the new `<Display Name> Viewers` permissions group
- Grant it `read` access to the new tenant collection
- Grant it `query-builder` access to the new tenant database only
- Grant the Global Viewers group `read` access to the new collection and `query-builder-and-native` access to the new tenant database

After deploying, assign users to the new group in Metabase: **Admin → People → [user] → Edit groups**.


## Local Terraform State for Development

CI/CD uses Terraform Cloud for state (configured in `main.tf`). Running
`terraform init` locally will fail with a token error unless you override the
backend using a gitignored override file.

**1. Copy the example override file:**

```bash
cp local_override.tf.example local_override.tf
```

**2. Initialize Terraform:**

```bash
terraform init    # uses local state, no Terraform Cloud token needed
```

`terraform plan` and `terraform apply` require a locally running Metabase
instance — see the Quick Start section above for that setup.

`local_override.tf` is gitignored — CI/CD never sees it, so GitHub Actions
continues using Terraform Cloud for staging and production.

## BigQuery Setup

The Google Analytics tab requires a BigQuery connection. To enable it locally:

**1. Get the service account key from 1Password**

Find the **"Data Dashboards BigQuery Key (Localhost)"** entry in the MyFriendBen 1Password vault. Copy the JSON content and save it:

```bash
mkdir -p secrets
# Create secrets/bigquerykey.json and paste the JSON content into it.
# macOS example:
# pbpaste > secrets/bigquerykey.json
```

**2. Enable BigQuery in Terraform**

In `terraform.tfvars`, set:

```hcl
bigquery_enabled = true
```

**3. Restart Metabase and apply**

```bash
docker restart metabase
terraform apply
```

The first apply after enabling BigQuery may need a second run — Metabase takes a moment to sync the BigQuery schema before Terraform can reference its tables.

> **Important:** The BigQuery service account key grants direct access to MyFriendBen analytics data. Do not share it with anyone outside of MyFriendBen.
>
> The `secrets/` directory is gitignored. Never commit service account keys to the repository.

## Troubleshooting

### Dashboard shows "No data"

Verify database user exists and has correct `white_label_id` setting

### Connection errors

Check credentials in `terraform.tfvars`

### Permissions graph: stale state (409)

```
Status code: 409, body: Looks like someone else edited the permissions and your data is out of date.
```

Terraform's cached state is behind Metabase's current revision (happens after manual UI changes). Re-import both graphs to get fresh state, then apply:

```bash
terraform state rm metabase_permissions_graph.graph
terraform import metabase_permissions_graph.graph 1

terraform state rm metabase_collection_graph.graph
terraform import metabase_collection_graph.graph 1

terraform apply
```

### Permissions graph: unmarshal crash

```
json: cannot unmarshal object into Go struct field PermissionsGraphDatabasePermissions.groups.create-queries
```

A group in Metabase has schema-level (per-schema) query permissions instead of a flat top-level value. This is a provider bug — the provider crashes reading that format.

**Step 1: Identify the problem group**

```bash
TOKEN=$(curl -s -X POST http://localhost:3001/api/session \
  -H "Content-Type: application/json" \
  -d '{"username":"<admin_email>","password":"<password>"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

curl -s http://localhost:3001/api/permissions/graph \
  -H "X-Metabase-Session: $TOKEN" | python3 -m json.tool | grep -A3 "create-queries"
```

Look for a `create-queries` value that is an object `{}` rather than a plain string like `"query-builder"`.

**Step 2: Fix it in the Metabase UI**

Go to Admin → Permissions, find the group, and change its database query permission from schema-level to a top-level value (e.g. "Query builder only").

> **Note:** The codebase includes a workaround that prevents this crash during initial `terraform apply`. However, `terraform import` still hits the provider bug directly — fixing the permissions in the UI (Step 2) is always required before running imports.

**Step 3: Re-import and apply**

```bash
terraform state rm metabase_permissions_graph.graph
terraform import metabase_permissions_graph.graph 1

terraform state rm metabase_collection_graph.graph
terraform import metabase_collection_graph.graph 1

terraform apply
```

**Notes:** 
- If you see a 400 `nil view-data` error during `terraform apply` after a manually created group exists in Metabase, delete that group from the Metabase UI and re-run apply. This is a provider bug where `ignored_groups` does not correctly preserve unmanaged group permissions during write operations.
- **Never use `terraform destroy` in staging or production.** It deletes all dashboards, cards, collections, and groups — breaking existing user bookmarks, saved URLs, and any manual UI configuration not managed by Terraform. For staging/production, always use the surgical approach: fix the issue in the Metabase UI, re-import affected resources, and run `terraform apply`.

### Switching Branches

FOR DEVELOPMENT PURPOSES ONLY - DO NOT USE THIS IN PRODUCTION

Terraform state can get out of sync when switching between branches that define different resources. To avoid errors, destroy the current infrastructure before checking out a new branch and re-apply after:

```bash
terraform destroy
git checkout <other-branch>
terraform apply
```
