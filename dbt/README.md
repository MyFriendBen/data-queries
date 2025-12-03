# dbt Data Transformation

Dbt transforms raw screening data into analytics-ready tables with built-in row-level security for multi-tenant access.

The plan is to replace our existing data-queries pipeline with dbt for better maintainability and scalability.

## Quick Start

```bash
# 1. Copy and configure environment files
cp .env.example .env          # Edit with your database credentials
cp profiles.yml.example profiles.yml

# 2. Load environment and install dependencies
source load-env.sh
source venv/bin/activate
pip install -r requirements.txt
dbt deps

# 3. Run PostgreSQL models (default)
dbt build --target postgres

# 4. Or run BigQuery models (if configured)
dbt build --target bigquery
```

## Project Structure

```
dbt/
├── models/
│   ├── postgres/           # PostgreSQL models and sources
│   │   ├── sources.yml     # Django app data sources
│   │   ├── staging/        # Clean raw screening data
│   │   ├── intermediate/   # Add derived fields and business logic
│   │   └── marts/          # Analytics-ready tables with RLS
│   └── bigquery/           # BigQuery models and sources
│       ├── sources.yml     # Google Analytics data sources
│       ├── staging/        # Extract GA4 event_params (light transformations)
│       ├── intermediate/   # Add derived fields and business logic
│       └── marts/          # Analytics-ready tables
├── macros/
│   └── row_level_security.sql  # RLS policy setup
└── profiles.yml            # Database connections
```

**Two separate data pipelines:**

- **PostgreSQL**: Screening data from Django apps with row-level security
- **BigQuery**: Google Analytics data

## Common Commands

All commands require loading environment variables first:

```bash
# Load environment variables
source load-env.sh

# Activate virtual environment
source venv/bin/activate
```

### Daily Usage

```bash
# Build all models and run tests
dbt build --target postgres        # Run PostgreSQL models
dbt build --target bigquery        # Run BigQuery models

# Test database connections
dbt debug --target postgres        # Test PostgreSQL connection
dbt debug --target bigquery        # Test BigQuery connection

# Run specific models
dbt run --select MODEL_NAME --target postgres
dbt run --select MODEL_NAME --target bigquery

# Show data from models (preview)
dbt show --select MODEL_NAME --target postgres
dbt show --select MODEL_NAME --target bigquery
```

### Documentation and Maintenance

```bash
# Generate and view documentation
dbt docs generate
dbt docs serve     # View docs at localhost:8080

# Clean dbt artifacts
rm -rf target/ logs/
```

## Development

### Adding New Models

**PostgreSQL models** → Place in `models/postgres/`
**BigQuery models** → Place in `models/bigquery/`

Models automatically run only on their target database.

### Row-Level Security (PostgreSQL Only)

**How RLS Works:**

- **Regular users**: Only see data for their assigned `white_label_id`
- **Admin users**: Bypass RLS and see all data
- **Automatic filtering**: Database enforces access controls at query time

#### Adding RLS to PostgreSQL Models

All models with white label data should use RLS. Add this post-hook to enable row-level security:

```sql
{{
  config(
    materialized='table',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}
```

#### Creating Test Users for Local Development

⚠️ **For local development only.** Production user provisioning should be handled via infrastructure-as-code (Terraform, CI/CD pipelines, etc.) with proper secrets management.

Use `psql` to create test users with secure password handling:

```bash
# Option 1: Interactive password prompt (most secure - password not logged)
psql -h localhost -U postgres << 'EOF'
\prompt 'Enter password for user: ' user_password
CREATE USER nc WITH PASSWORD :'user_password';
ALTER USER nc SET rls.white_label_id = '1';
GRANT CONNECT ON DATABASE your_database TO nc;
GRANT USAGE ON SCHEMA your_schema TO nc;
GRANT SELECT ON ALL TABLES IN SCHEMA your_schema TO nc;
EOF

# Option 2: Using environment variable (keeps password out of shell history)
export DB_PASSWORD="secure_password"
psql -h localhost -U postgres << EOF
-- Create user for North Carolina (white_label_id = 1)
CREATE USER nc WITH PASSWORD '$DB_PASSWORD';
ALTER USER nc SET rls.white_label_id = '1';
GRANT CONNECT ON DATABASE your_database TO nc;
GRANT USAGE ON SCHEMA your_schema TO nc;
GRANT SELECT ON ALL TABLES IN SCHEMA your_schema TO nc;

-- Create user for Colorado (white_label_id = 7)
CREATE USER co WITH PASSWORD '$DB_PASSWORD';
ALTER USER co SET rls.white_label_id = '7';
GRANT CONNECT ON DATABASE your_database TO co;
GRANT USAGE ON SCHEMA your_schema TO co;
GRANT SELECT ON ALL TABLES IN SCHEMA your_schema TO co;

-- Create admin user with BYPASSRLS (sees all data)
CREATE USER admin_user WITH PASSWORD '$DB_PASSWORD' BYPASSRLS;
GRANT CONNECT ON DATABASE your_database TO admin_user;
GRANT USAGE ON SCHEMA your_schema TO admin_user;
GRANT SELECT ON ALL TABLES IN SCHEMA your_schema TO admin_user;
EOF
unset DB_PASSWORD
```

**Note:** Replace `your_database` and `your_schema` with your actual database and schema names. The specific `white_label_id` values depend on your data.


## BigQuery Setup (Optional)

To use BigQuery for Google Analytics data, ask a teammate for the connection details. Or you can set it up yourself:

1. **Create GCP Service Account**:

   - Go to GCP Console → IAM & Admin → Service Accounts
   - Create new service account with BigQuery permissions:
     - BigQuery Data Editor
     - BigQuery Job User
   - Download JSON key file

2. **Configure Environment Variables**:

   Add to your `.env` file:

   ```bash
   GCP_PROJECT_ID=your-gcp-project-id
   GOOGLE_APPLICATION_CREDENTIALS=/path/to/your/service-account-key.json
   ```

   💡 **Tip**: Put your service account JSON file in the `secrets/` directory:

   ```bash
   GOOGLE_APPLICATION_CREDENTIALS=/Users/ktwork/Dev/mfb/mfb-analytics/dbt/secrets/bigquerykey.json
   ```

3. **Test BigQuery Connection**:
   ```bash
   dbt debug --target bigquery
   dbt build --target bigquery
   ```
