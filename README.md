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
| **Metabase application** (the container itself) | `dashboards/Dockerfile.heroku` | Manual docker build + push |

The first two change regularly. The third changes only when upgrading Metabase versions or modifying the entrypoint — typically a few times a year.

### 1. dbt Model Changes (analytics tables)

**When:** You've added or modified SQL models in `dbt/models/`.

**Staging** runs automatically every night at 6 AM UTC. To trigger manually:
```bash
gh workflow run dbt-nightly.yml -f environment=staging --repo MyFriendBen/data-queries
```

**Production** requires manual dispatch (never runs on the cron):
```bash
gh workflow run dbt-nightly.yml -f environment=production --repo MyFriendBen/data-queries
```

To do a full refresh (rebuilds tables from scratch instead of incrementally):
```bash
gh workflow run dbt-nightly.yml -f environment=production -f full_refresh=true --repo MyFriendBen/data-queries
```

Production runs are restricted to the `main` branch.

### 2. Metabase Configuration Changes (dashboards, cards, data sources)

**When:** You've added or modified Terraform resources in `dashboards/*.tf` — new cards, dashboard layouts, data source connections, collections, etc.

These are **Metabase configuration** changes, not container changes. Terraform talks to the Metabase API to create/update resources. No container rebuild is needed.

**Workflow:**

1. Open a PR that modifies `dashboards/*.tf`
2. `terraform-plan.yml` runs automatically against staging and posts the plan as a PR comment
3. Merge to `main` → `terraform-apply.yml` auto-applies to **staging**
4. When ready, manually apply to **production**:
   ```bash
   gh workflow run terraform-apply.yml -f environment=production --repo MyFriendBen/data-queries
   ```

Production applies are restricted to the `main` branch.

**Note:** The Terraform workflow ignores changes to `dashboards/Dockerfile.heroku`, `dashboards/heroku-entrypoint.sh`, `dashboards/docker-compose.yml`, and `dashboards/README.md` — those don't affect Metabase configuration.

### 3. Metabase Container Updates (version upgrades)

**When:** You're upgrading the Metabase version (changing the `FROM` tag in `Dockerfile.heroku`) or modifying the entrypoint script. This is rare.

**Why this is separate:** Heroku Pipeline promotion (`heroku pipelines:promote`) does not work with Container Registry apps. The container must be built and pushed to each environment individually.

**Steps:**

1. Update the version in `dashboards/Dockerfile.heroku`:
   ```dockerfile
   FROM metabase/metabase:v0.XX.YY
   ```

2. Build for the correct platform (Heroku requires amd64, and the provenance flag is needed for Heroku's registry):
   ```bash
   cd dashboards
   heroku container:login
   docker build --platform linux/amd64 --provenance=false \
     -f Dockerfile.heroku \
     -t registry.heroku.com/mfb-metabase-staging/web .
   ```

3. Deploy to **staging** first:
   ```bash
   docker push registry.heroku.com/mfb-metabase-staging/web
   heroku container:release web -a mfb-metabase-staging
   ```

4. Verify staging is healthy:
   ```bash
   curl https://mfb-metabase-staging-0805953c70da.herokuapp.com/api/health
   ```

5. Deploy to **production**:
   ```bash
   docker tag registry.heroku.com/mfb-metabase-staging/web \
     registry.heroku.com/mfb-metabase-production/web
   docker push registry.heroku.com/mfb-metabase-production/web
   heroku container:release web -a mfb-metabase-production
   ```

6. Verify production:
   ```bash
   curl https://mfb-metabase-production-baf31df893fc.herokuapp.com/api/health
   ```

**Important:** After a container deploy, you may need to re-run `terraform-apply` if the new Metabase version changes API behavior or database sync timing.

### Environment Reference

| Environment | Metabase URL | Django DB App |
|-------------|-------------|---------------|
| Staging | `mfb-metabase-staging-0805953c70da.herokuapp.com` | `cobenefits-api-staging` |
| Production | `mfb-metabase-production-baf31df893fc.herokuapp.com` | `cobenefits-api` |

For secrets/variables setup, see `dashboards/GITHUB_SECRETS.md`.
For local development, see `dashboards/README.md`.
