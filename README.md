# 📊 MFB Data Pipeline — Developer Guide

This repository contains the end-to-end data pipeline for My Friend Ben. We use automated tools to keep our code clean and consistent.

## Tools We Use

- **dbt SQL Models**: [SQLFluff](https://sqlfluff.com/) (handles both PostgreSQL & BigQuery)
- **Terraform**: `terraform fmt`
- **Config Files (YAML)**: [Prettier](https://prettier.io/)
- **Automation**: `pre-commit` (runs all the above automatically)

## One-Time Setup

To enable these automatic checks on your machine:

1. **Install pre-commit**:
   ```bash
   pip install pre-commit
   ```

2. **Setup Git Hooks**:
   Run this once from the root folder:
   ```bash
   pre-commit install
   ```

3. **Install dbt Requirements**:
   ```bash
   pip install -r dbt/requirements.txt
   ```

## How to Use

### Automatic Check
Once setup, every time you run `git commit`, these tools will check your scripts. If they find a small styling issue, they will fix it for you automatically.

### Manual Check
To check all files at any time:
```bash
pre-commit run --all-files
```

To run on a specific file:
```bash
pre-commit run --files filepath
```

### Direct Tool Commands
If you want to run the tools individually:

- **For SQL**: `sqlfluff fix dbt/models/`
- **For YAML**: `prettier --write 'dbt/**/*.yml'`
- **For Terraform**: `terraform fmt -recursive dashboards/` (formats all .tf files including subfolders)


## 💡 Quick Tips
- **Skipping Checks**: If you need to skip the check for a specific commit (emergency only!), add `--no-verify` to your commit command.

---

## Deployment

This repo has three types of changes, each with its own deployment path.

### Understanding What Lives Where

| What | Where it's defined | How it deploys |
|------|-------------------|----------------|
| **Analytics tables** (mart_screener_data, etc.) | `dbt/models/` | dbt nightly cron + manual dispatch |
| **Dashboards, cards, data sources** | `dashboards/*.tf` | Terraform via GitHub Actions |
| **Metabase application** (the container itself) | `dashboards/Dockerfile.web` | Manual `heroku container:push` |

The first two change regularly. The third changes only when upgrading Metabase versions or modifying the entrypoint — typically a few times a year.

### 1. dbt Model Changes (analytics tables)

**When:** You've added or modified SQL models in `dbt/models/`.

Production runs automatically every night at 6 AM UTC. To trigger manually:
```bash
gh workflow run dbt-nightly.yml --repo MyFriendBen/data-queries
```

To do a full refresh (rebuilds tables from scratch instead of incrementally):
```bash
gh workflow run dbt-nightly.yml -f full_refresh=true --repo MyFriendBen/data-queries
```

Manual dispatches are restricted to the `main` branch.

### 2. Metabase Configuration Changes (dashboards, cards, data sources)

**When:** You've added or modified Terraform resources in `dashboards/*.tf` — new cards, dashboard layouts, data source connections, collections, etc.

These are **Metabase configuration** changes, not container changes. Terraform talks to the Metabase API to create/update resources. No container rebuild is needed.

**Workflow:**

1. Open a PR that modifies `dashboards/*.tf`
2. `terraform-plan.yml` runs automatically against production and posts the plan as a PR comment
3. Merge to `main` → `terraform-apply.yml` auto-applies to **production**

Applies are restricted to the `main` branch.

**Note:** The Terraform plan and apply workflows both ignore changes to `dashboards/Dockerfile.web`, `dashboards/heroku-entrypoint.sh`, `dashboards/docker-compose.yml`, `dashboards/setup-metabase.sh`, and `dashboards/README.md` — those don't affect Metabase configuration. Renaming any of them means updating the `paths` filter in `.github/workflows/terraform-{plan,apply}.yml`, or the broader `dashboards/**` include starts matching again.

### 3. Metabase Container Updates (version upgrades)

**When:** You're upgrading the Metabase version (changing the `FROM` tag in `Dockerfile.web`) or modifying the entrypoint script. This is rare.

**Prerequisites:** `heroku container:push` shells out to BuildKit, so Docker needs the buildx plugin. Without it the build fails with `unknown flag: --provenance`:

```bash
brew install docker-buildx
mkdir -p ~/.docker/cli-plugins
ln -sfn "$(brew --prefix docker-buildx)/bin/docker-buildx" ~/.docker/cli-plugins/docker-buildx
docker buildx version   # confirm the plugin is found
```

**Steps:**

1. Update the version in `dashboards/Dockerfile.web`:
   ```dockerfile
   FROM metabase/metabase:v0.XX.YY
   ```

2. Build and push. `--recursive` is what makes Heroku pick up `Dockerfile.web`, and
   `--context-path .` keeps `COPY heroku-entrypoint.sh` resolvable:
   ```bash
   cd dashboards
   heroku container:login
   heroku container:push web --recursive --context-path . \
     --app mfb-metabase-production
   ```

3. Release to **production**:
   ```bash
   heroku container:release web --app mfb-metabase-production
   ```

4. Confirm a new release was actually created. `container:release` exits 0 and prints
   `done` even when it ships nothing — the warning `The process type web was not updated,
   because it is already running the specified docker image` means the release did **not**
   take:
   ```bash
   heroku releases --app mfb-metabase-production | head -4
   ```

5. Verify production is healthy. Metabase takes 60–90s to boot and returns
   `{"status":"initializing","progress":...}` until it is ready, so poll rather
   than reading a single response:
   ```bash
   URL=https://mfb-metabase-production-baf31df893fc.herokuapp.com/api/health
   for i in $(seq 60); do
     if curl -fsS "$URL" | grep -q '"status":"ok"'; then echo "ready"; break; fi
     echo "   waiting... ($((i * 5))s)"
     sleep 5
   done
   curl -fsS "$URL"
   ```

   Roll back with `heroku rollback vN --app mfb-metabase-production` if it never reaches `ok`.

**Important:** After a container deploy, you may need to re-run `terraform-apply` if the new Metabase version changes API behavior or database sync timing.

### Environment Reference

| Environment | Metabase URL | Django DB App |
|-------------|-------------|---------------|
| Production | `mfb-metabase-production-baf31df893fc.herokuapp.com` | `cobenefits-api` |

For secrets/variables setup, see `dashboards/GITHUB_SECRETS.md`.
For local development, see `dashboards/README.md`.

---

## Scripts

### GA4 Migration (`scripts/ga4-migration/`)

Copies GA4 events tables from the `benefits-mfb` BigQuery project to `mfb-data`.

**Prerequisites:**

1. Install the Google Cloud SDK:
   ```bash
   brew install google-cloud-sdk
   ```

2. Authenticate with a Google account that has BigQuery access to both `benefits-mfb` and `mfb-data` projects:
   ```bash
   gcloud auth login
   ```

3. Verify access:
   ```bash
   bq ls benefits-mfb:analytics_335669714 | head -5
   bq ls mfb-data:analytics_335669714 | head -5
   ```

**Usage:**

```bash
# Dry run — see what would be copied without making changes
./scripts/ga4-migration/copy_ga4_tables.sh --dry-run

# Copy all tables not yet copied
./scripts/ga4-migration/copy_ga4_tables.sh
```

The script tracks copied tables in `scripts/ga4-migration/ga4_copy_manifest.log`, so it's safe to re-run after interruption — it will skip tables already copied and pick up where it left off.
