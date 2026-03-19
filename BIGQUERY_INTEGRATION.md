# BigQuery / Google Analytics Integration

## Overview

The MyFriendBen analytics pipeline needs Google Analytics (GA4) data from BigQuery to populate the "Google Analytics" tab on each tenant dashboard. The dbt models and Terraform resources already exist but are disabled due to a GCP authentication blocker.

### Decided Architecture

```
GitHub Actions (dbt + Terraform)  →  Workload Identity Federation (OIDC, no key)
Metabase on Heroku                →  Service account key (org admin exception)
```

- **GitHub Actions** authenticates to BigQuery via Workload Identity Federation — no service account keys needed. The `google-github-actions/auth@v2` action handles OIDC token exchange.
- **Metabase** connects directly to BigQuery using a service account JSON key. The new GCP project (`mfb-data`) has no org policy blocking key creation, so this is straightforward.

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

## Authentication

Two systems need BigQuery access, each using a different auth method.

### System 1: GitHub Actions (dbt + Terraform)

**Auth method:** Workload Identity Federation (no key needed)

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
   - `GCP_ANALYTICS_TABLE` = your GA4 BigQuery dataset name (e.g., `analytics_335669714`)

**dbt profile change needed:** The current `profiles.yml.example` uses `method: service-account` with `keyfile`. For Workload Identity, change to `method: oauth` or use Application Default Credentials (ADC) which `google-github-actions/auth@v2` sets up automatically. The dbt-bigquery adapter supports ADC when `method: oauth` is set, but in CI the `auth@v2` action writes a credential file and sets `GOOGLE_APPLICATION_CREDENTIALS`, which `method: service-account` + `keyfile` already reads. So the existing profile may work as-is if `GOOGLE_APPLICATION_CREDENTIALS` is set.

### System 2: Metabase on Heroku (runtime BigQuery access)

**Auth method:** Service account key

Metabase's BigQuery driver expects a service account JSON key. The new GCP project (`mfb-data`) does not have the `iam.disableServiceAccountKeyCreation` org policy, so keys can be created directly — no org admin exception needed.

**Steps:**

1. Create the service account and key:
   ```bash
   # Create a dedicated service account for Metabase
   gcloud iam service-accounts create metabase-bigquery \
     --display-name="Metabase BigQuery Reader" \
     --project=mfb-data

   # Grant read-only BigQuery access
   gcloud projects add-iam-policy-binding mfb-data \
     --member="serviceAccount:metabase-bigquery@mfb-data.iam.gserviceaccount.com" \
     --role="roles/bigquery.dataViewer"

   gcloud projects add-iam-policy-binding mfb-data \
     --member="serviceAccount:metabase-bigquery@mfb-data.iam.gserviceaccount.com" \
     --role="roles/bigquery.jobUser"

   # Create the key
   gcloud iam service-accounts keys create metabase-bigquery-key.json \
     --iam-account=metabase-bigquery@mfb-data.iam.gserviceaccount.com
   ```
2. Store the key content as `BIGQUERY_SA_KEY` GitHub Environment secret (Terraform passes it to Metabase via API)

**Key rotation:** Service account keys should be rotated periodically. Create a new key, update the GitHub secret, run `terraform apply`, then delete the old key. No Metabase downtime required — the new key takes effect on the next Metabase restart or database sync.

## Environment Variables Summary

When BigQuery is enabled, these are needed:

### GitHub Environment Variables (non-sensitive)
| Variable | Value | Where |
|----------|-------|-------|
| `BIGQUERY_ENABLED` | `true` | GitHub Environment variable |
| `GCP_PROJECT_ID` | Your GCP project ID | GitHub Environment variable |
| `GCP_ANALYTICS_TABLE` | GA4 BigQuery dataset (e.g., `analytics_335669714`) | GitHub Environment variable |
| `WIF_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions/providers/github` | GitHub Environment variable |
| `WIF_SERVICE_ACCOUNT` | `github-actions-dbt@YOUR_PROJECT_ID.iam.gserviceaccount.com` | GitHub Environment variable |

