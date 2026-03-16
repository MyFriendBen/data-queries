# BigQuery / Google Analytics Integration

## Overview

The MyFriendBen analytics pipeline needs Google Analytics (GA4) data from BigQuery to populate the "Google Analytics" tab on each tenant dashboard. The dbt models and Terraform resources already exist but are disabled due to a GCP authentication blocker.

## What Already Exists

### dbt Models (ready, untested against real data)

Three BigQuery dbt models in `dbt/models/bigquery/`:

| Model | Type | Purpose |
|-------|------|---------|
| `stg_ga_page_views.sql` | staging view | Extracts `event_params` from GA4 `events_*` wildcard table (page_location, ga_session_id) |
| `int_ga4_page_views.sql` | intermediate view | Derives `page_path`, `page_hostname`, `state_code` from page_location URL |
| `mart_screener_conversion_funnel.sql` | mart table | Daily conversion metrics per state: sessions started/completed/converted, user metrics, conversion rates |

Source config (`dbt/models/bigquery/sources.yml`):
- Source: `google_analytics` database, reads from `events_*` wildcard table
- Requires env vars: `GCP_PROJECT_ID`, `GCP_ANALYTICS_TABLE` (the BigQuery dataset name)

### Terraform Resources (conditional, disabled)

In `dashboards/metabase.tf`:
- `metabase_database.bigquery` — BigQuery data source in Metabase (count = `var.bigquery_enabled ? 1 : 0`)
- `metabase_card.conversion_funnel` — Card querying `mart_screener_conversion_funnel` (conditional)
- Dashboard widget on global analytics dashboard (conditional)

In `dashboards/variables.tf`:
- `bigquery_enabled` (bool, default `false`) — master toggle
- `bigquery_service_account_key_content` (string, sensitive) — for CI/production
- `bigquery_service_account_key_path` (string) — for local dev (`./secrets/bigquerykey.json`)
- `gcp_project_id` (string) — GCP project ID

### dbt Profile (`dbt/profiles.yml.example`)

BigQuery target already configured:
```yaml
bigquery:
  type: bigquery
  method: service-account
  project: "{{ env_var('GCP_PROJECT_ID') }}"
  dataset: analytics
  threads: 4
  timeout_seconds: 300
  location: US
  keyfile: "{{ env_var('GOOGLE_APPLICATION_CREDENTIALS') }}"
```

### GitHub Actions (`dbt-nightly.yml`)

Currently only runs `--target postgres`. BigQuery target needs to be added once auth is resolved.

## The Blocker

**GCP organization policy `iam.disableServiceAccountKeyCreation`** prevents creating service account JSON keys. This affects two systems differently:

### System 1: GitHub Actions (dbt + Terraform)

**Status:** Solvable with Workload Identity Federation (no key needed)

GitHub Actions supports OIDC tokens natively. GCP's Workload Identity Federation can exchange a GitHub OIDC token for short-lived GCP credentials — no service account key file required.

**Steps to implement:**

1. **Create a GCP Service Account** (this is allowed — only key *creation* is blocked):
   ```bash
   gcloud iam service-accounts create github-actions-dbt \
     --display-name="GitHub Actions dbt" \
     --project=YOUR_PROJECT_ID
   ```

2. **Grant BigQuery roles to the service account:**
   ```bash
   # For dbt (read raw data + write to analytics dataset)
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:github-actions-dbt@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/bigquery.dataEditor"

   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:github-actions-dbt@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/bigquery.jobUser"
   ```

3. **Create a Workload Identity Pool + Provider:**
   ```bash
   # Create pool
   gcloud iam workload-identity-pools create "github-actions" \
     --location="global" \
     --display-name="GitHub Actions" \
     --project=YOUR_PROJECT_ID

   # Create OIDC provider for GitHub
   gcloud iam workload-identity-pools providers create-oidc "github" \
     --location="global" \
     --workload-identity-pool="github-actions" \
     --display-name="GitHub" \
     --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
     --issuer-uri="https://token.actions.githubusercontent.com" \
     --project=YOUR_PROJECT_ID
   ```

4. **Allow the GitHub repo to impersonate the service account:**
   ```bash
   gcloud iam service-accounts add-iam-policy-binding \
     github-actions-dbt@YOUR_PROJECT_ID.iam.gserviceaccount.com \
     --role="roles/iam.workloadIdentityUser" \
     --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/attribute.repository/MyFriendBen/data-queries" \
     --project=YOUR_PROJECT_ID
   ```

