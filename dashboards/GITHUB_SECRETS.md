# GitHub Secrets and Variables Setup

This document lists all secrets and variables needed for Terraform workflows.

## How to Add Secrets/Variables

### Step 1: Create Environments

Environments are managed in **repository settings**, not the Actions dashboard.

1. Go to **Settings → Environments**: https://github.com/MyFriendBen/data-queries/settings/environments
2. Click **"New environment"**, name it `staging`, click **"Configure environment"**
3. Repeat to create a `production` environment

### Step 2: Add Secrets and Variables

Within each environment's settings page:
- Click **"Add environment secret"** to add secrets
- Click **"Add environment variable"** to add variables
- Add the secrets/variables listed below for each environment

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

| Variable Name | Description | Value |
|---------------|-------------|-------|
| `METABASE_URL` | Staging Metabase URL | `https://mfb-metabase-staging-0805953c70da.herokuapp.com` |
| `METABASE_ADMIN_EMAIL` | Admin email from setup wizard | (your admin email) |
| `DATABASE_NAME` | Staging database name | From `heroku pg:credentials:url` output |
| `GCP_PROJECT_ID` | Google Cloud project ID | `mfb-data` |
| `BIGQUERY_ENABLED` | Enable BigQuery data source | `false` (see [BigQuery section](#bigquery-authentication-blocked)) |

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

---

## BigQuery Authentication (Blocked)

BigQuery integration is currently **disabled** due to a GCP organization policy (`iam.disableServiceAccountKeyCreation`) that prevents creating service account keys.

### Current State
- `BIGQUERY_ENABLED` variable is set to `false`
- Terraform skips all BigQuery resources (data source, cards, dashboard widgets)
- Postgres dashboards work without it

### To Enable BigQuery Later

Two approaches to resolve, depending on how Metabase and GitHub Actions authenticate:

#### For GitHub Actions (Terraform + dbt):
Use **Workload Identity Federation** — no service account key needed:
1. Create a Workload Identity Pool in GCP Console
2. Add an OIDC provider for GitHub (`https://token.actions.githubusercontent.com`)
3. Grant BigQuery Data Viewer + Job User roles
4. Update workflows to use `google-github-actions/auth@v2`

#### For Metabase on Heroku (runtime BigQuery access):
Metabase runs on Heroku and needs persistent credentials. Options:
1. **Ask an org admin** to create a one-time exception for a service account key
2. **Use a BigQuery proxy** that supports Workload Identity
3. **Move Metabase to GCP** (Cloud Run) where it can use attached service accounts

### When Ready to Enable:
1. Add `BIGQUERY_SA_KEY` secret to the environment (full JSON content of the service account key)
2. Change `BIGQUERY_ENABLED` variable to `true`
3. Run `terraform apply` — BigQuery data source and cards will be created automatically

---

## Environment: `production`

Same secrets/variables as staging, but with **production values**:
- Different `METABASE_URL` (production Metabase)
- Different `DATABASE_HOST` (production database)
- Different admin password
- Same `GCP_PROJECT_ID` (unless using separate GCP projects)
- `BIGQUERY_ENABLED` = `false` until BigQuery auth is resolved

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
- [ ] Add all Variables to staging environment (set `BIGQUERY_ENABLED` to `false`)
- [ ] Add all Secrets to staging environment (use default credential for all DB secrets)
- [ ] Push and merge workflow files to `main`
- [ ] Verify `terraform-apply` workflow runs successfully

### Production (Later)
- [ ] Create `production` GitHub Environment
- [ ] Create RLS database users (if Standard-tier or above)
- [ ] Add all Variables and Secrets to production environment
- [ ] Deploy Metabase to production via pipeline promotion
- [ ] Complete production Metabase setup wizard
- [ ] Run `terraform-apply` workflow with `production` environment

### BigQuery (Deferred)
- [ ] Resolve GCP org policy for service account keys (or set up Workload Identity Federation)
- [ ] Add `BIGQUERY_SA_KEY` secret to both environments
- [ ] Set `BIGQUERY_ENABLED` to `true` in both environments
- [ ] Run `terraform apply` to create BigQuery data sources
