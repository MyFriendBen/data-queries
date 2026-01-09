# Infrastructure & Analytics Platform

Terraform configuration for Metabase infrastructure and multi-tenant analytics with BigQuery integration.

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
cd ../terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Metabase admin credentials and GCP project
```

**4. Run Terraform to configure BigQuery and collections**

```bash
terraform init
terraform plan
terraform apply
```

This creates:

- BigQuery datasource in Metabase
- Metabase collections for multi-tenant organization

### Development Environment Configuration

By default, the setup uses:
- **Port 3001** for Metabase web interface
- **"metabase"** for all PostgreSQL credentials (database name, user, and password)

This is fine for local development since the database is only accessible on your machine.

#### Customizing the Port

**When to customize:** If port 3001 is already in use by another application, Docker Compose will fail with a "port is already allocated" error.

**How to customize:** Set the `METABASE_PORT` environment variable before running setup:

```bash
export METABASE_PORT=3002
bash ./setup-metabase.sh
```

The setup script will automatically use your custom port for the Metabase URL.

#### Customizing Database Credentials (Optional)

You can also customize the PostgreSQL database credentials if needed:

```bash
export METABASE_DB_NAME=my_db
export METABASE_DB_USER=my_user
export METABASE_DB_PASS=my_secure_password
bash ./setup-metabase.sh
```

#### Using a .env file

Alternatively, create a `.env` file in the `dashboards` directory with your customizations:

```bash
METABASE_PORT=3002
METABASE_DB_NAME=my_db
METABASE_DB_USER=my_user
METABASE_DB_PASS=my_secure_password
```

Then run the setup script as normal.

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
