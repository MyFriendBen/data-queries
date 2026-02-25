# MFB Data Dashboards

Metabase infrastructure deployed through terraform with multi-tenant analytics.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- BigQuery service account key saved to `./secrets/bigquerykey.json` (or customize path via `bigquery_service_account_key_path` in terraform.tfvars)

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

Each tenant needs a dedicated database user that only has access to their white-label data.

**Important:** Before running these commands:
- Replace `white_label_id` values with the correct IDs from your My Friend Ben database
- Update the database name (`benefit-Cal`) and credentials to match your local setup

```bash
# Set password as environment variable (keeps it out of shell history)
export DB_PASSWORD="secure_password"

psql -h localhost -U postgres -d mfb << EOF
-- Create user for North Carolina (white_label_id = 5)
CREATE USER nc WITH PASSWORD '$DB_PASSWORD';
ALTER USER nc SET rls.white_label_id = '5';
GRANT CONNECT ON DATABASE mfb TO nc;
GRANT USAGE ON SCHEMA analytics TO nc;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO nc;

-- Create user for Colorado (white_label_id = 1)
CREATE USER co WITH PASSWORD '$DB_PASSWORD';
ALTER USER co SET rls.white_label_id = '1';
GRANT CONNECT ON DATABASE mfb TO co;
GRANT USAGE ON SCHEMA analytics TO co;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO co;
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

**5. Run Terraform**

```bash
terraform init
terraform apply
```

Terraform will wait for Metabase to sync database schemas before creating cards and dashboards. This is configurable via `database_sync_wait_seconds` in terraform.tfvars (default: 60s, recommend 30s for local dev).

When complete, view your dashboards at http://localhost:3001!

### Development Environment Configuration

By default, the setup uses:
- **Port 3001** for Metabase web interface
- **Database credentials:** username `metabase`, password `metabase`, database name `metabase`

These defaults are fine for local development since the database is only accessible on your machine.

**To customize:** Edit `docker-compose.yml` directly:
- **Port:** Line 9 - change `"3001:3000"` to use a different port
- **Database credentials:** Lines 12, 14-15 (Metabase config) and lines 36-38 (PostgreSQL config)

## Terraform State: Local Dev vs Production

Terraform records every resource it manages in a **state file**. This project uses two different state backends depending on the environment.

### Local Development (default)

Local state works out of the box — no extra setup needed. When you run `terraform init` with no flags, Terraform stores state in `terraform.tfstate` on your machine. This file is gitignored and is only yours.

```bash
terraform init         # uses local state automatically
terraform plan
terraform apply
```

### Production (GCS remote backend)

Production uses a GCS bucket so that:
- **State locking** prevents two people from running `terraform apply` simultaneously and corrupting state
- **Shared access** lets any authorized team member deploy from the same known state
- **Security** keeps sensitive values (passwords, keys stored in state) off local machines and out of git

#### One-time GCS setup (done once per project, by an admin)

**1. Create the GCS bucket** with versioning enabled so state history is preserved:

```bash
gcloud storage buckets create gs://YOUR_BUCKET_NAME \
  --project=YOUR_GCP_PROJECT_ID \
  --location=US \
  --uniform-bucket-level-access \
  --versioning
```

Replace `YOUR_BUCKET_NAME` with a globally unique name (e.g. `mfb-terraform-state`) and `YOUR_GCP_PROJECT_ID` with the GCP project ID.

**2. Create your local backend config file** from the example:

```bash
cp backend-prod.hcl.example backend-prod.hcl
# Edit backend-prod.hcl and set the bucket name you just created
```

`backend-prod.hcl` is gitignored — it stays on your machine (or in CI secrets).

#### First-time migration (run once to move existing local state to GCS)

```bash
terraform init -backend-config=backend-prod.hcl -migrate-state
```

Terraform will ask: `Do you want to copy existing state to the new backend?` — answer **yes**. After this, the local `terraform.tfstate` file is no longer used for prod.

#### Ongoing prod workflow

```bash
terraform init -backend-config=backend-prod.hcl
terraform plan
terraform apply
```

State is now read from and written to GCS automatically. If another team member is running `terraform apply` at the same time, Terraform will display a locking error and exit safely rather than corrupting state.

#### Granting team members access to the state bucket

Each person deploying to prod needs the `roles/storage.objectAdmin` IAM role on the bucket:

```bash
gcloud storage buckets add-iam-policy-binding gs://YOUR_BUCKET_NAME \
  --member=user:teammate@example.com \
  --role=roles/storage.objectAdmin
```

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
tenant_db_credentials = {
  nc = { username = "nc", password = "secure_password" }
  co = { username = "co", password = "secure_password" }
  tx = { username = "tx", password = "secure_password" }  # ← New credentials
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

### 3. Create Database User

Create a new database user with row-level security (see Quick Start step 3 for detailed instructions).

**Note:** Check your My Friend Ben database to find the correct `white_label_id` for the new tenant.

```bash
export DB_PASSWORD="secure_password"

psql -h localhost -U postgres -d mfb << EOF
-- Create user for Texas (white_label_id = 40)
CREATE USER tx WITH PASSWORD '$DB_PASSWORD';
ALTER USER tx SET rls.white_label_id = '40';
GRANT CONNECT ON DATABASE mfb TO tx;
GRANT USAGE ON SCHEMA analytics TO tx;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO tx;
EOF

unset DB_PASSWORD
```

### 4. Deploy New Tenant

```bash
terraform plan  # Review changes
terraform apply  # Deploy new configuration
```

## Troubleshooting

### Dashboard shows "No data"

Verify database user exists and has correct `white_label_id` setting

### Connection errors

Check credentials in `terraform.tfvars`

### Switching Branches

FOR DEVELOPMENT PURPOSES ONLY - DO NOT USE THIS IN PRODUCTION

Terraform state can get out of sync when switching between branches that define different resources. To avoid errors, destroy the current infrastructure before checking out a new branch and re-apply after:

```bash
terraform destroy
git checkout <other-branch>
terraform apply
```