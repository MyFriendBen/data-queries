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

Each tenant needs a dedicated database user that only has access to their white label data.

**Important:** Before running these commands:
- Replace `white_label_id` values with the correct IDs from your My Friend Ben database
- Update the database name (`mfb`) and credentials to match your local setup

```bash
# Set password as environment variable (keeps it out of shell history)
export DB_PASSWORD="secure_password"

psql -h localhost -U postgres -d mfb << EOF
-- Create user for North Carolina (example: white_label_id = 1)
CREATE USER nc WITH PASSWORD '$DB_PASSWORD';
ALTER USER nc SET rls.white_label_id = '1';
GRANT CONNECT ON DATABASE mfb TO nc;
GRANT USAGE ON SCHEMA public TO nc;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO nc;

-- Create user for Colorado (example: white_label_id = 7)
CREATE USER co WITH PASSWORD '$DB_PASSWORD';
ALTER USER co SET rls.white_label_id = '7';
GRANT CONNECT ON DATABASE mfb TO co;
GRANT USAGE ON SCHEMA public TO co;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO co;
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

**5. Run Terraform to configure BigQuery and collections**

```bash
terraform init
terraform plan
terraform apply
```

This creates the collections and dashboards in Metabase. Now when you go to localhost:3001, you should see the dashboards populated with data.

### Development Environment Configuration

By default, the setup uses:
- **Port 3001** for Metabase web interface
- **Database credentials:** username `metabase`, password `metabase`, database name `metabase`

These defaults are fine for local development since the database is only accessible on your machine.

**To customize:** Edit `docker-compose.yml` directly:
- **Port:** Line 9 - change `"3001:3000"` to use a different port
- **Database credentials:** Lines 12, 14-15 (Metabase config) and lines 36-38 (PostgreSQL config)

## Adding New Tenants

### 1. Add Tenant to Configuration

Edit `terraform.tfvars`:

```hcl
# Add new tenant
tenants = {
  nc = { name = "nc", display_name = "North Carolina" }
  co = { name = "co", display_name = "Colorado" }
  fl = { name = "fl", display_name = "Florida" }  # ← New tenant
}

# Add tenant database credentials
tenant_db_credentials = {
  nc = { username = "nc", password = "secure_password" }
  co = { username = "co", password = "secure_password" }
  fl = { username = "fl", password = "secure_password" }  # ← New credentials
}
```

### 2. Create Database User

Create a new database user with row-level security (see Quick Start step 3 for detailed instructions).

**Note:** Check your My Friend Ben database to find the correct `white_label_id` for the new tenant.

```bash
export DB_PASSWORD="secure_password"

psql -h localhost -U postgres -d mfb << EOF
-- Create user for Florida (example: white_label_id = 3)
CREATE USER fl WITH PASSWORD '$DB_PASSWORD';
ALTER USER fl SET rls.white_label_id = '3';
GRANT CONNECT ON DATABASE mfb TO fl;
GRANT USAGE ON SCHEMA public TO fl;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO fl;
EOF

unset DB_PASSWORD
```

### 3. Deploy New Tenant

```bash
terraform plan  # Review changes
terraform apply  # Deploy new configuration
```

## Troubleshooting

### Dashboard shows "No data"

Verify database user exists and has correct `white_label_id` setting

### Connection errors

Check credentials in `terraform.tfvars`
