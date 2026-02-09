# Deployment Plan: dbt + Metabase to Production

## Overview

Move from a fully local setup (Docker Compose Metabase, local dbt runs, Terraform against localhost) to a production environment where stakeholders can access dashboards and data refreshes automatically.

### Production Architecture

```
                          ┌─────────────────────┐
                          │   Django App DB      │
                          │   (Production PG)    │
                          │                      │
                          │  public schema       │  ← Django reads/writes here
                          │  analytics schema    │  ← dbt writes here
                          │                      │
                          └──────┬───────┬───────┘
                                 │       │
                    ┌────────────┘       └────────────┐
                    │                                  │
              dbt (GH Actions)                   Metabase (Heroku)
              reads public                       reads analytics
              writes analytics                   (via RLS-filtered users)
              runs nightly cron                  connects to BQ too
                    │                                  │
                    │         ┌────────────┐           │
                    └────────►│  BigQuery   │◄──────────┘
                              │  (GA4 data) │
                              └────────────┘
```

**Key decision:** dbt writes to an `analytics` schema on the same production Postgres that hosts the Django app. This matches the current local setup and how the existing materialized views work. Metabase reads from `analytics` via RLS-filtered database users. This is fine at current scale; a read replica is a future optimization if analytics queries begin impacting app performance.

### Phase Dependencies

- **Phases 1 and 2 can be worked in parallel** — neither depends on the other
- **Phase 3 depends on both** — Terraform needs Metabase running (Phase 1) and data available (Phase 2)

---

## Phase 1: Deploy Metabase on Heroku

### Goal
Get Metabase running at a public URL so stakeholders can access dashboards.

### Prerequisite: Create Wrapper Dockerfile and Entrypoint

Both deployment options below require a wrapper Dockerfile and entrypoint script. Two Heroku-specific issues make this necessary:

1. **`$PORT` mapping:** Heroku dynamically assigns a port. Metabase defaults to 3000. Without mapping, you get H10 (App crashed) errors.
2. **BigQuery credentials:** Heroku has no volume mounts. The BigQuery service account JSON must be decoded from a base64 env var at startup.

Create these files before proceeding with either deployment option:

```bash
# dashboards/heroku-entrypoint.sh
#!/bin/sh
set -e

# Heroku assigns $PORT dynamically; Metabase needs it as MB_JETTY_PORT
export MB_JETTY_PORT=${PORT:-3000}

# Decode BigQuery service account key from base64 env var
if [ -n "$BIGQUERY_SA_KEY_BASE64" ]; then
    echo "$BIGQUERY_SA_KEY_BASE64" | base64 -d > /tmp/bigquery-sa-key.json
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/bigquery-sa-key.json
fi

exec /app/run_metabase.sh
```

```dockerfile
# dashboards/Dockerfile.heroku
FROM metabase/metabase:v0.57.11
COPY dashboards/heroku-entrypoint.sh /app/heroku-entrypoint.sh
RUN chmod +x /app/heroku-entrypoint.sh
CMD ["/app/heroku-entrypoint.sh"]
```

```yaml
# heroku.yml (repo root)
build:
  docker:
    web: dashboards/Dockerfile.heroku
```

### Deployment Options

The Metabase official Heroku buildpack/deploy button is **deprecated** (since v0.45) and should not be used. Choose one of the two options below based on team preference.

#### Option A: `heroku.yml` (git push deploy)

Deploy via `git push heroku main`. Uses the `heroku.yml` and Dockerfile committed above.

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

1. **Create the wrapper Dockerfile, entrypoint, and `heroku.yml`** (files listed in Prerequisite above)

2. **Provision Heroku app + Postgres addon**
   ```bash
   heroku create mfb-metabase
   heroku stack:set container -a mfb-metabase
   heroku addons:create heroku-postgresql:essential-0 -a mfb-metabase
   ```

3. **Configure Heroku environment variables**
   ```bash
   # Metabase internal DB (parse from DATABASE_URL provided by addon)
   # The entrypoint or Metabase can use JDBC_DATABASE_URL, or set individual vars:
   heroku config:set MB_DB_TYPE=postgres -a mfb-metabase
   heroku config:set MB_DB_CONNECTION_URI="<jdbc-url-from-addon>" -a mfb-metabase

   # Required Metabase config
   heroku config:set MB_SITE_URL="https://mfb-metabase-<hash>.herokuapp.com" -a mfb-metabase
   heroku config:set MB_ENCRYPTION_SECRET_KEY="<generate-a-random-key>" -a mfb-metabase

   # BigQuery credentials (base64-encoded service account JSON)
   heroku config:set BIGQUERY_SA_KEY_BASE64="$(base64 -i secrets/bigquerykey.json | tr -d '\n')" -a mfb-metabase
   ```

