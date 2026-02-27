# GitHub Secrets and Variables Setup

This document lists all secrets and variables needed for Terraform workflows.

## How to Add Secrets/Variables

1. Go to your repository: https://github.com/MyFriendBen/data-queries
2. Navigate to **Settings → Secrets and variables → Actions**
3. Create two **Environments**: `staging` and `production`
4. Add the secrets/variables below to each environment

---

## Environment: `staging`

### Variables (Settings → Environments → staging → Variables)

| Variable Name | Description | Example Value |
|---------------|-------------|---------------|
| `METABASE_URL` | Staging Metabase URL | `https://mfb-metabase-staging-0805953c70da.herokuapp.com` |
| `METABASE_ADMIN_EMAIL` | Admin email from setup wizard | `admin@myfriendben.org` |
| `DATABASE_NAME` | Staging database name | `mfb_staging` or your actual DB name |
| `GCP_PROJECT_ID` | Google Cloud project ID | `mfb-data` |

### Secrets (Settings → Environments → staging → Secrets)

| Secret Name | Description | How to Get It |
|-------------|-------------|---------------|
| `METABASE_ADMIN_PASSWORD` | Admin password from setup wizard | From the wizard you completed |
| `DATABASE_HOST` | Staging Django database hostname | Get from your staging database config |
| `GLOBAL_DB_USER` | Admin database user (BYPASSRLS) | `analytics_admin` (needs to be created) |
| `GLOBAL_DB_PASS` | Admin database password | Password for `analytics_admin` |
| `NC_DB_USER` | North Carolina tenant DB user | `nc` (needs to be created) |
| `NC_DB_PASS` | NC tenant password | Password for `nc` user |
| `CO_DB_USER` | Colorado tenant DB user | `co` (needs to be created) |
| `CO_DB_PASS` | CO tenant password | Password for `co` user |
| `BIGQUERY_SA_KEY` | BigQuery service account JSON key | Full JSON content of your service account key file |

---

## Environment: `production`

Same secrets/variables as staging, but with **production values**:
- Different `METABASE_URL` (production Metabase)
- Different `DATABASE_HOST` (production database)
- Different admin/tenant passwords
- Same `BIGQUERY_SA_KEY` and `GCP_PROJECT_ID` (unless using separate GCP projects)

---

## Database Users Setup (Run These SQL Commands First!)

Before Terraform can work, you need to create the database users in your staging/production databases:

### Connect to your staging database and run:

```sql
-- Admin user for global Metabase access (bypasses RLS)
CREATE USER analytics_admin WITH PASSWORD '<strong-random-password>' BYPASSRLS;
GRANT USAGE ON SCHEMA analytics TO analytics_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO analytics_admin;

-- North Carolina tenant user (RLS-filtered)
CREATE USER nc WITH PASSWORD '<strong-random-password>';
ALTER USER nc SET rls.white_label_id = '5';  -- NC white label ID
GRANT USAGE ON SCHEMA analytics TO nc;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO nc;

-- Colorado tenant user (RLS-filtered)
CREATE USER co WITH PASSWORD '<strong-random-password>';
ALTER USER co SET rls.white_label_id = '1';  -- CO white label ID
GRANT USAGE ON SCHEMA analytics TO co;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO co;

-- Auto-grant SELECT on future tables created by dbt
ALTER DEFAULT PRIVILEGES FOR USER dbt_runner IN SCHEMA analytics
  GRANT SELECT ON TABLES TO nc, co, analytics_admin;
```

**Save these passwords** - you'll add them as GitHub Secrets.

---

## Checklist

- [ ] Create `staging` and `production` GitHub Environments
- [ ] Add all Variables to staging environment
- [ ] Add all Secrets to staging environment
- [ ] Create database users in staging database (SQL above)
- [ ] (Later) Repeat for production environment

---

## Testing the Setup

Once secrets are configured:
1. Commit and push the workflow files
2. Merge to `main` branch
3. The `terraform-apply` workflow will run automatically against staging
4. Check the Actions tab to see the run
5. Verify Metabase has the data sources and dashboards configured
