# BigQuery / Google Analytics Integration

## Project Reference

| Key | Value |
|-----|-------|
| **New GCP Project ID** | `mfb-data` |
| **New GCP Project Number** | `38721872277` |
| **Old GCP Project ID** | `benefits-mfb` (owned by Brian, Gary team) |
| **GA4 Dataset** | `analytics_335669714` |
| **GitHub Repo** | `MyFriendBen/data-queries` |
| **WIF Pool** | `github-actions` |
| **WIF Provider** | `github` |
| **SA (GitHub Actions/dbt)** | `github-actions-dbt@mfb-data.iam.gserviceaccount.com` |
| **SA (Metabase)** | `metabase-bigquery@mfb-data.iam.gserviceaccount.com` |

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
  method: oauth
  project: "{{ env_var('GCP_PROJECT_ID') }}"
  dataset: analytics
  threads: 4
  timeout_seconds: 300
  location: US
```

Uses `method: oauth` so dbt-bigquery calls `google.auth.default()`, which reads the WIF credential file via `GOOGLE_APPLICATION_CREDENTIALS` (set automatically by `google-github-actions/auth@v2`).

### GitHub Actions (`dbt-nightly.yml`)

Runs `--target postgres` and conditionally `--target bigquery` (gated on `BIGQUERY_ENABLED`).

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
     --project=mfb-data
   ```

2. **Grant BigQuery roles to the service account:**
   ```bash
   # For dbt (read raw data + write to analytics dataset)
   gcloud projects add-iam-policy-binding mfb-data \
     --member="serviceAccount:github-actions-dbt@mfb-data.iam.gserviceaccount.com" \
     --role="roles/bigquery.dataEditor"

   gcloud projects add-iam-policy-binding mfb-data \
     --member="serviceAccount:github-actions-dbt@mfb-data.iam.gserviceaccount.com" \
     --role="roles/bigquery.jobUser"
   ```

3. **Create a Workload Identity Pool + Provider:**
   ```bash
   # Create pool
   gcloud iam workload-identity-pools create "github-actions" \
     --location="global" \
     --display-name="GitHub Actions" \
     --project=mfb-data

   # Create OIDC provider for GitHub (--attribute-condition is required by GCP)
   gcloud iam workload-identity-pools providers create-oidc "github" \
     --location="global" \
     --workload-identity-pool="github-actions" \
     --display-name="GitHub" \
     --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
     --attribute-condition="assertion.repository == 'MyFriendBen/data-queries'" \
     --issuer-uri="https://token.actions.githubusercontent.com" \
     --project=mfb-data
   ```

4. **Enable the IAM Service Account Credentials API** (required for WIF token exchange):
   ```bash
   gcloud services enable iamcredentials.googleapis.com --project=mfb-data
   ```

5. **Allow the GitHub repo to impersonate the service account:**
   ```bash
   gcloud iam service-accounts add-iam-policy-binding \
     github-actions-dbt@mfb-data.iam.gserviceaccount.com \
     --role="roles/iam.workloadIdentityUser" \
     --member="principalSet://iam.googleapis.com/projects/38721872277/locations/global/workloadIdentityPools/github-actions/attribute.repository/MyFriendBen/data-queries" \
     --project=mfb-data
   ```

6. **Update GitHub Actions workflows** to use `google-github-actions/auth@v2`:
   ```yaml
   - uses: google-github-actions/auth@v2
     with:
       workload_identity_provider: "projects/38721872277/locations/global/workloadIdentityPools/github-actions/providers/github"
       service_account: "github-actions-dbt@mfb-data.iam.gserviceaccount.com"

   # This sets GOOGLE_APPLICATION_CREDENTIALS automatically
   ```

7. **Update `dbt-nightly.yml`** to add BigQuery target:
   ```yaml
   - name: Run dbt build (BigQuery)
     if: vars.BIGQUERY_ENABLED == 'true'
     run: dbt build --target bigquery
     env:
       GCP_PROJECT_ID: ${{ vars.GCP_PROJECT_ID }}
       GCP_ANALYTICS_TABLE: ${{ vars.GCP_ANALYTICS_TABLE }}
   ```

