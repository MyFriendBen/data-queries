# Data Pipeline Operational Guide

This document captures the current state of the MFB data pipeline and serves as a reference for ongoing operations and future handoffs. To hand off: update the "Current State" section, work through the Access Verification Checklist with the new owner, and transfer credentials.

For full architectural details, see [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md) and [BIGQUERY_INTEGRATION.md](BIGQUERY_INTEGRATION.md).

---

## Current State (April 2026)

The data pipeline is fully operational. GA4 event data flows from the screener into our own GCP project (`mfb-data`) via a direct BigQuery export link, and the nightly dbt cron builds analytics tables in both Postgres and BigQuery automatically.

**GA4 BigQuery migration is complete** (April 13, 2026). The export was switched from Gary's `benefits-mfb` project (free sandbox, 60-day expiration) to `mfb-data` (billing enabled, no expiration). Raw event data in `mfb-data` goes back to January 18, 2026.

**In flight:**
- [MFB-608](https://linear.app/myfriendben/issue/MFB-608/data-white-label-dashboard-google-analytics) — GA tab on tenant Metabase dashboards. Code merged (PR #61, April 10). Needs Terraform apply to production once QA is confirmed.
- [MFB-940](https://linear.app/myfriendben/issue/MFB-940/backfill-historical-ga4-data-from-reporting-api-into-bigquery) — Backfill historical GA4 data (pre-January 2026) from the GA4 Reporting API into BigQuery. Time-sensitive: the API retains up to 14 months of aggregated metrics.

**Known gap:**
- GTM custom events (`Page Change`, `outbound_click`) are not forwarding to GA4. The app pushes these to `window.dataLayer` correctly but the GTM container has not been configured with the corresponding tags/triggers. Needs GTM container access to resolve.

---

## What's Running Today

| System | Production |
|--------|------------|
| **Metabase** (dashboards) | Running on Heroku (`mfb-metabase-production`) |
| **dbt** (analytics tables) | Nightly cron at 6 AM UTC |
| **Terraform** (Metabase config) | Auto-applies on merge to `main` |
| **BigQuery / GA4** | Enabled — exporting to `mfb-data` |

### Nightly dbt Cron

The `dbt-nightly.yml` workflow runs at 6 AM UTC against production. Each run:

1. Builds Postgres analytics tables (`analytics` schema)
2. Builds BigQuery analytics tables (only if `BIGQUERY_ENABLED=true`)
3. Triggers a Metabase schema sync so dashboards pick up fresh data

To trigger manually:
```bash
gh workflow run dbt-nightly.yml --repo MyFriendBen/data-queries
```

---

## Access Verification Checklist

Work through this checklist with the person taking over the project **before the handoff is complete**. Each item verifies they have the access and tools needed to operate the pipeline.

### Google Cloud (`gcloud` / `bq` CLI)

- [ ] **Google Cloud SDK installed** — Run `gcloud version` (install with `brew install google-cloud-sdk` if needed)
- [ ] **Authenticated to Google Cloud** — Run `gcloud auth login` and sign in
- [ ] **Read/write access to `mfb-data` project** — Verify: `bq ls mfb-data:analytics_335669714 | head -5`
- [ ] **GA4 property admin access** — Go to [Google Analytics](https://analytics.google.com/) > Admin > Property Access Management and confirm your account is listed as Admin or Editor
- [ ] **GCP project-level permissions on `mfb-data`** — Verify: `gcloud projects get-iam-policy mfb-data --format="table(bindings.role,bindings.members)" | grep <your-email>`
  - Need at minimum: `roles/bigquery.dataEditor`, `roles/bigquery.jobUser`

### GitHub (`gh` CLI)

- [ ] **GitHub CLI installed and authenticated** — Run `gh auth status`
- [ ] **Write access to `MyFriendBen/data-queries` repo** — Verify: `gh repo view MyFriendBen/data-queries --json viewerPermission --jq .viewerPermission` (should return `ADMIN` or `WRITE`)
- [ ] **Can trigger workflows** — Verify: `gh workflow list --repo MyFriendBen/data-queries`
- [ ] **Can set environment variables and secrets** — Verify: `gh variable list --env production --repo MyFriendBen/data-queries`
- [ ] **Can view workflow run logs** — Verify: `gh run list --workflow=dbt-nightly.yml --limit=1 --repo MyFriendBen/data-queries`

### Heroku (`heroku` CLI)

- [ ] **Heroku CLI installed** — Run `heroku --version` (install with `brew tap heroku/brew && brew install heroku` if needed)
- [ ] **Authenticated to Heroku** — Run `heroku auth:whoami`
- [ ] **Access to production Metabase app** — Verify: `heroku info -a mfb-metabase-production`
- [ ] **Access to production Django DB app** (for RLS user management) — Verify: `heroku info -a cobenefits-api`
- [ ] **Can connect to production database** — Verify: `heroku pg:info -a cobenefits-api`
- [ ] **Heroku container registry access** (for Metabase upgrades) — Verify: `heroku container:login`

### Metabase (Web UI)

- [ ] **Production admin login** — Can sign in at `https://mfb-metabase-production-baf31df893fc.herokuapp.com`
- [ ] **Admin credentials documented** — Stored in 1Password

### Terraform Cloud

- [ ] **Terraform Cloud account** — Can sign in at [app.terraform.io](https://app.terraform.io)
- [ ] **Access to `MyFriendBen` organization** — Can see the `mfb-dashboards-production` workspace
- [ ] **API token available** — Stored as `TF_API_TOKEN` in GitHub secrets (verify with `gh secret list --repo MyFriendBen/data-queries | grep TF_API_TOKEN`)

### Local Tools

- [ ] **Docker installed** (for Metabase container upgrades) — Run `docker --version`
- [ ] **Python 3.11+** (for running dbt locally) — Run `python3 --version`
- [ ] **dbt dependencies installed** — Run `pip install -r dbt/requirements.txt`
- [ ] **pre-commit hooks installed** — Run `pre-commit --version` (install with `pip install pre-commit && pre-commit install`)

### Key Credentials to Transfer

- [ ] **Metabase admin email/password** (production) — stored in 1Password
- [ ] **`metabase-bigquery-key.json`** — service account key for Metabase BigQuery access (stored as `BIGQUERY_SA_KEY` GitHub secret)
- [ ] **Terraform Cloud API token** — stored as `TF_API_TOKEN` GitHub secret
- [ ] **Heroku team/account ownership** — ensure new owner is a collaborator or team member on all three Heroku apps

---

## Key Contacts and Accounts

| What | Who / Where |
|------|-------------|
| **GA4 property admin** | MFB team (`caton@myfriendben.org`) |
| **`mfb-data` GCP project owner** | MFB team |
| **Heroku apps** | `mfb-metabase-production` |
| **Terraform Cloud org** | `MyFriendBen`, workspace `mfb-dashboards-production` |
| **GitHub repo** | `MyFriendBen/data-queries` |

---

## Quick Reference: Common Operations

### Trigger a dbt refresh
```bash
gh workflow run dbt-nightly.yml --repo MyFriendBen/data-queries
```

### Trigger a full dbt refresh (rebuild from scratch)
```bash
gh workflow run dbt-nightly.yml -f full_refresh=true --repo MyFriendBen/data-queries
```

### Apply Terraform changes to production
Terraform applies automatically on merge to `main`. To force a manual run:
```bash
gh workflow run terraform-apply.yml --repo MyFriendBen/data-queries
```

### Upgrade Metabase version
See "Metabase Container Updates" section in [README.md](README.md). Key points:
- Update `FROM` tag in `dashboards/Dockerfile.heroku`
- Build with `--platform linux/amd64 --provenance=false`
- Push to `mfb-metabase-production`

### Check workflow status
```bash
gh run list --workflow=dbt-nightly.yml --limit=5 --repo MyFriendBen/data-queries
```

### Rotate Metabase BigQuery service account key
The `mfb-data` project has `iam.disableServiceAccountKeyCreation` org policy. To rotate:
1. Temporarily disable at project level: `gcloud resource-manager org-policies disable-enforce iam.disableServiceAccountKeyCreation --project=mfb-data`
2. Create new key: `gcloud iam service-accounts keys create metabase-bigquery-key.json --iam-account=metabase-bigquery@mfb-data.iam.gserviceaccount.com --project=mfb-data`
3. Re-enable immediately: `gcloud resource-manager org-policies enable-enforce iam.disableServiceAccountKeyCreation --project=mfb-data`
4. Update GitHub secret: `gh secret set BIGQUERY_SA_KEY --env production --repo MyFriendBen/data-queries < metabase-bigquery-key.json`
5. Run `terraform apply` to push the new key to Metabase
6. Delete the old key from GCP Console
