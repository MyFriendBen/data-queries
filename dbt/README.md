# dbt Data Transformation

dbt transforms raw screening data into analytics-ready tables with built-in row-level security for multi-tenant access.

The plan is to replace our existing data-queries pipeline with this dbt project for better maintainability and scalability.

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
│   │   └── marts/          # Analytics-ready tables with RLS
│   └── bigquery/           # BigQuery models and sources
│       ├── sources.yml     # Google Analytics data sources
│       ├── staging/        # Clean GA4 data
│       └── marts/          # Analytics-ready tables
├── macros/
│   └── row_level_security.sql  # RLS user management
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

### Row-Level Security (PostgreSQL Only)

Create tenant-specific database users with row-level security:

Note: the specific ids will depend on your data.

```bash
# Create user for North Carolina (white_label_id = 1)
dbt run-operation create_rls_user --vars '{"username": "nc", "password": "secure_password", "white_label_access": 1}'

# Create user for Colorado (white_label_id = 7)
dbt run-operation create_rls_user --vars '{"username": "co", "password": "secure_password", "white_label_access": 7}'

# Create admin user (sees all data)
dbt run-operation create_rls_user --vars '{"username": "admin_user", "password": "admin_password", "white_label_access": "ADMIN"}'
```

**How RLS Works:**

- **Regular users**: Only see data for their assigned `white_label_id`
- **Admin users**: Bypass RLS and see all data
- **Automatic filtering**: Database enforces access controls at query time

## Development

### Adding New Models

**PostgreSQL models** → Place in `models/postgres/`
**BigQuery models** → Place in `models/bigquery/`

Models automatically run only on their target database.

### Adding RLS to PostgreSQL Models

Add this post-hook to enable row-level security:

```sql
{{
  config(
    materialized='table',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}
```

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