8. **Add GitHub Environment variables:**
   - `BIGQUERY_ENABLED` = `true`
   - `GCP_PROJECT_ID` = your GCP project ID
   - `GCP_ANALYTICS_TABLE` = your GA4 BigQuery dataset name (e.g., `analytics_335669714`)

### System 2: Metabase on Heroku (runtime BigQuery access)

**Auth method:** Service account key

Metabase's BigQuery driver expects a service account JSON key. The `mfb-data` project inherits the `iam.disableServiceAccountKeyCreation` org policy from the `myfriendben.org` organization. To create a key, a project-level exception must be set (requires `roles/orgpolicy.policyAdmin` at the org level). After key creation, the exception should be re-enabled.

**Steps:**

1. Create the service account:
   ```bash
   gcloud iam service-accounts create metabase-bigquery \
     --display-name="Metabase BigQuery Reader" \
     --project=mfb-data
   ```

2. Grant read-only BigQuery access:
   ```bash
   gcloud projects add-iam-policy-binding mfb-data \
     --member="serviceAccount:metabase-bigquery@mfb-data.iam.gserviceaccount.com" \
     --role="roles/bigquery.dataViewer"

   gcloud projects add-iam-policy-binding mfb-data \
     --member="serviceAccount:metabase-bigquery@mfb-data.iam.gserviceaccount.com" \
     --role="roles/bigquery.jobUser"
   ```

3. Temporarily disable the org policy to allow key creation (requires `roles/orgpolicy.policyAdmin` on org `1001672396356`):
   ```bash
   # Create a policy override file
   cat > /tmp/org-policy-override.yaml <<'EOF'
   name: projects/mfb-data/policies/iam.disableServiceAccountKeyCreation
   spec:
     rules:
     - enforce: false
   EOF

   # Apply the override
   gcloud org-policies set-policy /tmp/org-policy-override.yaml --project=mfb-data

   # Wait ~60 seconds for propagation, then create the key
   gcloud iam service-accounts keys create metabase-bigquery-key.json \
     --iam-account=metabase-bigquery@mfb-data.iam.gserviceaccount.com
   ```

4. Re-enable the org policy after key creation:
   ```bash
   gcloud org-policies delete iam.disableServiceAccountKeyCreation --project=mfb-data
   ```
   This removes the project-level override so the org-level enforcement is inherited again.

5. Store the key content as `BIGQUERY_SA_KEY` GitHub Environment secret (Terraform passes it to Metabase via API)

**Key rotation:** Service account keys should be rotated periodically. Repeat steps 3-5: temporarily disable the org policy, create a new key, update the GitHub secret, run `terraform apply`, delete the old key, re-enable the org policy.

## Environment Variables Summary

When BigQuery is enabled, these are needed. All variables and secrets are set **per GitHub environment** (`staging` and `production`). Values are the same for both environments.

### GitHub Environment Variables (non-sensitive)
| Variable | Value | Staging | Production |
|----------|-------|---------|------------|
| `BIGQUERY_ENABLED` | `true` | Set | Not set |
| `GCP_PROJECT_ID` | `mfb-data` | Set | Not set |
| `GCP_ANALYTICS_TABLE` | `analytics_335669714` | Set | Not set |
| `WIF_PROVIDER` | `projects/38721872277/locations/global/workloadIdentityPools/github-actions/providers/github` | Set | Not set |
| `WIF_SERVICE_ACCOUNT` | `github-actions-dbt@mfb-data.iam.gserviceaccount.com` | Set | Not set |

### GitHub Environment Secrets
| Secret | Value | Staging | Production |
|--------|-------|---------|------------|
| `BIGQUERY_SA_KEY` | Full JSON content of `metabase-bigquery-key.json` | Set | Not set |

### Workload Identity Federation (GitHub Actions — no secrets needed)

