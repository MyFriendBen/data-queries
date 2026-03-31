# Data Pipeline Handoff Guide

This document captures the current state of the MFB data pipeline and what needs ongoing attention. It's designed so the team can continue operating and completing in-progress work without context loss.

For full architectural details, see [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md) and [BIGQUERY_INTEGRATION.md](BIGQUERY_INTEGRATION.md).

---

## Access Verification Checklist

Work through this checklist with the person taking over the project **before the handoff is complete**. Each item verifies they have the access and tools needed to operate the pipeline.

### Google Cloud (`gcloud` / `bq` CLI)

- [ ] **Google Cloud SDK installed** — Run `gcloud version` (install with `brew install google-cloud-sdk` if needed)
- [ ] **Authenticated to Google Cloud** — Run `gcloud auth login` and sign in
- [ ] **Read access to `benefits-mfb` project** (old, Gary-owned) — Verify: `bq ls benefits-mfb:analytics_335669714 | head -5`
- [ ] **Read/write access to `mfb-data` project** (new, MFB-owned) — Verify: `bq ls mfb-data:analytics_335669714 | head -5`
- [ ] **GA4 property admin access** — Go to [Google Analytics](https://analytics.google.com/) > Admin > Property Access Management and confirm your account is listed as Admin or Editor
- [ ] **GCP project-level permissions on `mfb-data`** — Verify: `gcloud projects get-iam-policy mfb-data --format="table(bindings.role,bindings.members)" | grep <your-email>`
  - Need at minimum: `roles/bigquery.dataEditor`, `roles/bigquery.jobUser`
  - For org policy overrides (SA key rotation): `roles/orgpolicy.policyAdmin` at the org level

### GitHub (`gh` CLI)

- [ ] **GitHub CLI installed and authenticated** — Run `gh auth status`
- [ ] **Write access to `MyFriendBen/data-queries` repo** — Verify: `gh repo view MyFriendBen/data-queries --json viewerPermission --jq .viewerPermission` (should return `ADMIN` or `WRITE`)
- [ ] **Can trigger workflows** — Verify: `gh workflow list --repo MyFriendBen/data-queries`
- [ ] **Can set environment variables and secrets** — Verify: `gh variable list --env staging --repo MyFriendBen/data-queries`
- [ ] **Can view workflow run logs** — Verify: `gh run list --workflow=dbt-nightly.yml --limit=1 --repo MyFriendBen/data-queries`

### Heroku (`heroku` CLI)

- [ ] **Heroku CLI installed** — Run `heroku --version` (install with `brew tap heroku/brew && brew install heroku` if needed)
- [ ] **Authenticated to Heroku** — Run `heroku auth:whoami`
- [ ] **Access to staging Metabase app** — Verify: `heroku info -a mfb-metabase-staging`
- [ ] **Access to production Metabase app** — Verify: `heroku info -a mfb-metabase-production`
- [ ] **Access to production Django DB app** (for RLS user management) — Verify: `heroku info -a cobenefits-api`
- [ ] **Can connect to production database** — Verify: `heroku pg:info -a cobenefits-api`
- [ ] **Heroku container registry access** (for Metabase upgrades) — Verify: `heroku container:login`

### Metabase (Web UI)

- [ ] **Staging admin login** — Can sign in at `https://mfb-metabase-staging-0805953c70da.herokuapp.com`
- [ ] **Production admin login** — Can sign in at `https://mfb-metabase-production-baf31df893fc.herokuapp.com`
- [ ] **Admin credentials documented** — Stored in a shared password manager or documented securely

### Terraform Cloud

- [ ] **Terraform Cloud account** — Can sign in at [app.terraform.io](https://app.terraform.io)
- [ ] **Access to `mfb` organization** — Can see the `mfb-dashboards-staging` workspace
- [ ] **API token available** — Stored as `TF_API_TOKEN` in GitHub secrets (verify with `gh secret list --env staging --repo MyFriendBen/data-queries | grep TF_API_TOKEN`)

### Local Tools

- [ ] **Docker installed** (for Metabase container upgrades) — Run `docker --version`
- [ ] **Python 3.11+** (for running dbt locally) — Run `python3 --version`
- [ ] **dbt dependencies installed** — Run `pip install -r dbt/requirements.txt`
- [ ] **pre-commit hooks installed** — Run `pre-commit --version` (install with `pip install pre-commit && pre-commit install`)

### Key Credentials to Transfer

These credentials are needed for ongoing operations. Ensure the new owner has access or knows where to find them:

- [ ] **Metabase admin email/password** (staging + production) — needed for Terraform workflows and direct admin access
- [ ] **`metabase-bigquery-key.json`** — service account key for Metabase BigQuery access (stored as `BIGQUERY_SA_KEY` GitHub secret)
- [ ] **Terraform Cloud API token** — stored as `TF_API_TOKEN` GitHub secret
- [ ] **Heroku team/account ownership** — ensure new owner is a collaborator or team member on all three Heroku apps

---

## What's Running Today

| System | Staging | Production |
|--------|---------|------------|
| **Metabase** (dashboards) | Running on Heroku (`mfb-metabase-staging`) | Running on Heroku (`mfb-metabase-production`) |
| **dbt** (analytics tables) | Nightly cron at 6 AM UTC | Nightly cron at 6 AM UTC |
| **Terraform** (Metabase config) | Auto-applies on merge to `main` | Manual dispatch only |
| **BigQuery / GA4** | Enabled (dbt builds BQ models) | Enabled (dbt builds BQ models) |

### Nightly dbt Cron

The `dbt-nightly.yml` workflow runs at 6 AM UTC and refreshes **both staging and production** (via matrix strategy). Each run:

1. Builds Postgres analytics tables (`analytics` schema)
2. Builds BigQuery analytics tables (only if `BIGQUERY_ENABLED=true` for that environment)
3. Triggers a Metabase schema sync so dashboards pick up fresh data

To trigger manually:
```bash
gh workflow run dbt-nightly.yml -f environment=production --repo MyFriendBen/data-queries
gh workflow run dbt-nightly.yml -f environment=staging --repo MyFriendBen/data-queries
```

---

## Ongoing Task: GA4 Data Sync (Manual)

**This is the most time-sensitive item.** Until the GA4 BigQuery export is switched to our own GCP project, GA4 data must be manually copied.

### Background

GA4 event data currently exports to a GCP project (`benefits-mfb`) owned by **Brian at Gary Community Ventures**. We've created our own GCP project (`mfb-data`) and are copying data over, but the GA4 export link still points to the old project.

### The 60-Day Expiration Problem

The `benefits-mfb` project is on BigQuery's **free sandbox tier**, which enforces a **60-day automatic table expiration**. One table disappears every day. We cannot recover expired tables. This means the copy script must be run regularly to avoid permanent data loss.

### How to Run the Copy Script

**Prerequisites:** Google Cloud SDK installed and authenticated with access to both `benefits-mfb` and `mfb-data` projects.

```bash
# Authenticate (one-time, or when session expires)
gcloud auth login

# See what would be copied (safe, no changes)
./scripts/ga4-migration/copy_ga4_tables.sh --dry-run

# Copy new tables
./scripts/ga4-migration/copy_ga4_tables.sh
```

The script is resumable — it tracks what's been copied in `scripts/ga4-migration/ga4_copy_manifest.log` and skips already-copied tables.

**How often:** Run at least weekly to stay ahead of the 60-day expiration. Running daily is ideal.

### Current State of Copied Data

As of late March 2026, the manifest shows 69 tables copied: `events_20260118` through `events_20260326`. The earliest available data in `benefits-mfb` goes back ~60 days; anything older has already expired.

---

## In-Progress: GA4 BigQuery Migration (Phase 3)

The full migration plan is in [BIGQUERY_INTEGRATION.md](BIGQUERY_INTEGRATION.md). Phases 1-2 are complete. Phase 3 is the cutover.

### What's Done (Phases 1-2)

- Created `mfb-data` GCP project with billing enabled (avoids sandbox expiration)
- Copied historical GA4 data from `benefits-mfb` to `mfb-data`
- Set up Workload Identity Federation for keyless GitHub Actions auth
- Created Metabase service account + key for BigQuery access
- Added GitHub Environment variables/secrets for **both staging and production**
- dbt builds BigQuery models on both environments (`mart_screener_conversion_funnel`, `referrer_codes`)
- Terraform creates BigQuery data source + conversion funnel card on staging Metabase

### What's Left (Phase 3 — Cutover)

These steps are in order. See `BIGQUERY_INTEGRATION.md` for full details on each.

1. **Switch the GA4 BigQuery link** — In GA4 Admin > Product Links > BigQuery Links:
   - Remove the link to `benefits-mfb`
   - Add a new link to `mfb-data` (same export settings: daily events)
   - Note: GA4 only allows one BigQuery link at a time

2. **Run a final catch-up copy** — After switching the link, run the copy script one last time to capture any gap-period tables.

3. **Notify Brian at Gary Community Ventures** — Let him know the old export has stopped and old dashboards will no longer receive new data.

4. **Team decision: backfill historical data?** — Data older than 60 days is permanently gone from BigQuery. The GA4 reporting API retains up to 14 months of aggregated metrics. Decide if backfilling aggregated data is worth the effort.

### After Cutover

Once the GA4 link points to `mfb-data`:
- New GA4 events flow directly to `mfb-data` (no more manual copies)
- The nightly dbt cron handles everything automatically
- The copy script and manifest are no longer needed

---

## Other Incomplete Work

### CO Partner Export Columns

PR #16 context: The Colorado partner data export is missing some program-specific columns. The `total_benefits_annual` column doesn't reconcile with the sum of individual program columns because not all programs are exported. See `data.sql` lines 620-727 for the full list of programs included in the totals.

---

## Key Contacts and Accounts

| What | Who / Where |
|------|-------------|
| **GA4 property admin** | MFB team (we have admin access) |
| **`benefits-mfb` GCP project owner** | Brian, Gary Community Ventures |
| **`mfb-data` GCP project owner** | MFB team |
| **Heroku apps** | `mfb-metabase-staging`, `mfb-metabase-production` |
| **Terraform Cloud org** | `mfb`, workspace `mfb-dashboards-staging` (production workspace TBD) |
| **GitHub repo** | `MyFriendBen/data-queries` |

---

## Quick Reference: Common Operations

### Trigger a dbt refresh
```bash
gh workflow run dbt-nightly.yml -f environment=production --repo MyFriendBen/data-queries
```

### Trigger a full dbt refresh (rebuild from scratch)
```bash
gh workflow run dbt-nightly.yml -f environment=production -f full_refresh=true --repo MyFriendBen/data-queries
```

### Apply Terraform changes to production
```bash
gh workflow run terraform-apply.yml -f environment=production --repo MyFriendBen/data-queries
```

### Copy latest GA4 data (until cutover is complete)
```bash
gcloud auth login
./scripts/ga4-migration/copy_ga4_tables.sh
```

### Upgrade Metabase version
See "Metabase Container Updates" section in [README.md](README.md). Key points:
- Update `FROM` tag in `dashboards/Dockerfile.heroku`
- Build with `--platform linux/amd64 --provenance=false`
- Push to each environment separately (pipeline promotion doesn't work with container registry)

### Check workflow status
```bash
gh run list --workflow=dbt-nightly.yml --limit=5 --repo MyFriendBen/data-queries
```
