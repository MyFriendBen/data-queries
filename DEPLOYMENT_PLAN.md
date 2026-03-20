# Deployment Plan: dbt + Metabase to Production

## Overview

Move from a fully local setup (Docker Compose Metabase, local dbt runs, Terraform against localhost) to a production environment where stakeholders can access dashboards and data refreshes automatically.

### Production Architecture

**Data sources** (both read by dbt and Metabase):

- **PostgreSQL** — the production Django database. dbt reads from `public` schema (source data), writes marts to `analytics` schema. Metabase reads `analytics` via RLS-filtered users.
- **BigQuery** — GA4 event data. dbt reads raw events, writes aggregated marts. Metabase reads marts directly.

**Services:**

- **dbt** runs as a nightly GitHub Actions cron, targeting both data sources
- **Metabase** runs on Heroku, connecting to both data sources for dashboards

**Key decision:** dbt writes to an `analytics` schema on the same Postgres that hosts the Django app. This matches the current local setup and how the existing materialized views work. A read replica is a future optimization if analytics queries begin impacting app performance.

### Phase Dependencies

- **Phases 1 and 2 can be worked in parallel** — neither depends on the other
- **Phase 3 depends on both** — Terraform needs Metabase running (Phase 1) and data available (Phase 2)

---

## Phase 1: Deploy Metabase on Heroku

### Goal

Get Metabase running in both staging and production environments using a Heroku Pipeline so stakeholders can access dashboards and changes can be tested before production release.

### Prerequisite: Create Wrapper Dockerfile and Entrypoint — ✅ Completed

Both deployment options below require a wrapper Dockerfile and entrypoint script. Heroku dynamically assigns a port via `$PORT`, but Metabase expects `MB_JETTY_PORT`. Without mapping, you get H10 (App crashed) errors.

These files are already committed (`dashboards/Dockerfile.heroku`, `dashboards/heroku-entrypoint.sh`):

```bash
# dashboards/heroku-entrypoint.sh
#!/bin/sh
set -e

# Heroku assigns $PORT dynamically; Metabase needs it as MB_JETTY_PORT
export MB_JETTY_PORT=$PORT

exec /app/run_metabase.sh
```

```dockerfile
# dashboards/Dockerfile.heroku
FROM metabase/metabase:v0.56.19
COPY dashboards/heroku-entrypoint.sh /app/heroku-entrypoint.sh
RUN chmod +x /app/heroku-entrypoint.sh
CMD ["/app/heroku-entrypoint.sh"]
```

### Environment Strategy

Deploy to **both staging and production** using a **Heroku Pipeline** for controlled promotion:
- Staging app: `mfb-metabase-staging` → connects to staging Django database
- Production app: `mfb-metabase-production` → connects to production Django database
- Pipeline enables: test in staging, then promote the exact same Docker image to production

### Deployment Options

The Metabase official Heroku buildpack/deploy button is **deprecated** (since v0.45) and should not be used. Choose one of the two options below based on team preference.

#### Option A: `heroku.yml` (git push deploy)

Deploy via `git push heroku main`. Uses the `heroku.yml` and Dockerfile committed above.

```yaml
# heroku.yml (repo root)
build:
  docker:
    web: dashboards/Dockerfile.heroku
```

**Pros:** Version-pinned in source control. Standard `git push` deploy. Supports Heroku Pipelines if needed later.

**Cons:** Heroku rebuilds the image on every push (no layer caching), though for a one-line `FROM` + `COPY` this is fast.

#### Option B: Heroku Container Registry (CLI deploy)

Push the Docker image directly to Heroku's container registry via CLI.

```bash
heroku container:login

# Build and push the wrapper image
docker build -f dashboards/Dockerfile.heroku -t registry.heroku.com/mfb-metabase/web .
docker push registry.heroku.com/mfb-metabase/web
heroku container:release web -a mfb-metabase
```

To upgrade Metabase versions: update the `FROM` tag in `Dockerfile.heroku`, rebuild, and push.

**Pros:** No git remote needed. Explicit control over when deploys happen.

**Cons:** Deploy is not tracked in git history (unless scripted). No Heroku Pipelines or Review Apps support.

### Steps

1. ~~**Create the wrapper Dockerfile and entrypoint**~~ ✅ Completed

2. **Create `heroku.yml`** if you choose Option A above.

3. **Provision Heroku Pipeline with staging and production apps**

   ```bash
   # Create the pipeline
   heroku pipelines:create mfb-metabase --team=<your-team>  # omit --team if personal account

   # Create staging app and add to pipeline
   heroku create mfb-metabase-staging --team=<your-team>
   heroku pipelines:add mfb-metabase --app=mfb-metabase-staging --stage=staging
   heroku stack:set container -a mfb-metabase-staging
   heroku addons:create heroku-postgresql:essential-0 -a mfb-metabase-staging

   # Create production app and add to pipeline
   heroku create mfb-metabase-production --team=<your-team>
   heroku pipelines:add mfb-metabase --app=mfb-metabase-production --stage=production
   heroku stack:set container -a mfb-metabase-production
   heroku addons:create heroku-postgresql:essential-0 -a mfb-metabase-production

   # Add git remotes for both apps
   heroku git:remote -a mfb-metabase-staging -r heroku-staging
   heroku git:remote -a mfb-metabase-production -r heroku-production
   ```