4. **Use Standard-2X dynos (1GB RAM) or higher**
   - Metabase needs significant memory; Standard-1X (512MB) will likely OOM
   ```bash
   heroku ps:type standard-2x -a mfb-metabase
   ```
   - Monitor memory usage after deploy; upgrade to Performance-M if needed

5. **Deploy** using Option A or B above

6. **Complete Metabase setup wizard manually**
   - Visit the Heroku app URL
   - Create admin account (save credentials — Terraform uses these in Phase 3)
   - Skip data source setup (Terraform handles this in Phase 3)

7. **Verify Metabase is healthy**
   - Check `/api/health` endpoint returns OK
   - Confirm Heroku Postgres addon is being used for Metabase internal state

### Heroku Gotchas

- **Heroku Postgres addon** is only for Metabase's internal metadata — it is not the analytics database. The analytics data lives in the production Django database.
- **`MB_DB_CONNECTION_URI`:** Heroku Postgres provides `DATABASE_URL` in postgres:// format. Metabase needs JDBC format. Either parse it in the entrypoint script or set `MB_DB_HOST`, `MB_DB_PORT`, `MB_DB_DBNAME`, `MB_DB_USER`, `MB_DB_PASS` individually.
- **Ephemeral filesystem:** The decoded BigQuery JSON at `/tmp/` is lost on dyno restart — the entrypoint recreates it on every boot, which is fine.

---

## Phase 2: Deploy dbt into Production (GitHub Actions)

### Goal
Automate nightly dbt runs against staging and production databases so analytics tables stay fresh.

### Steps

1. **Store secrets in GitHub Actions**

   Use GitHub Environments (`staging`, `production`) with environment-specific secrets so the same workflow file targets different databases:

   | Secret | Description |
   |--------|-------------|
   | `DB_HOST` | PostgreSQL host (different per environment) |
   | `DB_USER` | PostgreSQL user for dbt (needs read on `public`, write on `analytics`) |
   | `DB_PASS` | PostgreSQL password |
   | `DB_NAME` | Database name |
   | `GCP_PROJECT_ID` | Google Cloud project ID |
   | `GCP_SA_KEY` | BigQuery service account JSON (full content, not base64) |
   | `GCP_ANALYTICS_TABLE` | GA4 analytics table name |