### GitHub Environment Secrets
| Secret | Value | Used By |
|--------|-------|---------|
| `BIGQUERY_SA_KEY` | Full JSON content of Metabase service account key | Terraform (passes to Metabase via API) |

### Workload Identity Federation (GitHub Actions — no secrets needed)

The `google-github-actions/auth@v2` action exchanges a GitHub OIDC token for short-lived GCP credentials. It reads `WIF_PROVIDER` and `WIF_SERVICE_ACCOUNT` from GitHub Environment variables and automatically sets `GOOGLE_APPLICATION_CREDENTIALS` for subsequent steps (dbt, Terraform).

## Prerequisite: Migrate GA4 Data to New GCP Project

**Status:** Not started — must be completed before any other steps

The GA4 BigQuery export currently lives in a previous organization's GCP project. We have read access to the data, but need to move it into our own GCP project before we can set up Workload Identity, dbt, or Metabase integration.

### Projects

| | Project Name | Project ID | Owner |
|--|-------------|-----------|-------|
| **Old (source)** | Benefits - MFB | `benefits-mfb` | Brian (Gary team) |
| **New (target)** | mfb-data | `mfb-data` | MFB team |

### Known issue: Historical data loss in `benefits-mfb`

The `benefits-mfb` project is on the **BigQuery free sandbox**, which enforces a **60-day table expiration**. Tables older than 60 days are automatically and permanently deleted. As of March 2026, only ~60 days of `events_*` tables remain (back to approx. January 2026), despite the GA4 BigQuery link being active for 1-2 years.