4. **Configure Heroku environment variables for both apps**

   For **staging**:
   ```bash
   # Metabase internal DB (uses DATABASE_URL from Postgres addon automatically)
   heroku config:set MB_DB_TYPE=postgres -a mfb-metabase-staging

   # Required Metabase config
   heroku config:set MB_SITE_URL="https://mfb-metabase-staging-<hash>.herokuapp.com" -a mfb-metabase-staging
   heroku config:set MB_ENCRYPTION_SECRET_KEY="<generate-a-random-key>" -a mfb-metabase-staging
   ```

   For **production**:
   ```bash
   heroku config:set MB_DB_TYPE=postgres -a mfb-metabase-production
   heroku config:set MB_SITE_URL="https://mfb-metabase-production-<hash>.herokuapp.com" -a mfb-metabase-production
   heroku config:set MB_ENCRYPTION_SECRET_KEY="<generate-a-different-random-key>" -a mfb-metabase-production
   ```

   **Note:** Generate different encryption keys for staging and production. Use: `openssl rand -base64 32`

5. **Use Standard-2X dynos (1GB RAM) or higher for both apps**
   - Metabase needs significant memory; Standard-1X (512MB) will likely OOM

   ```bash
   heroku ps:type standard-2x -a mfb-metabase-staging
   heroku ps:type standard-2x -a mfb-metabase-production
   ```

   - Monitor memory usage after deploy; upgrade to Performance-M if needed

6. **Deploy to staging first, then promote to production**

   Using **Option A (git push)**:
   ```bash
   # Deploy to staging
   git push heroku-staging main

   # Test staging thoroughly, then promote to production
   heroku pipelines:promote -a mfb-metabase-staging
   ```

   Using **Option B (container registry)**:
   ```bash
   # Build and push to staging
   docker build -f dashboards/Dockerfile.heroku -t registry.heroku.com/mfb-metabase-staging/web .
   docker push registry.heroku.com/mfb-metabase-staging/web
   heroku container:release web -a mfb-metabase-staging

   # Test, then push to production
   docker tag registry.heroku.com/mfb-metabase-staging/web registry.heroku.com/mfb-metabase-production/web
   docker push registry.heroku.com/mfb-metabase-production/web
   heroku container:release web -a mfb-metabase-production
   ```

7. **Complete Metabase setup wizard manually for both environments**

   For **staging**:
   - Visit the staging Heroku app URL
   - Create admin account (save credentials — Terraform uses these in Phase 3)
   - Skip data source setup (Terraform handles this in Phase 3)

   For **production**:
   - Visit the production Heroku app URL
   - Create admin account (save credentials — Terraform uses these in Phase 3)
   - Skip data source setup (Terraform handles this in Phase 3)

   **Note:** Use different admin credentials for staging and production for security

8. **Verify both Metabase instances are healthy**

   For **staging**:
   ```bash
   curl https://mfb-metabase-staging-<hash>.herokuapp.com/api/health
   heroku logs --tail -a mfb-metabase-staging  # Check for errors
   ```

   For **production**:
   ```bash
   curl https://mfb-metabase-production-<hash>.herokuapp.com/api/health
   heroku logs --tail -a mfb-metabase-production
   ```

   Confirm both are using their respective Heroku Postgres addons for Metabase internal state

### Heroku Gotchas

- **Heroku Pipeline promotion** copies the Docker image slug from staging to production, but does NOT copy config vars. Each app maintains its own environment variables (different database hosts, site URLs, encryption keys).
- **Heroku Postgres addon** is only for Metabase's internal metadata — it is not the analytics database. The analytics data lives in the staging/production Django databases.
- **`MB_DB_CONNECTION_URI`:** Heroku Postgres provides `DATABASE_URL` in postgres:// format. Metabase needs JDBC format. Either set `MB_DB_CONNECTION_URI` to the JDBC URL or set `MB_DB_HOST`, `MB_DB_PORT`, `MB_DB_DBNAME`, `MB_DB_USER`, `MB_DB_PASS` individually.
- **BigQuery credentials:** Configured via Terraform (Phase 3), which passes the service account key content directly through the Metabase API — no filesystem or entrypoint involvement needed.

---

## Phase 2: Deploy dbt into Production (GitHub Actions)

### Goal

Automate nightly dbt runs against staging and production databases so analytics tables stay fresh.

### Prerequisite: Store Secrets in GitHub Actions

Use GitHub Environments (`staging`, `production`) with environment-specific secrets so the same workflow file targets different databases. Staging database already exists with the same schema structure.

