# GitHub Secrets and Variables Setup

This document lists all secrets and variables needed for Terraform workflows.

## Why Secrets Live Where They Do

Secrets and variables are stored at different levels based on scope and sensitivity:

| Storage Level | What Goes Here | Why |
|---------------|---------------|-----|
| **Repository-level secrets** | `TF_API_TOKEN` | Authenticates to Terraform Cloud. One token accesses all workspaces. Stored at the repo level so all workflows can use it. |
| **Environment variables** | `METABASE_URL`, `METABASE_ADMIN_EMAIL`, `DATABASE_NAME`, `BIGQUERY_ENABLED`, `GCP_PROJECT_ID` | Non-sensitive, environment-specific configuration. Variables are visible in logs and workflow files. |
| **Environment secrets** | `METABASE_ADMIN_PASSWORD`, `DATABASE_HOST`, all `*_DB_USER`/`*_DB_PASS` | Sensitive credentials. GitHub encrypts these and masks them in logs. |
| **Heroku config vars** | `MB_DB_*`, `MB_ENCRYPTION_SECRET_KEY`, `MB_SITE_URL` | Runtime config for Metabase containers. These are read by the Metabase process at startup, not by GitHub Actions. Heroku config vars are the standard way to configure Heroku apps. |
| **Terraform Cloud** | Terraform state files | State contains resource IDs and sensitive values in plaintext. Terraform Cloud encrypts state at rest and provides locking to prevent concurrent applies. Chosen over GCS because GCP org policy blocks service account key creation needed for GCS auth. |

## How to Add Secrets/Variables

### Step 1: Create Environment

Environments are managed in **repository settings**, not the Actions dashboard.

1. Go to **Settings → Environments**: https://github.com/MyFriendBen/data-queries/settings/environments
2. Click **"New environment"**, name it `production`, click **"Configure environment"**

### Step 2: Add Secrets and Variables

See sections below for what to add at each level.

---

## Repository-Level Secrets

Shared across all environments. Add at **Settings → Secrets and variables → Actions → Secrets tab → "New repository secret"**.

| Secret Name | Description | How to Get It |
|-------------|-------------|---------------|
| `TF_API_TOKEN` | Terraform Cloud API token (authenticates to all workspaces in the MyFriendBen org) | From https://app.terraform.io → User Settings → Tokens |

---

## Terraform Cloud Workspace

Create one workspace at https://app.terraform.io:

1. Click **"New Workspace"**
2. Select **"CLI-driven workflow"**
3. Name it `mfb-dashboards-production`
4. Create the workspace

| Workspace Name | Execution Mode |
|---------------|----------------|
| `mfb-dashboards-production` | Local |

The CLI-driven workflow sets execution mode to **Local**, meaning GitHub Actions runs `plan`/`apply` and Terraform Cloud only stores state and provides locking.

---

## BigQuery Authentication

BigQuery integration is **enabled** for production. The GCP org policy (`iam.disableServiceAccountKeyCreation`) was resolved with two approaches:

- **dbt (GitHub Actions):** Uses Workload Identity Federation (OIDC, no key needed). Configured via `WIF_PROVIDER` and `WIF_SERVICE_ACCOUNT` variables.
- **Terraform (GitHub Actions):** Uses the service account key via `BIGQUERY_SA_KEY` secret (passed as `TF_VAR_bigquery_service_account_key_content`). WIF is not used here because the Metabase Terraform provider needs the raw key to configure Metabase's BigQuery data source.
- **Metabase on Heroku:** Uses the same service account key (`metabase-bigquery@mfb-data.iam.gserviceaccount.com`) at runtime. The org policy was temporarily overridden at the project level to create the key, then re-enabled. Key stored as `BIGQUERY_SA_KEY` GitHub secret.

See `BIGQUERY_INTEGRATION.md` for full details.

---

## Environment: `production`

### Production Database Users (RLS)

Production uses Heroku Postgres Standard-tier, which supports multiple credentials. RLS is enforced by extracting the `white_label_id` from the credential username via `regexp_match(current_user, '^wl_[a-z_]+_([0-9]+)_ro$')`.