The `google-github-actions/auth@v2` action exchanges a GitHub OIDC token for short-lived GCP credentials. It reads `WIF_PROVIDER` and `WIF_SERVICE_ACCOUNT` from GitHub Environment variables and automatically sets `GOOGLE_APPLICATION_CREDENTIALS` for subsequent steps (dbt, Terraform).

### Setup commands for production

Once staging is validated, run these to set up production (same values):

```bash
# Variables
gh variable set BIGQUERY_ENABLED --env production --repo MyFriendBen/data-queries --body "true"
gh variable set GCP_PROJECT_ID --env production --repo MyFriendBen/data-queries --body "mfb-data"
gh variable set GCP_ANALYTICS_TABLE --env production --repo MyFriendBen/data-queries --body "analytics_335669714"
gh variable set WIF_PROVIDER --env production --repo MyFriendBen/data-queries --body "projects/38721872277/locations/global/workloadIdentityPools/github-actions/providers/github"
gh variable set WIF_SERVICE_ACCOUNT --env production --repo MyFriendBen/data-queries --body "github-actions-dbt@mfb-data.iam.gserviceaccount.com"

# Secret (same key file used for both environments)
gh secret set BIGQUERY_SA_KEY --env production --repo MyFriendBen/data-queries < metabase-bigquery-key.json
```

**Note:** Production also needs the non-BigQuery variables (`DATABASE_NAME`, `METABASE_URL`, `METABASE_ADMIN_EMAIL`) and secrets (`DATABASE_HOST`, `GLOBAL_DB_USER`, `GLOBAL_DB_PASS`, `METABASE_ADMIN_PASSWORD`, tenant DB credentials) that staging already has. These should be set with production-specific values before running the production workflow.

## Prerequisite: Migrate GA4 Data to New GCP Project

**Status:** Complete — 60 tables copied (2026-01-18 to 2026-03-18)

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
- [x] Verify `mfb-data` has billing enabled so the same expiration does not apply after migration
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

1. [x] **Verify `mfb-data` has billing enabled** — GCP Console > Billing. Required to avoid the same 60-day sandbox expiration.
2. [x] **Create dataset + copy historical data to `mfb-data`** — 60 tables copied (2026-01-18 to 2026-03-18). See `scripts/ga4-migration/ga4_copy_manifest.log`.
3. [x] **Set up Workload Identity Federation** — Pool `github-actions`, provider `github` with attribute condition restricting to `MyFriendBen/data-queries`. SA `github-actions-dbt` bound with `workloadIdentityUser`.
4. [x] **Create Metabase service account + key** — SA `metabase-bigquery` (pre-existing with correct roles). Key created after temporarily overriding org policy. **Remember to re-enable the org policy** (step 2 below).
5. [ ] **Add GitHub Environment variables and secrets** — Set per environment (`staging` first, then `production`). See [Environment Variables Summary](#environment-variables-summary).

### Phase 2: Code Changes + Dashboard Build (against copied historical data)

6. [x] **Update `dbt-nightly.yml`** — add OIDC auth step + BigQuery target (conditional on `BIGQUERY_ENABLED`). Merged in PR #46.
7. [x] **Test dbt BigQuery build** — triggered workflow on staging, `mart_screener_conversion_funnel` and `referrer_codes` created in BigQuery.
8. **Enable `bigquery_enabled = true` in Terraform** — set the GitHub Environment variable, run `terraform apply` to create BigQuery data source in Metabase
9. **Add GA tab cards to tenant dashboards** — build conversion funnel charts for the "Google Analytics" tab

### Phase 3: Cutover (after new dashboards are validated)

10. **Switch the GA4 BigQuery link** from `benefits-mfb` to `mfb-data` — migration step 5
11. **Run catch-up copy** for the gap period — migration step 6
12. **Notify Brian (Gary team)** that old export has stopped — migration step 7
13. **Team decision: backfill older historical data?** — Discuss whether to pull aggregated metrics from the GA4 reporting API for the period lost to sandbox expiration (see [known issue](#known-issue-historical-data-loss-in-benefits-mfb))