| Secret                | Description                                                            |
| --------------------- | ---------------------------------------------------------------------- |
| `DB_HOST`             | PostgreSQL host (different per environment)                            |
| `DB_USER`             | PostgreSQL user for dbt (needs read on `public`, write on `analytics`) |
| `DB_PASS`             | PostgreSQL password                                                    |
| `DB_NAME`             | Database name                                                          |
| `GCP_PROJECT_ID`      | Google Cloud project ID                                                |
| `GCP_SA_KEY`          | BigQuery service account JSON (full content, not base64)               |
| `GCP_ANALYTICS_TABLE` | GA4 analytics table name                                               |

### Prerequisite: Set Up RLS Database Users (one-time manual step)

#### Local Development (superuser available)

For local Postgres where you have superuser access, use GUC-based RLS:

```sql
CREATE USER nc WITH PASSWORD '<password>';
ALTER USER nc SET rls.white_label_id = '5';
GRANT USAGE ON SCHEMA analytics TO nc;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO nc;

CREATE USER co WITH PASSWORD '<password>';
ALTER USER co SET rls.white_label_id = '1';
GRANT USAGE ON SCHEMA analytics TO co;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO co;
```

#### Heroku Production (no superuser)

On Heroku, `ALTER USER ... SET` for custom GUC parameters requires superuser, which Heroku doesn't grant. Instead, use **view-based RLS** with Heroku credentials:

1. **Credential naming convention:** `wl_<state>_<white_label_id>_ro` — the `data_tenant` view extracts the white_label_id from the username via `regexp_replace(current_user, '[^0-9]', '', 'g')::int`.

2. **Create credentials:**
   ```bash
   heroku pg:credentials:create -a cobenefits-api --name wl_co_1_ro
   heroku pg:credentials:url -a cobenefits-api --name wl_co_1_ro
   ```

3. **Grant permissions** (via `heroku pg:psql`):
   ```sql
   GRANT USAGE ON SCHEMA analytics TO wl_co_1_ro;
   GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO wl_co_1_ro;
   GRANT USAGE ON SCHEMA public TO wl_co_1_ro;
   GRANT SELECT ON public.data_tenant TO wl_co_1_ro;
   ```

4. **The `data_tenant` view** (already exists on production) handles row filtering:
   ```sql
   CREATE VIEW public.data_tenant
   WITH (security_barrier = TRUE)
   AS
   SELECT * FROM public.data
   WHERE white_label_id = regexp_replace(current_user, '[^0-9]', '', 'g')::int;
   ```

#### Staging (Essential-tier)

Essential-tier Heroku Postgres doesn't support custom credentials. Use the single default credential for all connections.

### Prerequisite: Configure Default Privileges for New Tables

When dbt creates new tables, tenant users won't automatically have `SELECT` access. Run this once per database to auto-grant on future tables:

```sql
-- Auto-grant SELECT on future analytics tables (Heroku production example)
ALTER DEFAULT PRIVILEGES FOR USER <default_credential_user> IN SCHEMA analytics
  GRANT SELECT ON TABLES TO wl_nc_5_ro, wl_co_1_ro, read_only;
```

Without this, every new dbt model requires manually re-granting `SELECT` to each tenant user.

### Steps

1. **Create GitHub Actions workflow: `.github/workflows/dbt-nightly.yml`**

   ```yaml
   name: dbt nightly build
   on:
     schedule:
       - cron: "0 6 * * *" # 6am UTC daily (adjust to run after business hours)
     workflow_dispatch: {} # Allow manual trigger

   jobs:
     dbt-build:
       runs-on: ubuntu-latest
       strategy:
         fail-fast: false
         matrix:
           environment: [staging, production]
           target: [postgres, bigquery]
       environment: ${{ matrix.environment }}
       defaults:
         run:
           working-directory: dbt
       steps:
         - uses: actions/checkout@v4
         - uses: actions/setup-python@v5
           with:
             python-version: "3.11"
             cache: "pip"
             cache-dependency-path: dbt/requirements.txt
         - run: pip install -r requirements.txt
         - run: dbt deps

         # Write BigQuery service account key to temp file
         - if: matrix.target == 'bigquery'
           run: |
            install -m 600 /dev/null /tmp/bigquery-key.json
            echo '${{ secrets.GCP_SA_KEY }}' > /tmp/bigquery-key.json

         - run: dbt build --target ${{ matrix.target }}
           env:
             DB_HOST: ${{ secrets.DB_HOST }}
             DB_USER: ${{ secrets.DB_USER }}
             DB_PASS: ${{ secrets.DB_PASS }}
             DB_NAME: ${{ secrets.DB_NAME }}
             DB_SCHEMA: analytics
             GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
             GOOGLE_APPLICATION_CREDENTIALS: /tmp/bigquery-key.json
             GCP_ANALYTICS_TABLE: ${{ secrets.GCP_ANALYTICS_TABLE }}
   ```

   **Notes on this design:**
   - `fail-fast: false` ensures a BigQuery failure doesn't cancel the Postgres run (and vice versa)
   - `strategy.matrix` runs staging and production as separate jobs with separate secrets via GitHub Environments
   - `workflow_dispatch` allows manual re-runs from the GitHub UI
   - `dbt build` runs models + tests together; test failures will fail the workflow visibly
   - Slack/email notifications for failures can be added later