This same pattern is used in two places:
- **dbt analytics tables** — the RLS policy in `dbt/macros/row_level_security.sql` filters rows by the extracted ID
- **`data_tenant` view** — a `security_barrier` view in `public` schema that filters the legacy `data` table the same way

Credential names must follow the convention `wl_<state>_<white_label_id>_ro`:
- `wl_nc_5_ro` → extracts `5` (NC)
- `wl_co_1_ro` → extracts `1` (CO)

Table owners (the dbt build user) bypass RLS automatically in PostgreSQL.

**Creating credentials:**

```bash
# Create credentials via Heroku CLI (Standard-tier+ only)
# Naming convention: wl_<state>_<white_label_id>_ro
heroku pg:credentials:create -a cobenefits-api --name wl_co_1_ro

# Get the connection URL (contains username + password for GitHub secrets)
heroku pg:credentials:url -a cobenefits-api --name wl_co_1_ro
```

**Granting permissions** (connect via `heroku pg:psql`):

```sql
-- Grant analytics schema access
GRANT USAGE ON SCHEMA analytics TO wl_co_1_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO wl_co_1_ro;

-- Grant access to the RLS view in public schema
GRANT USAGE ON SCHEMA public TO wl_co_1_ro;
GRANT SELECT ON public.data_tenant TO wl_co_1_ro;

-- Auto-grant SELECT on future tables created by the default credential
ALTER DEFAULT PRIVILEGES FOR USER <default_credential_user> IN SCHEMA analytics
  GRANT SELECT ON TABLES TO wl_co_1_ro;
```

### Production Credentials Reference

| GitHub Secret | Heroku Credential | Purpose |
|---------------|-------------------|---------|
| `GLOBAL_DB_USER/PASS` | `default` | dbt writes + global Metabase access |
| `NC_DB_USER/PASS` | `wl_nc_5_ro` | NC tenant Metabase (white_label_id=5) |
| `CO_DB_USER/PASS` | `wl_co_1_ro` | CO tenant Metabase (white_label_id=1) |
| `TX_DB_USER/PASS` | `wl_tx_40_ro` | TX tenant Metabase (white_label_id=40) |
| `IL_DB_USER/PASS` | `wl_il_39_ro` | IL tenant Metabase (white_label_id=39) |
| `MA_DB_USER/PASS` | `wl_ma_38_ro` | MA tenant Metabase (white_label_id=38) |
| `CESN_DB_USER/PASS` | `wl_cesn_4_ro` | CESN tenant Metabase (white_label_id=4) |
| `CO_TAX_CALCULATOR_DB_USER/PASS` | `wl_co_tax_calculator_3_ro` | CO Tax Calculator Metabase (white_label_id=3) |

### Variables (Settings → Environments → production → Variables)

| Variable Name | Description | Value |
|---------------|-------------|-------|
| `METABASE_URL` | Production Metabase URL | `https://mfb-metabase-production-baf31df893fc.herokuapp.com` |
| `METABASE_ADMIN_EMAIL` | Admin email from setup wizard | (your admin email) |
| `DATABASE_NAME` | Production database name | `d2ng9i7crgcemt` |
| `BIGQUERY_ENABLED` | Enable BigQuery data source | `true` |
| `GCP_PROJECT_ID` | Google Cloud project ID | `mfb-data` |
| `GCP_ANALYTICS_TABLE` | GA4 BigQuery table | `analytics_335669714` |
| `WIF_PROVIDER` | Workload Identity Federation provider | `projects/38721872277/locations/global/workloadIdentityPools/github-actions/providers/github` |
| `WIF_SERVICE_ACCOUNT` | WIF service account | `github-actions-dbt@mfb-data.iam.gserviceaccount.com` |

### Secrets (Settings → Environments → production → Secrets)