**Implications:**
- Historical data beyond 60 days is gone from BigQuery and cannot be recovered by upgrading to a paid plan
- Looker Studio dashboards showing older data are pulling from the GA4 reporting API (GA4's internal storage), not BigQuery
- The GA4 reporting API retains data for up to 14 months, but provides aggregated metrics — not the raw event-level data that BigQuery exports
- One table is expiring every day, so copying the remaining data is time-sensitive

**Action items:**
- [ ] Flag to Brian (Gary team) that `benefits-mfb` is losing data due to sandbox expiration
- [ ] Verify `mfb-data` has billing enabled so the same expiration does not apply after migration
- [ ] After cutover (Phase 3), decide as a team whether to backfill older data from the GA4 reporting API. This would provide aggregated metrics (sessions, conversions, page views by date) but not raw event-level data, and may not fit the existing dbt models without modification

### Decisions (resolved)

1. **GA4 property ownership** — We have admin access to the GA4 property and can manage BigQuery links.
2. **Migration strategy** — Build-first, then cutover. GA4 only allows one BigQuery link at a time, so we cannot dual-link. Instead: copy historical data to `mfb-data`, build and validate dashboards against the copy, then switch the GA4 link and do a final catch-up copy to fill the gap. Old dashboards (owned by Brian/Gary team) continue working until the cutover.
3. **What moves** — All available historical data (~60 days due to sandbox expiration), plus the GA4 export link once dashboards are ready.

### Migration steps

**Step 1: Create the dataset in `mfb-data`**

```bash
bq mk --dataset --location=US mfb-data:analytics_335669714
```

**Step 2: Copy historical data from old project to `mfb-data`**

Use the copy script (`scripts/ga4-migration/copy_ga4_tables.sh`), which copies each date-sharded `events_*` table individually and logs completed tables to a manifest file (`scripts/ga4-migration/ga4_copy_manifest.log`).

```bash
# Preview what will be copied
./scripts/ga4-migration/copy_ga4_tables.sh --dry-run

# Run the copy
./scripts/ga4-migration/copy_ga4_tables.sh
```

The script is resumable — if interrupted, re-run it and it will skip tables already in the manifest. The manifest also serves as a record of what was copied and when to resume from during the catch-up copy (Step 6).

**Step 3: Verify the copy**

- Compare row counts between old and new datasets for a sample of date-sharded tables
- Validate dbt models run successfully against the copied data in `mfb-data`

**Step 4: Build and validate dashboards**

- Set up WIF, dbt, Metabase (Phases 1-2 below)
- Build the GA tab with conversion funnel charts
- Validate everything works against the copied historical data

**Step 5: Cutover the GA4 link**

Once dashboards are validated and ready for production:

1. Note the current date — this marks the start of the gap period
2. In GA4 Admin > Product Links > BigQuery Links, remove the link to `benefits-mfb`
3. Add a new link pointing to `mfb-data` with the same export settings (daily/streaming, events)
4. New events now flow to `mfb-data`

**Step 6: Catch-up copy**

Re-run the same copy script to pick up any new tables created since the initial copy:

```bash
./scripts/ga4-migration/copy_ga4_tables.sh
```

The script skips tables already in the manifest, so it will only copy the gap period tables.

**Step 7: Coordinate with Brian (Gary team)**

- Notify Brian that the old export has stopped and old dashboards will no longer receive new data
- Old data in `benefits-mfb` remains accessible until the project owner deletes it

### Permissions required

In the **old project** (Benefits - MFB), the user running the copy needs:
- `bigquery.tables.getData` on the source dataset (BigQuery Data Viewer role)
- `bigquery.jobs.create` in the old project (BigQuery Job User role)

In the **new project** (`mfb-data`):
- `bigquery.datasets.create` (to create the target dataset, if not auto-created by GA4 link)
- `bigquery.tables.create` + `bigquery.tables.updateData` (BigQuery Data Editor role)
- `bigquery.jobs.create` (BigQuery Job User role)

## Implementation Order

### Phase 1: GCP Setup (manual — no code changes)

Steps 1, 2, and 3 can be done in parallel. **Copy data ASAP** — the sandbox is deleting one table per day.

1. **Verify `mfb-data` has billing enabled** — GCP Console > Billing. Required to avoid the same 60-day sandbox expiration.
2. **Create dataset + copy historical data to `mfb-data`** — migration steps 1-3 above
3. **Set up Workload Identity Federation** — run the `gcloud` commands in [System 1](#system-1-github-actions-dbt--terraform) above
4. **Create Metabase service account + key** — see [System 2](#system-2-metabase-on-heroku-runtime-bigquery-access) above
5. **Add GitHub Environment variables and secrets** — `BIGQUERY_ENABLED`, `GCP_PROJECT_ID`, `GCP_ANALYTICS_TABLE`, `WIF_PROVIDER`, `WIF_SERVICE_ACCOUNT`, `BIGQUERY_SA_KEY`

### Phase 2: Code Changes + Dashboard Build (against copied historical data)

6. **Update `dbt-nightly.yml`** — add OIDC auth step + BigQuery target (conditional on `BIGQUERY_ENABLED`)
7. **Test dbt BigQuery build** — trigger workflow manually, verify mart table is populated
8. **Enable `bigquery_enabled = true` in Terraform** — set the GitHub Environment variable, run `terraform apply` to create BigQuery data source in Metabase
9. **Add GA tab cards to tenant dashboards** — build conversion funnel charts for the "Google Analytics" tab

### Phase 3: Cutover (after new dashboards are validated)

10. **Switch the GA4 BigQuery link** from `benefits-mfb` to `mfb-data` — migration step 5
11. **Run catch-up copy** for the gap period — migration step 6
12. **Notify Brian (Gary team)** that old export has stopped — migration step 7
13. **Team decision: backfill older historical data?** — Discuss whether to pull aggregated metrics from the GA4 reporting API for the period lost to sandbox expiration (see [known issue](#known-issue-historical-data-loss-in-benefits-mfb))