---

## Phase 3: Configure Metabase via Terraform (GitHub Actions)

### Goal

Deploy existing Terraform functionality (databases, collections, cards, dashboards) to production Metabase. Auto-deploy to staging on merge; manual release to production.

### Terraform CI/CD Approach

```
PR touching dashboards/*.tf
        │
        ▼
GitHub Actions: terraform plan (against staging)
  → Posts plan output as PR comment
  → Reviewer sees exactly what will change
        │
        ▼
PR merged to main
        │
        ▼
GitHub Actions: terraform apply (staging, auto)
  → Auto-applies to staging Metabase
        │
        ▼
Manual trigger (when ready)
        │
        ▼
GitHub Actions: terraform apply (production, manual)
  → workflow_dispatch to release to production
```

This matches the pattern used in other repos: auto-deploy to staging for validation, manual release to production.

**Important caveat:** Even `terraform plan` requires a live, accessible Metabase instance because the Metabase provider's data sources (like `metabase_table`) make API calls during plan. You cannot plan against a non-running Metabase.

### Prerequisite: Set Up Terraform Cloud as State Backend

Add a `cloud` block to the Terraform config:

```hcl
# In dashboards/metabase.tf (or a new dashboards/backend.tf)
terraform {
  cloud {
    organization = "mfb"  # your Terraform Cloud org
    workspaces {
      name = "mfb-dashboards"
    }
  }
}
```

In Terraform Cloud workspace settings, set **Execution Mode to "Local"**. This means:

- Terraform Cloud only stores state and provides locking
- GitHub Actions runners execute the actual plan/apply (not Terraform Cloud runners)
- This avoids networking issues — the GitHub runner can reach the public Heroku Metabase URL directly

**Alternative if Terraform Cloud feels heavyweight:** A GCS bucket works as a simpler state backend since you already have GCP for BigQuery:

```hcl
terraform {
  backend "gcs" {
    bucket = "mfb-terraform-state"
    prefix = "dashboards"
  }
}
```

### Prerequisite: Configure GitHub Secrets for Terraform

Terraform variables are passed as `TF_VAR_` environment variables. Use GitHub Environments (`staging`, `production`) with environment-specific values where the Metabase URL and database host differ:

| GitHub Secret             | Maps to Terraform variable                         |
| ------------------------- | -------------------------------------------------- |
| `METABASE_ADMIN_PASSWORD` | `TF_VAR_metabase_admin_password`                   |
| `DATABASE_HOST`           | `TF_VAR_database_host`                             |
| `GLOBAL_DB_USER`          | Part of `TF_VAR_global_db_credentials`             |
| `GLOBAL_DB_PASS`          | Part of `TF_VAR_global_db_credentials`             |
| `NC_DB_USER`              | Part of `TF_VAR_tenant_db_credentials`             |
| `NC_DB_PASS`              | Part of `TF_VAR_tenant_db_credentials`             |
| `CO_DB_USER`              | Part of `TF_VAR_tenant_db_credentials`             |
| `CO_DB_PASS`              | Part of `TF_VAR_tenant_db_credentials`             |
| `BIGQUERY_SA_KEY`         | `TF_VAR_bigquery_service_account_key_content`      |
| `GCP_PROJECT_ID`          | `TF_VAR_gcp_project_id`                            |
| `TF_API_TOKEN`            | Terraform Cloud API token (for state backend auth) |

### Steps