| Secret Name | Description | How to Get It |
|-------------|-------------|---------------|
| `METABASE_ADMIN_PASSWORD` | Admin password from setup wizard | From the Metabase wizard you completed |
| `DATABASE_HOST` | Production Django database hostname | `heroku pg:credentials:url -a cobenefits-api` |
| `GLOBAL_DB_USER` | Default credential username | `heroku pg:credentials:url -a cobenefits-api` |
| `GLOBAL_DB_PASS` | Default credential password | `heroku pg:credentials:url -a cobenefits-api` |
| `NC_DB_USER` | NC tenant credential username | `heroku pg:credentials:url -a cobenefits-api --name wl_nc_5_ro` |
| `NC_DB_PASS` | NC tenant credential password | Same as above |
| `CO_DB_USER` | CO tenant credential username | `heroku pg:credentials:url -a cobenefits-api --name wl_co_1_ro` |
| `CO_DB_PASS` | CO tenant credential password | Same as above |
| `TX_DB_USER` | TX tenant credential username | `heroku pg:credentials:url -a cobenefits-api --name wl_tx_40_ro` |
| `TX_DB_PASS` | TX tenant credential password | Same as above |
| `IL_DB_USER` | IL tenant credential username | `heroku pg:credentials:url -a cobenefits-api --name wl_il_39_ro` |
| `IL_DB_PASS` | IL tenant credential password | Same as above |
| `MA_DB_USER` | MA tenant credential username | `heroku pg:credentials:url -a cobenefits-api --name wl_ma_38_ro` |
| `MA_DB_PASS` | MA tenant credential password | Same as above |
| `CESN_DB_USER` | CESN tenant credential username | `heroku pg:credentials:url -a cobenefits-api --name wl_cesn_4_ro` |
| `CESN_DB_PASS` | CESN tenant credential password | Same as above |
| `CO_TAX_CALCULATOR_DB_USER` | CO Tax Calculator credential username | `heroku pg:credentials:url -a cobenefits-api --name wl_co_tax_calculator_3_ro` |
| `CO_TAX_CALCULATOR_DB_PASS` | CO Tax Calculator credential password | Same as above |
| `BIGQUERY_SA_KEY` | BigQuery service account key (JSON) | From `metabase-bigquery@mfb-data.iam.gserviceaccount.com` |

---

## dbt Nightly Workflow

The `dbt-nightly.yml` workflow reuses the same production environment secrets as Terraform — no new secrets are needed:

| dbt env var | GitHub secret/variable |
|-------------|----------------------|
| `DB_HOST` | `DATABASE_HOST` (secret) |
| `DB_USER` | `GLOBAL_DB_USER` (secret) |
| `DB_PASS` | `GLOBAL_DB_PASS` (secret) |
| `DB_NAME` | `DATABASE_NAME` (variable) |
| `DB_SSLMODE` | Hardcoded to `require` |
| `DB_SCHEMA` | Hardcoded to `analytics` |

The workflow runs nightly at 6 AM UTC against production. Manual dispatch is also available from the `main` branch.

---

## Prerequisite: Analytics Schema

Ensure the `analytics` schema exists in the production database:

```bash
heroku pg:psql -a <your-django-app-name>
```

```sql
CREATE SCHEMA IF NOT EXISTS analytics;
```

---

## Checklist

### Repository-Level
- [x] Add `TF_API_TOKEN` as a repository secret

### Terraform Cloud
- [x] Create workspace `mfb-dashboards-production` (execution mode: Local)

### BigQuery
- [x] Set up Workload Identity Federation for GitHub Actions
- [x] Create SA key for Metabase (org policy exception)
- [x] Add `BIGQUERY_SA_KEY`, `GCP_PROJECT_ID`, `GCP_ANALYTICS_TABLE`, `WIF_*` to production environment
- [x] Set `BIGQUERY_ENABLED` to `true` in production environment

### Production
- [x] Create `production` GitHub Environment
- [x] Create analytics schema on production DB
- [x] Create RLS credentials (`wl_nc_5_ro` pre-existing, `wl_co_1_ro` created)
- [x] Grant permissions and set default privileges
- [x] Set Metabase `MB_DB_*` config vars, upgrade dyno, deploy container
- [x] Complete production Metabase setup wizard
- [x] Add all Variables and Secrets to production environment
- [x] Run `dbt-nightly` for production
- [x] Create `mfb-dashboards-production` Terraform Cloud workspace
- [x] Run `terraform-apply` for production (first run creates DBs, wait ~45 min for Metabase sync, then re-run)
