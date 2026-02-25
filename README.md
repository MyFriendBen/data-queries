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
   pip3 install pre-commit
   ```

2. **Setup Git Hooks**:
   Run this once from the root folder:
   ```bash
   pre-commit install
   ```

3. **Install dbt Requirements**:
   ```bash
   pip3 install -r dbt/requirements.txt
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