5. **Update GitHub Actions workflows** to use `google-github-actions/auth@v2`:
   ```yaml
   - uses: google-github-actions/auth@v2
     with:
       workload_identity_provider: "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github"
       service_account: "github-actions-dbt@YOUR_PROJECT_ID.iam.gserviceaccount.com"

   # This sets GOOGLE_APPLICATION_CREDENTIALS automatically
   ```

6. **Update `dbt-nightly.yml`** to add BigQuery target:
   ```yaml
   - name: Run dbt build (BigQuery)
     if: vars.BIGQUERY_ENABLED == 'true'
     run: dbt build --target bigquery
     env:
       GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}
       GCP_ANALYTICS_TABLE: ${{ vars.GCP_ANALYTICS_TABLE }}
   ```

7. **Add GitHub Environment variables:**
   - `BIGQUERY_ENABLED` = `true`
   - `GCP_PROJECT_ID` = your GCP project ID
   - `GCP_ANALYTICS_TABLE` = your GA4 BigQuery dataset name (e.g., `analytics_XXXXXXX`)

**dbt profile change needed:** The current `profiles.yml.example` uses `method: service-account` with `keyfile`. For Workload Identity, change to `method: oauth` or use Application Default Credentials (ADC) which `google-github-actions/auth@v2` sets up automatically. The dbt-bigquery adapter supports ADC when `method: oauth` is set, but in CI the `auth@v2` action writes a credential file and sets `GOOGLE_APPLICATION_CREDENTIALS`, which `method: service-account` + `keyfile` already reads. So the existing profile may work as-is if `GOOGLE_APPLICATION_CREDENTIALS` is set.

### System 2: Metabase on Heroku (runtime BigQuery access)

**Status:** Harder to solve — Metabase needs persistent credentials, not short-lived OIDC tokens

Metabase's BigQuery driver expects a service account JSON key. It doesn't support Workload Identity Federation natively.

**Options (pick one):**

| Option | Effort | Tradeoff |
|--------|--------|----------|
| **A. Org admin exception** — Ask a GCP org admin to create a one-time exception for a single service account key | Low | Requires org admin cooperation. Key must be rotated manually. |
| **B. Move Metabase to Cloud Run** — Run Metabase on GCP instead of Heroku, attach a service account directly | High | Eliminates Heroku dependency. Metabase can use attached SA identity. Significant migration effort. |
| **C. BigQuery proxy** — Run a proxy (e.g., Cloud SQL Auth Proxy pattern) that handles auth and presents a simple interface to Metabase | Medium | Complex architecture. Adds another service to maintain. |
| **D. Skip Metabase BigQuery** — Run dbt BigQuery models, materialize results back to Postgres, let Metabase read from Postgres only | Low | Adds latency (BigQuery → Postgres copy). But keeps Metabase auth simple. Only works if data volume is small. |

**Recommended approach:** Start with **Option A** (org admin exception) for speed, or **Option D** (materialize to Postgres) if getting an exception is difficult. Option D means adding a step that exports `mart_screener_conversion_funnel` from BigQuery to the Postgres `analytics` schema, so Metabase only ever reads Postgres.

## Environment Variables Summary

When BigQuery is enabled, these are needed:

### GitHub Environment Variables (non-sensitive)
| Variable | Value | Where |
|----------|-------|-------|
| `BIGQUERY_ENABLED` | `true` | GitHub Environment variable |
| `GCP_PROJECT_ID` | Your GCP project ID | GitHub Environment variable |
| `GCP_ANALYTICS_TABLE` | GA4 BigQuery dataset (e.g., `analytics_XXXXXXX`) | GitHub Environment variable |

### GitHub Environment Secrets (if using service account key)
| Secret | Value | Where |
|--------|-------|-------|
| `BIGQUERY_SA_KEY` | Full JSON content of service account key | GitHub Environment secret |

### Workload Identity (if using OIDC — no secrets needed)
| Config | Value |
|--------|-------|
| Workload Identity Provider | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github` |
| Service Account | `github-actions-dbt@YOUR_PROJECT_ID.iam.gserviceaccount.com` |

## Recommended Implementation Order

1. **Set up Workload Identity Federation** in GCP (unblocks GitHub Actions)
2. **Add BigQuery target to `dbt-nightly.yml`** and test against real GA4 data
3. **Decide on Metabase BigQuery auth** (org admin exception vs. materialize to Postgres)
4. **Enable `bigquery_enabled` in Terraform** and add GA4 cards to tenant dashboards
5. **Build out the "Google Analytics" tab** with conversion funnel charts