1. **First Terraform apply (manual, one-time)**
   - Run the first `terraform apply` manually from a dev machine against staging, then production
   - This creates: BigQuery + Postgres data sources, Global + tenant collections, cards, dashboards
   - Sets the `database_sync_wait_seconds` appropriately (60s for first run; subsequent CI runs won't trigger the wait unless databases are recreated)

2. **Create GitHub Actions workflows**

   **`.github/workflows/terraform-plan.yml`** — runs on PRs touching `dashboards/`:

   ```yaml
   name: Terraform Plan
   on:
     pull_request:
       branches: [main]
       paths:
         - "dashboards/**"
         - "!dashboards/README.md"
         - "!dashboards/docker-compose.yml"
         - "!dashboards/setup-metabase.sh"

   jobs:
     plan:
       runs-on: ubuntu-latest
       environment: staging
       defaults:
         run:
           working-directory: dashboards
       env:
         TF_VAR_metabase_url: ${{ vars.METABASE_URL }}
         TF_VAR_metabase_admin_email: ${{ vars.METABASE_ADMIN_EMAIL }}
         TF_VAR_metabase_admin_password: ${{ secrets.METABASE_ADMIN_PASSWORD }}
         TF_VAR_database_host: ${{ secrets.DATABASE_HOST }}
         TF_VAR_database_ssl: "true"
         TF_VAR_bigquery_service_account_key_content: ${{ secrets.BIGQUERY_SA_KEY }}
         TF_VAR_gcp_project_id: ${{ secrets.GCP_PROJECT_ID }}
       steps:
         - uses: actions/checkout@v4
         - uses: hashicorp/setup-terraform@v3
           with:
             terraform_version: "1.9.x"
             cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}
         - name: Build Terraform credential JSON variables
           run: |
             global_creds=$(jq -cn \
               --arg user "$GLOBAL_DB_USER" \
               --arg pass "$GLOBAL_DB_PASS" \
               '{username: $user, password: $pass}')
             tenant_creds=$(jq -cn \
               --arg nc_user "$NC_DB_USER" \
               --arg nc_pass "$NC_DB_PASS" \
               --arg co_user "$CO_DB_USER" \
               --arg co_pass "$CO_DB_PASS" \
               '{nc: {username: $nc_user, password: $nc_pass}, co: {username: $co_user, password: $co_pass}}')
             echo "TF_VAR_global_db_credentials=$global_creds" >> "$GITHUB_ENV"
             echo "TF_VAR_tenant_db_credentials=$tenant_creds" >> "$GITHUB_ENV"
           env:
             GLOBAL_DB_USER: ${{ secrets.GLOBAL_DB_USER }}
             GLOBAL_DB_PASS: ${{ secrets.GLOBAL_DB_PASS }}
             NC_DB_USER: ${{ secrets.NC_DB_USER }}
             NC_DB_PASS: ${{ secrets.NC_DB_PASS }}
             CO_DB_USER: ${{ secrets.CO_DB_USER }}
             CO_DB_PASS: ${{ secrets.CO_DB_PASS }}
         - run: terraform init
         - run: terraform plan -no-color
           id: plan
         # Post plan output as PR comment (optional but recommended)
   ```

   **`.github/workflows/terraform-apply.yml`** — auto-applies to staging on merge, manual dispatch for production:

   ```yaml
   name: Terraform Apply
   on:
     push:
       branches: [main]
       paths:
         - "dashboards/**"
         - "!dashboards/README.md"
         - "!dashboards/docker-compose.yml"
         - "!dashboards/setup-metabase.sh"
         - "!dashboards/secrets/**"
     workflow_dispatch:
       inputs:
         environment:
           description: "Target environment"
           required: true
           type: choice
           options:
             - staging
             - production

   jobs:
     apply:
       runs-on: ubuntu-latest
       environment: ${{ github.event.inputs.environment || 'staging' }}
       defaults:
         run:
           working-directory: dashboards
       env:
         TF_VAR_metabase_url: ${{ vars.METABASE_URL }}
         TF_VAR_metabase_admin_email: ${{ vars.METABASE_ADMIN_EMAIL }}
         TF_VAR_metabase_admin_password: ${{ secrets.METABASE_ADMIN_PASSWORD }}
         TF_VAR_database_host: ${{ secrets.DATABASE_HOST }}
         TF_VAR_database_ssl: "true"
         TF_VAR_bigquery_service_account_key_content: ${{ secrets.BIGQUERY_SA_KEY }}
         TF_VAR_gcp_project_id: ${{ secrets.GCP_PROJECT_ID }}
       steps:
         - uses: actions/checkout@v4
         - uses: hashicorp/setup-terraform@v3
           with:
             terraform_version: "1.9.x"
             cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}
         - name: Build Terraform credential JSON variables
           run: |
             global_creds=$(jq -cn \
               --arg user "$GLOBAL_DB_USER" \
               --arg pass "$GLOBAL_DB_PASS" \
               '{username: $user, password: $pass}')
             tenant_creds=$(jq -cn \
               --arg nc_user "$NC_DB_USER" \
               --arg nc_pass "$NC_DB_PASS" \
               --arg co_user "$CO_DB_USER" \
               --arg co_pass "$CO_DB_PASS" \
               '{nc: {username: $nc_user, password: $nc_pass}, co: {username: $co_user, password: $co_pass}}')
             echo "TF_VAR_global_db_credentials=$global_creds" >> "$GITHUB_ENV"
             echo "TF_VAR_tenant_db_credentials=$tenant_creds" >> "$GITHUB_ENV"
           env:
             GLOBAL_DB_USER: ${{ secrets.GLOBAL_DB_USER }}
             GLOBAL_DB_PASS: ${{ secrets.GLOBAL_DB_PASS }}
             NC_DB_USER: ${{ secrets.NC_DB_USER }}
             NC_DB_PASS: ${{ secrets.NC_DB_PASS }}
             CO_DB_USER: ${{ secrets.CO_DB_USER }}
             CO_DB_PASS: ${{ secrets.CO_DB_PASS }}
         - run: terraform init
         - run: terraform apply -auto-approve
   ```

### Terraform Provider Notes

- **Pin versions:** Keep `flovouin/metabase ~> 0.14` and `metabase/metabase:v0.56.19`. Test compatibility before upgrading either — the Metabase API is unversioned and can break between releases.
- **State file security:** Terraform state stores all variable values in plaintext, including passwords. Terraform Cloud encrypts state at rest. If using GCS, ensure the bucket has appropriate access controls.

### Maintenance Note: CI Variable Coupling

Both `terraform-plan.yml` and `terraform-apply.yml` duplicate the `TF_VAR_*` environment variable mappings and the `jq` credential-building step. This means:

- **Adding a new Terraform variable** requires three changes: update `variables.tf`, add the GitHub secret, and update **both** workflow files.
- **Adding a new tenant** requires updating the `jq` block in both workflows (to include the new tenant's credentials in the JSON object).

This is a known tradeoff for simplicity — the duplication keeps each workflow self-contained and easy to read. If it becomes painful (e.g., many tenants or frequent variable changes), extract the shared logic into a [composite action](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action) or switch to a `.tfvars` file generated by a single setup step.

---

## Cross-Cutting Concerns

### Secrets Management

Three systems need credentials:

| System                     | Secret Store                  | Secrets                                                         |
| -------------------------- | ----------------------------- | --------------------------------------------------------------- |
| Heroku (Metabase)          | Heroku config vars            | `MB_DB_*`, `MB_ENCRYPTION_SECRET_KEY`                           |
| GitHub Actions (dbt)       | GitHub secrets + Environments | `DB_HOST/USER/PASS/NAME`, `GCP_SA_KEY`, `GCP_PROJECT_ID`        |
| GitHub Actions (Terraform) | GitHub secrets                | `TF_VAR_*`, `TF_API_TOKEN`                                      |

For a small team, keeping these as separate stores (Heroku config vars, GitHub secrets) is pragmatic. Centralizing to a dedicated secrets manager (Doppler, 1Password, etc.) is a future optimization if secret sprawl becomes a pain point.

### Rollout Order

| Step                                                       | Phase | Type   | Depends On          | Status |
| ---------------------------------------------------------- | ----- | ------ | ------------------- | ------ |
| ~~Create wrapper Dockerfile + entrypoint~~                 | 1     | Prereq | —                   | ✅     |
| ~~Create heroku.yml~~                                      | 1     | Prereq | —                   | ✅     |
| ~~Provision Heroku Pipeline with staging + production~~    | 1     | Step   | Prereq above        | ✅     |
| ~~Configure Heroku env vars for staging~~                  | 1     | Step   | Above               | ✅     |
| ~~Deploy Metabase to staging~~                             | 1     | Step   | Above               | ✅     |
| ~~Complete setup wizard (staging)~~                        | 1     | Step   | Above               | ✅     |
| Deploy Metabase to production                              | 1     | Step   | Above               |        |
| Complete setup wizard (production)                         | 1     | Step   | Above               |        |
| ~~Store dbt secrets in GitHub Environments~~               | 2     | Prereq | —                   | ✅     |
| ~~Create RLS users + default privileges (production)~~     | 2     | Prereq | DB access           | ✅     |
| ~~Create dbt nightly workflow, first successful run~~      | 2     | Step   | Prereqs above       | ✅     |
| ~~Set up Terraform Cloud workspace~~                       | 3     | Prereq | —                   | ✅     |
| ~~Store Terraform secrets in GitHub Environments~~         | 3     | Prereq | Phase 1 admin creds | ✅     |
| ~~Terraform apply (staging)~~                              | 3     | Step   | Phases 1+2 complete | ✅     |
| ~~Create Terraform plan/apply workflows~~                  | 3     | Step   | Manual apply worked | ✅     |
| Build out dashboard cards and charts                       | 3     | Step   | Above               |        |
| Terraform apply (production)                               | 3     | Step   | Production deploy   |        |

---

## Staging Deployment Log

Issues encountered during staging deployment and their resolutions, captured to streamline production deployment.

### Heroku Docker Build Context

**Issue:** `COPY dashboards/heroku-entrypoint.sh` failed because Heroku sets the Docker build context to the Dockerfile's directory, not the repo root.

**Fix:** Changed Dockerfile `COPY` to use a relative path (`COPY heroku-entrypoint.sh`). The `heroku.yml` `context` property is not supported.

### Metabase ENTRYPOINT vs CMD

**Issue:** Using `CMD ["/app/heroku-entrypoint.sh"]` caused Metabase to interpret the entrypoint path as a Metabase command ("Unrecognized command"). The base Metabase image has its own ENTRYPOINT that receives CMD as arguments.

**Fix:** Changed Dockerfile to use `ENTRYPOINT ["/app/heroku-entrypoint.sh"]` to fully override the base image entrypoint.

### Metabase run_metabase.sh Not Found

**Issue:** The entrypoint script called `/app/run_metabase.sh` which doesn't exist in Metabase v0.56.19.

**Fix:** Changed entrypoint to call `java -jar metabase.jar` directly.

### Metabase Database Connection

**Issue:** Metabase crashed trying to connect to `localhost:5432` even though DATABASE_URL was set by the Heroku Postgres addon.

**Fix:** Metabase does NOT automatically parse Heroku's `DATABASE_URL`. Set individual `MB_DB_HOST`, `MB_DB_PORT`, `MB_DB_DBNAME`, `MB_DB_USER`, `MB_DB_PASS`, and `MB_DB_SSL=true` config vars explicitly.

### Memory (OOM)

**Issue:** Basic dyno (512MB) caused `Error R15 (Memory quota vastly exceeded)` — Metabase used 1152MB (225%).

**Fix:** Upgraded to Standard-2X (1GB RAM, ~$50/month). **Standard-2X is the minimum viable dyno for Metabase.**

### Heroku Postgres Essential-Tier Limitations

**Issue:** `heroku pg:credentials:create` fails on Essential-tier with "You can't create a custom credential on Essential-tier databases." Cannot create separate RLS database users.

**Workaround:** Use the single default Heroku Postgres credential for all Metabase database connections on staging. Database-level RLS requires Standard-tier ($50/month) or higher.

**Production note:** If production uses Standard-tier or higher, create separate RLS users via `heroku pg:credentials:create`.

### GCP Service Account Key Creation Blocked — ✅ Resolved

**Issue:** GCP organization policy `iam.disableServiceAccountKeyCreation` prevents creating service account JSON keys needed for BigQuery access.

**Resolution:**
- **GitHub Actions (dbt + Terraform):** Uses Workload Identity Federation (OIDC, no key needed). Set up in PR #46.
- **Metabase on Heroku:** Temporarily overrode the org policy at the project level to create a SA key for `metabase-bigquery@mfb-data.iam.gserviceaccount.com`, then re-enabled the policy. Key stored as `BIGQUERY_SA_KEY` GitHub secret.

See `BIGQUERY_INTEGRATION.md` for full details.

### Terraform State Backend — GCS Requires Auth Too

**Issue:** The GCS backend (`mfb-terraform-state` bucket) also needs GCP authentication. Since service account keys are blocked by the org policy, GitHub Actions workflows can't authenticate to GCS to read/write Terraform state.

**Decision:** Switch from GCS to **Terraform Cloud** as the state backend. This avoids the GCP auth issue entirely — Terraform Cloud only needs an API token (stored as a GitHub Secret), provides free state storage, locking, and encryption at rest.

**Resolution:** Switched to Terraform Cloud. See "Current Status" section below.

---

## Production Deployment Log

Issues encountered during production deployment and their resolutions.

### Heroku RLS — ALTER USER SET Requires Superuser

**Issue:** `ALTER USER wl_nc_5_ro SET rls.white_label_id = '5'` fails with "permission denied" on Heroku. Custom GUC parameters require superuser, which Heroku doesn't grant.

**Fix:** Use view-based RLS instead. A `data_tenant` view with `security_barrier` extracts the white_label_id from the credential username: `regexp_replace(current_user, '[^0-9]', '', 'g')::int`. Credential naming convention `wl_<state>_<id>_ro` embeds the ID.

### Pipeline Promotion Blocked for Container Registry Apps

**Issue:** `heroku pipelines:promote -a mfb-metabase-staging` fails with "Pipeline promotions are not supported on apps pushed via Heroku Container Registry."

**Fix:** Build and push directly to each app's container registry:
```bash
docker build --platform linux/amd64 --provenance=false -f Dockerfile.heroku -t registry.heroku.com/mfb-metabase-production/web .
docker push registry.heroku.com/mfb-metabase-production/web
heroku container:release web -a mfb-metabase-production
```

### Docker Build Flags Required on Apple Silicon

**Issue:** Two separate failures:
1. `docker push` fails with "unsupported" — provenance/attestation manifests incompatible with Heroku registry
2. `docker push` fails with "unsupported architecture arm64" — Heroku requires amd64

**Fix:** Always use both flags: `docker build --platform linux/amd64 --provenance=false`

### Cannot Set Dyno Type Before Deploying Code

**Issue:** `heroku ps:type standard-2x` fails with "No process types on mfb-metabase-production" before any code is deployed.

**Fix:** Deploy the container first (`container:release`), then scale the dyno type.

### Terraform Apply Needed 3 Runs (Not 2)

**Issue:** Documentation said "first run fails on BigQuery table lookup, second succeeds." In practice, the first run created all database connections successfully, but Metabase took ~45 minutes to fully sync all tenant database schemas. Some tenants (co, co_tax_calculator) synced within minutes; others (nc, il, ma, tx, cesn) took much longer.

**Fix:** Wait at least 45 minutes after the first terraform apply before retrying. The third run (after ~45 min total) succeeded with all 17 resources created.

---

## Production Deployment Checklist

Quick-reference for deploying to production, incorporating lessons from staging:

### Database Setup (production Django DB: `cobenefits-api`)
- [ ] Create analytics schema: `CREATE SCHEMA IF NOT EXISTS analytics;`
- [ ] Grant default credential access to analytics schema (USAGE, CREATE)
- [ ] Grant default credential SELECT on public schema tables
- [ ] Create CO credential: `heroku pg:credentials:create -a cobenefits-api --name wl_co_1_ro`
- [ ] Grant analytics + public schema access to `wl_nc_5_ro` and `wl_co_1_ro`
- [ ] Grant `data_tenant` view access to both tenant credentials
- [ ] Set default privileges for future analytics tables

**Important:** Do NOT use `ALTER USER ... SET rls.white_label_id` — this requires superuser. RLS is handled by the `data_tenant` view which extracts the ID from the credential username.

### Phase 1: Metabase on Heroku
- [ ] Set Heroku config vars — Metabase does NOT parse `DATABASE_URL`, need individual `MB_DB_*` vars:
  ```bash
  heroku config:set MB_DB_HOST=<host> MB_DB_PORT=5432 MB_DB_DBNAME=<dbname> \
    MB_DB_USER=<user> MB_DB_PASS=<pass> MB_DB_SSL=true -a mfb-metabase-production
  ```
- [ ] Upgrade to Standard-2X dyno (required, 512MB will OOM):
  ```bash
  heroku ps:type standard-2x -a mfb-metabase-production
  ```
- [ ] Promote staging image to production:
  ```bash
  heroku pipelines:promote -a mfb-metabase-staging
  ```
- [ ] Complete Metabase setup wizard at production URL
- [ ] Verify `/api/health` returns `{"status":"ok"}`

### Phase 2: GitHub Environment Secrets + dbt
- [ ] Set all production variables (METABASE_URL, DATABASE_NAME, BIGQUERY_ENABLED=true, GCP vars, WIF vars)
- [ ] Set all production secrets (DATABASE_HOST, GLOBAL/NC/CO DB credentials, METABASE_ADMIN_PASSWORD, BIGQUERY_SA_KEY)
- [ ] Trigger `dbt-nightly` workflow for production

### Phase 3: Terraform
- [ ] Create `mfb-dashboards-production` workspace in Terraform Cloud (CLI-driven, local execution)
- [ ] Trigger `terraform-apply` workflow with `production` environment
- [ ] Note: First run creates DB connections but fails on table lookups. Wait ~45 min for Metabase to sync all tenant schemas, then run again. May need 3+ attempts.

---

## Current Status

### What's Done — Staging End-to-End Pipeline Complete
- ✅ **Phase 1 staging**: Metabase running on Heroku at `https://mfb-metabase-staging-0805953c70da.herokuapp.com`
  - Heroku Pipeline created (`mfb-metabase` with staging + production apps)
  - Standard-2X dyno (required — 512MB OOMs)
  - Setup wizard complete, admin account created
  - Production app provisioned but not yet deployed
- ✅ **Phase 2 staging**: dbt nightly workflow running successfully
  - `.github/workflows/dbt-nightly.yml` — cron 6 AM UTC + manual dispatch
  - Builds Postgres models, creates tables in `analytics` schema
  - Triggers Metabase schema sync after build (so Terraform can find new tables)
  - Reuses existing staging secrets (no new GitHub secrets needed)
- ✅ **Phase 3 staging**: Terraform plan/apply workflows running successfully
  - Terraform Cloud backend configured (`mfb-dashboards-staging` workspace)
  - `terraform-plan.yml` runs on PRs, `terraform-apply.yml` auto-applies on merge
  - Creates: Postgres data sources (global + per-tenant), collections, cards, dashboards
- ✅ **GitHub Environments**: `staging` and `production` created with secrets configured
- ✅ **Analytics schema**: Created in staging database, populated by dbt

### What's Next (In Order)

#### 1. Build out dashboard content in Terraform

The staging pipeline is working end-to-end, but the dashboards only contain a single "Completed Screens" scalar card per tenant. The tenant dashboards have 5 tabs (Google Analytics, All-Time Performance, Last 30 Days Performance, Households, Benefits & Immediate Needs) but only the "All-Time Performance" tab has a card.

Next steps:
- Design the charts/cards needed for each tab using the `analytics.mart_screener_data` table
- Add Terraform resources for new cards in `dashboards/metabase.tf`
- Use the dashboard generation helper scripts (`dashboards/scripts/`) to convert Metabase designs to Terraform HCL if helpful

#### 2. Google Analytics / BigQuery integration — ✅ Staging complete

BigQuery integration is working end-to-end on staging:
- **GCP setup**: Workload Identity Federation for GitHub Actions, SA key for Metabase (org policy exception applied and re-enabled)
- **dbt**: `dbt-nightly.yml` builds BigQuery models (`mart_screener_conversion_funnel`, `referrer_codes`)
- **Terraform**: BigQuery data source, conversion funnel card, and dashboard widget created in staging Metabase

Remaining: enable on production (set GitHub env vars/secrets, run workflows). See `BIGQUERY_INTEGRATION.md` for details.

#### 3. Deploy to production

Follow the "Production Deployment Checklist" section above. Summary:
- Set Heroku config vars for production Metabase app
- Upgrade to Standard-2X dyno, promote staging image
- Complete Metabase setup wizard
- Add production secrets to `production` GitHub Environment
- Trigger `dbt-nightly` and `terraform-apply` for production
- If production DB is Standard-tier+, create RLS users via `heroku pg:credentials:create`

### Deferred Items
- **Database-level RLS**: Only available on Heroku Postgres Standard-tier+. Staging uses single credential.
- **Read replica**: Future optimization if analytics queries impact app performance.

---
