# dbt Data Transformation

Dbt transforms raw screening data into analytics-ready tables with built-in row-level security for multi-tenant access.

The plan is to replace our existing data-queries pipeline with dbt for better maintainability and scalability.

## Quick Start

```bash
# 1. Copy and configure environment files
cd dbt
cp .env.example .env          # Edit with your database credentials
cp profiles.yml.example profiles.yml

# 2. Load environment and install dependencies
source load-env.sh

# Create a virtual environment using the following command
python3 -m venv venv

# Activate the virtual environment
# For Mac/Linux/Git Bash:
source venv/bin/activate
# For Windows PowerShell:
# .\venv\Scripts\Activate.ps1

# Install all the packages
pip install -r requirements.txt

# Install the dependencies specified in packages.yml file
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

⚠️ **For local development only.** Production credentials are provisioned via `heroku pg:credentials:create`.

RLS uses **username-based filtering** — the policy extracts the `white_label_id` from the connecting role's name via `regexp_match(current_user, '^wl_[a-z_]+_([0-9]+)_ro$')`. Only roles matching the `wl_<state>_<white_label_id>_ro` convention see data; non-conforming roles get zero rows.

The dbt build user (table owner) bypasses RLS automatically in PostgreSQL — no special handling needed.

```sql
-- Connect as your local superuser (e.g. postgres or your OS username)
-- Create passwordless roles for local development

CREATE ROLE wl_nc_5_ro LOGIN;          -- NC, white_label_id = 5
CREATE ROLE wl_co_1_ro LOGIN;          -- CO, white_label_id = 1
CREATE ROLE wl_tx_40_ro LOGIN;         -- TX, white_label_id = 40
CREATE ROLE wl_il_39_ro LOGIN;         -- IL, white_label_id = 39
CREATE ROLE wl_ma_38_ro LOGIN;         -- MA, white_label_id = 38
CREATE ROLE wl_cesn_4_ro LOGIN;        -- CESN, white_label_id = 4
CREATE ROLE wl_co_tax_calculator_3_ro LOGIN;  -- CO Tax Calculator, white_label_id = 3

-- Grant access to the analytics schema
GRANT USAGE ON SCHEMA analytics TO wl_nc_5_ro, wl_co_1_ro, wl_tx_40_ro,
  wl_il_39_ro, wl_ma_38_ro, wl_cesn_4_ro, wl_co_tax_calculator_3_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO wl_nc_5_ro, wl_co_1_ro,
  wl_tx_40_ro, wl_il_39_ro, wl_ma_38_ro, wl_cesn_4_ro, wl_co_tax_calculator_3_ro;
```

**Verifying RLS:**

```sql
SET ROLE wl_nc_5_ro;
SELECT count(*), white_label_id FROM analytics.mart_screener_data GROUP BY white_label_id;
-- Should show only white_label_id = 5
RESET ROLE;
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