2. **Create GitHub Actions workflow: `.github/workflows/dbt-nightly.yml`**

   ```yaml
   name: dbt nightly build
   on:
     schedule:
       - cron: '0 6 * * *'  # 6am UTC daily (adjust to run after business hours)
     workflow_dispatch: {}   # Allow manual trigger

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
             python-version: '3.11'
             cache: 'pip'
             cache-dependency-path: dbt/requirements.txt
         - run: pip install -r requirements.txt
         - run: dbt deps

         # Write BigQuery service account key to temp file
         - if: matrix.target == 'bigquery'
           run: echo '${{ secrets.GCP_SA_KEY }}' > /tmp/bigquery-key.json

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

3. **Set up RLS database users in production Postgres** (one-time manual step)

   Run against the production database:
   ```sql
   -- Admin user for dbt and global Metabase access
   CREATE USER analytics_admin WITH PASSWORD '<strong-password>' BYPASSRLS;
   GRANT USAGE ON SCHEMA analytics TO analytics_admin;
   GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO analytics_admin;

   -- dbt user (needs write access to analytics schema)
   CREATE USER dbt_runner WITH PASSWORD '<strong-password>';
   GRANT USAGE, CREATE ON SCHEMA analytics TO dbt_runner;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO dbt_runner;  -- read source data

   -- Tenant users (RLS-filtered read-only access)
   CREATE USER nc WITH PASSWORD '<strong-password>';
   ALTER USER nc SET rls.white_label_id = '5';
   GRANT USAGE ON SCHEMA analytics TO nc;
   GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO nc;

   CREATE USER co WITH PASSWORD '<strong-password>';
   ALTER USER co SET rls.white_label_id = '1';
   GRANT USAGE ON SCHEMA analytics TO co;
   GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO co;
   ```

   **Note:** After dbt creates new tables, you may need to re-grant `SELECT` to the tenant users. Consider adding a `post_hook` to the dbt project that auto-grants, or use `ALTER DEFAULT PRIVILEGES`.

4. **Set up the same workflow for staging**
   - The matrix approach handles this: `staging` and `production` are separate GitHub Environments
   - Staging points to a staging database (with the same schema structure)
   - Staging runs let you validate model changes before they hit production

### Notes

- The workflow uses `dbt build` (run + test). Test failures will fail the workflow visibly — this is intentional. Slack/email notifications for failures can be added later.
- Staging database already exists with the same schema structure. GitHub Environments (`staging`, `production`) provide separate credentials for each.

---

## Phase 3: Configure Metabase via Terraform (GitHub Actions)

### Goal
Use Terraform to deploy data sources, collections, cards, dashboards, and permissions to production Metabase — automated via CI on merge to `main`.

### Terraform CI/CD Approach

The standard best practice, and appropriate for this use case:

```
PR touching dashboards/*.tf
        │
        ▼
GitHub Actions: terraform plan
  → Posts plan output as PR comment
  → Reviewer sees exactly what will change in Metabase
        │
        ▼
PR merged to main
        │
        ▼
GitHub Actions: terraform apply
  → Auto-applies (no manual gate needed)
  → Dashboard/collection config is low-risk and easily reversible
```

**Why auto-apply on merge is fine here:** The blast radius is Metabase dashboards and collections — worst case, a dashboard breaks, which is easily fixed. The PR review of the `terraform plan` output is the approval gate. A second manual gate would slow down a small team for minimal safety benefit.

**Important caveat:** Even `terraform plan` requires a live, accessible Metabase instance because the Metabase provider's data sources (like `metabase_table`) make API calls during plan. You cannot plan against a non-running Metabase.

### Steps

1. **Set up Terraform Cloud as state backend**

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

2. **Configure GitHub secrets for Terraform**

   Terraform variables are passed as `TF_VAR_` environment variables:

   | GitHub Secret | Maps to Terraform variable |
   |---------------|---------------------------|
   | `METABASE_ADMIN_PASSWORD` | `TF_VAR_metabase_admin_password` |
   | `DATABASE_HOST` | `TF_VAR_database_host` |
   | `GLOBAL_DB_USER` | Part of `TF_VAR_global_db_credentials` |
   | `GLOBAL_DB_PASS` | Part of `TF_VAR_global_db_credentials` |
   | `NC_DB_PASS` | Part of `TF_VAR_tenant_db_credentials` |
   | `CO_DB_PASS` | Part of `TF_VAR_tenant_db_credentials` |
   | `BIGQUERY_SA_KEY` | `TF_VAR_bigquery_service_account_key_content` |
   | `GCP_PROJECT_ID` | `TF_VAR_gcp_project_id` |
   | `TF_API_TOKEN` | Terraform Cloud API token (for state backend auth) |

3. **Create GitHub Actions workflows**

   **`.github/workflows/terraform-plan.yml`** — runs on PRs touching `dashboards/`:
   ```yaml
   name: Terraform Plan
   on:
     pull_request:
       branches: [main]
       paths:
         - 'dashboards/**'
         - '!dashboards/README.md'
         - '!dashboards/docker-compose.yml'
         - '!dashboards/setup-metabase.sh'
         - '!dashboards/secrets/**'

   jobs:
     plan:
       runs-on: ubuntu-latest
       defaults:
         run:
           working-directory: dashboards
       env:
         TF_VAR_metabase_url: "https://mfb-metabase-<hash>.herokuapp.com"
         TF_VAR_metabase_admin_email: "admin@myfriendben.org"
         TF_VAR_metabase_admin_password: ${{ secrets.METABASE_ADMIN_PASSWORD }}
         TF_VAR_database_host: ${{ secrets.DATABASE_HOST }}
         TF_VAR_database_ssl: "true"
         TF_VAR_global_db_credentials: >-
           {"username":"${{ secrets.GLOBAL_DB_USER }}","password":"${{ secrets.GLOBAL_DB_PASS }}"}
         TF_VAR_tenant_db_credentials: >-
           {"nc":{"username":"nc","password":"${{ secrets.NC_DB_PASS }}"},"co":{"username":"co","password":"${{ secrets.CO_DB_PASS }}"}}
         TF_VAR_bigquery_service_account_key_content: ${{ secrets.BIGQUERY_SA_KEY }}
         TF_VAR_gcp_project_id: ${{ secrets.GCP_PROJECT_ID }}
       steps:
         - uses: actions/checkout@v4
         - uses: hashicorp/setup-terraform@v3
           with:
             terraform_version: "1.9.x"
             cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}
         - run: terraform init
         - run: terraform plan -no-color
           id: plan
         # Post plan output as PR comment (optional but recommended)
   ```

   **`.github/workflows/terraform-apply.yml`** — runs on merge to `main`:
   ```yaml
   name: Terraform Apply
   on:
     push:
       branches: [main]
       paths:
         - 'dashboards/**'
         - '!dashboards/README.md'
         - '!dashboards/docker-compose.yml'
         - '!dashboards/setup-metabase.sh'
         - '!dashboards/secrets/**'

   jobs:
     apply:
       runs-on: ubuntu-latest
       defaults:
         run:
           working-directory: dashboards
       env:
         # Same env vars as plan workflow
         # ...
       steps:
         - uses: actions/checkout@v4
         - uses: hashicorp/setup-terraform@v3
           with:
             terraform_version: "1.9.x"
             cli_config_credentials_token: ${{ secrets.TF_API_TOKEN }}
         - run: terraform init
         - run: terraform apply -auto-approve
   ```

4. **First Terraform apply (manual, one-time)**
   - Before CI is set up, run the first `terraform apply` manually from a dev machine against the production Metabase
   - This creates: BigQuery + Postgres data sources, Global + tenant collections, cards, dashboards
   - Sets the `database_sync_wait_seconds` appropriately (60s for first run; subsequent CI runs won't trigger the wait unless databases are recreated)

5. **Configure Metabase user permissions** (separate ticket, out of scope)
   - User group creation and permission assignment via Terraform is tracked in a separate ticket
   - Phase 3 scope is deploying existing Terraform functionality (databases, collections, cards, dashboards)

### Terraform Provider Notes

- **Pin versions:** Keep `flovouin/metabase ~> 0.14` and `metabase/metabase:v0.57.11`. Test compatibility before upgrading either — the Metabase API is unversioned and can break between releases.
- **Race condition:** Collection creation is already handled sequentially in the existing Terraform config (due to a known Metabase race condition with concurrent writes).
- **State file security:** Terraform state stores all variable values in plaintext, including passwords. Terraform Cloud encrypts state at rest. If using GCS, ensure the bucket has appropriate access controls.

---

## Cross-Cutting Concerns

### Secrets Management

Three systems need credentials:

| System | Secret Store | Secrets |
|--------|-------------|---------|
| Heroku (Metabase) | Heroku config vars | `MB_DB_*`, `MB_ENCRYPTION_SECRET_KEY`, `BIGQUERY_SA_KEY_BASE64` |
| GitHub Actions (dbt) | GitHub secrets + Environments | `DB_HOST/USER/PASS/NAME`, `GCP_SA_KEY`, `GCP_PROJECT_ID` |
| GitHub Actions (Terraform) | GitHub secrets | `TF_VAR_*`, `TF_API_TOKEN` |

For a small team, keeping these as separate stores (Heroku config vars, GitHub secrets) is pragmatic. Centralizing to a dedicated secrets manager (Doppler, 1Password, etc.) is a future optimization if secret sprawl becomes a pain point.

### Rollout Order

| Step | Phase | Depends On | Estimated Effort |
|------|-------|-----------|-----------------|
| Create Heroku app + Postgres addon | 1 | — | — |
| Build wrapper Dockerfile + entrypoint | 1 | — | — |
| Deploy Metabase to Heroku | 1 | Above | — |
| Complete setup wizard | 1 | Metabase running | — |
| Create RLS users in prod Postgres | 2 | Prod DB access | — |
| Store dbt secrets in GitHub | 2 | — | — |
| Create dbt nightly workflow | 2 | Secrets stored | — |
| First successful dbt run | 2 | Workflow + secrets | — |
| Set up Terraform Cloud workspace | 3 | — | — |
| Store Terraform secrets in GitHub | 3 | Phase 1 admin creds | — |
| First manual `terraform apply` | 3 | Phases 1+2 complete | — |
| Create Terraform plan/apply workflows | 3 | Manual apply worked | — |

---

## Open Questions (Remaining)

1. **Heroku deployment method:** Option A (`heroku.yml` / git push) or Option B (Container Registry / CLI)? Both use the same wrapper Dockerfile. Decision can be deferred to the deployment team.

---

## Future Considerations (Out of Scope)
- Read replica for analytics queries (if analytics load impacts Django app performance)
- Metabase SSO / SAML integration for tenant login
- Slack/email alerting on dbt test failures or workflow failures
- Dashboard version control beyond Terraform (e.g., Metabase serialization)
- Cost monitoring for Heroku + BigQuery
- Centralizing secrets into a dedicated secrets manager
