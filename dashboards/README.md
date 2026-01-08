# Infrastructure & Analytics Platform

Terraform configuration for Metabase infrastructure and multi-tenant analytics with BigQuery integration.

## Quick Start

```bash
# 1. Copy and configure environment files
cp .env.example .env
cp terraform.tfvars.example terraform.tfvars

# Edit both files with your configuration

# 2. Run automated setup
./setup-metabase.sh
```

The setup script will:

1. Start Metabase and PostgreSQL containers via Docker Compose
2. Wait for Metabase to be ready
3. Prompt you to complete the initial setup wizard (if needed)
4. Automatically configure BigQuery datasource and collections via Terraform

## 5. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

This creates:

- BigQuery datasource in Metabase
- Metabase collections for multi-tenant organization

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

Verify Metabase admin credentials in both `.env` and `terraform.tfvars`

### BigQuery Connection Issues

1. **Service Account**: Ensure the service account key is mounted correctly at `../dbt/secrets/bigquerykey.json`
2. **Permissions**: Verify the service account has BigQuery Data Viewer permissions
3. **Project ID**: Double-check the GCP project ID in your configuration

### Performance Optimization

1. **Query Caching**: Enable caching in **Admin** > **Settings** > **Caching**
2. **Scheduled Refreshes**: Set up email subscriptions for regular dashboard updates
3. **Database Optimization**: Use dbt model materializations for faster queries
