# MFB Data Dashboards

Metabase infrastructure deployed through terraform with multi-tenant analytics.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- BigQuery service account key at `../dbt/secrets/bigquerykey.json`

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

**3. Configure Terraform variables**

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Metabase admin credentials and GCP project
```

**4. Run Terraform to configure BigQuery and collections**

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

TODO: update with new dbt instructions

### 3. Deploy New Tenant

```bash
terraform plan  # Review changes
terraform apply  # Deploy new configuration
```

## Troubleshooting

### Dashboard shows "No data"

Verify database user exists and has correct `white_label_id` setting

### Connection errors

Check database host/credentials in `terraform.tfvars`

### Metabase auth issues

Verify Metabase admin credentials in `terraform.tfvars`

### BigQuery Connection Issues

1. **Service Account**: Ensure the service account key is mounted correctly at `../dbt/secrets/bigquerykey.json`
2. **Permissions**: Verify the service account has BigQuery Data Viewer permissions
3. **Project ID**: Double-check the GCP project ID in your configuration

### Performance Optimization

1. **Query Caching**: Enable caching in **Admin** > **Settings** > **Caching**
2. **Scheduled Refreshes**: Set up email subscriptions for regular dashboard updates
3. **Database Optimization**: Use dbt model materializations for faster queries
