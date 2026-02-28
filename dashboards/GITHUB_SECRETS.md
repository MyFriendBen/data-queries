# GitHub Secrets and Variables Setup

This document lists all secrets and variables needed for Terraform workflows.

## How to Add Secrets/Variables

1. Go to your repository: https://github.com/MyFriendBen/data-queries
2. Navigate to **Settings → Secrets and variables → Actions**
3. Create two **Environments**: `staging` and `production`
4. Add the secrets/variables below to each environment

---

## Environment: `staging`

### Getting Your Staging Database Credentials

Staging uses the default Heroku Postgres credential for all Metabase database connections (Essential-tier doesn't support custom credentials).

```bash
# Get the default credential (host, user, password, database name)
heroku pg:credentials:url -a cobenefits-api-staging
```

Use the same user/password for `GLOBAL_DB_*`, `NC_DB_*`, and `CO_DB_*` secrets below.

### Variables (Settings → Environments → staging → Variables)

| Variable Name | Description | Example Value |
|---------------|-------------|---------------|
| `METABASE_URL` | Staging Metabase URL | `https://mfb-metabase-staging-0805953c70da.herokuapp.com` |
| `METABASE_ADMIN_EMAIL` | Admin email from setup wizard | `admin@myfriendben.org` |
| `DATABASE_NAME` | Staging database name | From `heroku pg:credentials:url` output |
| `GCP_PROJECT_ID` | Google Cloud project ID | `mfb-data` |

### Secrets (Settings → Environments → staging → Secrets)

| Secret Name | Description | How to Get It |
|-------------|-------------|---------------|
| `METABASE_ADMIN_PASSWORD` | Admin password from setup wizard | From the Metabase wizard you completed |
| `DATABASE_HOST` | Staging Django database hostname | From `heroku pg:credentials:url` output |
| `GLOBAL_DB_USER` | Database user for global dashboard | From `heroku pg:credentials:url` (default user) |
| `GLOBAL_DB_PASS` | Database password for global dashboard | From `heroku pg:credentials:url` (default password) |
| `NC_DB_USER` | Database user for NC tenant | Same as `GLOBAL_DB_USER` (single credential on staging) |
| `NC_DB_PASS` | Database password for NC tenant | Same as `GLOBAL_DB_PASS` (single credential on staging) |
| `CO_DB_USER` | Database user for CO tenant | Same as `GLOBAL_DB_USER` (single credential on staging) |
| `CO_DB_PASS` | Database password for CO tenant | Same as `GLOBAL_DB_PASS` (single credential on staging) |
| `BIGQUERY_SA_KEY` | BigQuery service account JSON key | Full JSON content of your service account key file |

---

## Environment: `production`

Same secrets/variables as staging, but with **production values**:
- Different `METABASE_URL` (production Metabase)
- Different `DATABASE_HOST` (production database)
- Different admin password
- Same `BIGQUERY_SA_KEY` and `GCP_PROJECT_ID` (unless using separate GCP projects)

### Production Database Users (RLS)

If your production database is Standard-tier or higher, create separate RLS users for proper tenant isolation:

```bash
# Create credentials via Heroku CLI (Standard-tier and above only)
heroku pg:credentials:create -a <your-production-django-app> --name analytics_admin
heroku pg:credentials:create -a <your-production-django-app> --name nc
heroku pg:credentials:create -a <your-production-django-app> --name co

# Get the credentials
heroku pg:credentials:url -a <your-production-django-app> --name analytics_admin
heroku pg:credentials:url -a <your-production-django-app> --name nc
heroku pg:credentials:url -a <your-production-django-app> --name co
```

Then connect via `heroku pg:psql` to configure RLS and grants:

```sql
-- Grant schema access
GRANT USAGE ON SCHEMA analytics TO analytics_admin, nc, co;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO analytics_admin, nc, co;

-- Set RLS config for tenant users
ALTER USER nc SET rls.white_label_id = '5';
ALTER USER co SET rls.white_label_id = '1';

-- Auto-grant on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics
  GRANT SELECT ON TABLES TO nc, co, analytics_admin;
```

Use these separate credentials for `GLOBAL_DB_*`, `NC_DB_*`, and `CO_DB_*` secrets in the production environment.

---

## Prerequisite: Analytics Schema

Ensure the `analytics` schema exists in both staging and production databases:

```bash
heroku pg:psql -a <your-django-app-name>
```

```sql
CREATE SCHEMA IF NOT EXISTS analytics;
```

---

## Checklist

### Staging
- [ ] Create `staging` GitHub Environment
- [ ] Ensure `analytics` schema exists in staging database
- [ ] Run `heroku pg:credentials:url -a cobenefits-api-staging` to get credentials
- [ ] Add all Variables to staging environment
- [ ] Add all Secrets to staging environment (use default credential for all DB secrets)

### Production (Later)
- [ ] Create `production` GitHub Environment
- [ ] Create RLS database users (if Standard-tier or above)
- [ ] Add all Variables and Secrets to production environment

---

## Testing the Setup

Once secrets are configured:
1. Push and merge the workflow files to `main`
2. The `terraform-apply` workflow will run automatically against staging
3. Check the Actions tab to see the run
4. Verify Metabase has the data sources and dashboards configured
