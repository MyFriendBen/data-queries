# Materialized View Update Script Usage Guide

## Quick Start

### 1. Local Development Database

Test the script on your local database first:

```bash
# Dry run to preview changes
./update_materialized_views.sh --url "postgresql://localhost:5432/mydb" --dry-run

# Execute the update
./update_materialized_views.sh --url "postgresql://localhost:5432/mydb"
```

### 2. Heroku Production Database (Recommended Approach)

Get the database URL from Heroku and use psql directly for more control:

```bash
# Get the database URL
DATABASE_URL=$(heroku config:get DATABASE_URL --app your-heroku-app)

# Dry run first
./update_materialized_views.sh --url "$DATABASE_URL" --dry-run

# Execute the update
./update_materialized_views.sh --url "$DATABASE_URL"
```

## Command Line Options

| Option              | Description                                        |
| ------------------- | -------------------------------------------------- |
| `-u, --url URL`     | PostgreSQL connection URL (required)               |
| `-s, --skip-backup` | Skip backup step                                   |
| `-d, --dry-run`     | Show what would be executed without making changes |
| `-r, --restore`     | Restore views from backup tables (quick recovery)  |
| `-h, --help`        | Show help message                                  |

## Using Environment Variables

Create a `.env` file (copy from `.env.sample`):

```bash
cp .env.sample .env
# Edit .env with your database credentials
```

Then source it before running:

```bash
source .env
./update_materialized_views.sh
```

## Common Workflows

### Testing Workflow (Recommended)

1. **Test locally with dry run:**

   ```bash
   ./update_materialized_views.sh --url "postgresql://localhost:5432/test_db" --dry-run
   ```

2. **Test locally for real:**

   ```bash
   ./update_materialized_views.sh --url "postgresql://localhost:5432/test_db"
   ```

3. **Verify locally:**

   ```bash
   psql postgresql://localhost:5432/test_db
   # Run verification queries
   SELECT * FROM data_referrer_codes;
   ```

4. **Apply to staging/production:**
   ```bash
   DATABASE_URL=$(heroku config:get DATABASE_URL --app staging-app)
   ./update_materialized_views.sh --url "$DATABASE_URL" --dry-run
   # Review output, then run without --dry-run
   ```

### Quick Update (No Backup)

**Warning:** Only use this if you're confident in your changes!

```bash
./update_materialized_views.sh --url "$DATABASE_URL" --skip-backup
```

## Connection String Formats

### Local PostgreSQL

```
postgresql://localhost:5432/database_name
postgresql://user:password@localhost:5432/database_name
```

### Heroku

```bash
# Get from Heroku
heroku config:get DATABASE_URL -a cobenefits-api

# Format (example)
postgres://user:password@ec2-host.compute.amazonaws.com:5432/database
```

## Troubleshooting

### Connection Issues

**Local database won't connect:**

```bash
# Check if PostgreSQL is running
pg_isready

# Test connection manually
psql postgresql://localhost:5432/mydb -c "SELECT 1;"
```

**Heroku connection fails:**

```bash
# Verify you're logged in
heroku auth:whoami

# Check app access
heroku apps:info --app your-app

# Test database connection
heroku pg:psql -a cobenefits-api -c "SELECT 1;"
```

### Script Issues

**psql not found:**

```bash
# macOS
brew install postgresql

# Verify installation
which psql
```

**Permission denied:**

```bash
chmod +x update_materialized_views.sh
```

### Database Issues

**View doesn't exist:**

- The view may have already been dropped
- Check if you're connected to the correct database
- Run: `\dv` in psql to list all views

## Safety Checklist

Before running against production:

- [ ] Tested on local database
- [ ] Tested on staging/review app
- [ ] Verified SQL files are correct
- [ ] Ran with `--dry-run` flag first
- [ ] Scheduled during low-traffic period
- [ ] Notified team of maintenance window
- [ ] Have rollback plan ready (see Restore section below)

## What Gets Updated

The script updates these materialized views in order:

1. `data_referrer_codes` (primary view being updated)
2. `data` (depends on data_referrer_codes)
3. `data_currentbenefits` (depends on data)
4. `data_householdmembers` (depends on data)
5. `data_immediate_needs` (depends on data)
6. `data_previous_benefits` (depends on data)
7. `data_income` (depends on data)
8. `data_expenses` (depends on data)
9. `data_tenant` (security view, depends on data)

All of these must be recreated because of PostgreSQL's CASCADE drop behavior.

## Backup and Restore

### What Gets Backed Up

The script creates backup tables for **all** materialized views before making changes:

- `data_referrer_codes_backup`
- `data_backup`
- `data_currentbenefits_backup`
- `data_householdmembers_backup`
- `data_immediate_needs_backup`
- `data_previous_benefits_backup`
- `data_income_backup`
- `data_expenses_backup`

Existing backup tables are automatically dropped and recreated.

### Quick Restore (If Something Goes Wrong)

If the update fails and dashboards are broken, use the `--restore` flag for quick recovery:

```bash
./update_materialized_views.sh --url "$DATABASE_URL" --restore
```

This will:

1. Show existing backup tables
2. Ask for confirmation
3. Drop any broken/partial materialized views
4. Recreate all views directly from backup tables (fast - no source table queries)
5. Recreate the `data_tenant` security view
6. Verify row counts

Dashboards should be back online within seconds.

### Manual Restore (Alternative)

If you prefer to restore manually:

```bash
psql "$DATABASE_URL" << 'EOF'
-- Drop broken views
DROP MATERIALIZED VIEW IF EXISTS data_referrer_codes CASCADE;

-- Restore from backup
CREATE MATERIALIZED VIEW data_referrer_codes AS SELECT * FROM data_referrer_codes_backup;
CREATE MATERIALIZED VIEW data AS SELECT * FROM data_backup;
CREATE MATERIALIZED VIEW data_currentbenefits AS SELECT * FROM data_currentbenefits_backup;
CREATE MATERIALIZED VIEW data_householdmembers AS SELECT * FROM data_householdmembers_backup;
CREATE MATERIALIZED VIEW data_immediate_needs AS SELECT * FROM data_immediate_needs_backup;
CREATE MATERIALIZED VIEW data_previous_benefits AS SELECT * FROM data_previous_benefits_backup;
CREATE MATERIALIZED VIEW data_income AS SELECT * FROM data_income_backup;
CREATE MATERIALIZED VIEW data_expenses AS SELECT * FROM data_expenses_backup;
EOF
```

### Cleaning Up Backup Tables

After a successful update, the script will ask if you want to drop the backup tables. You can also clean them up manually:

```bash
psql "$DATABASE_URL" -c "
DROP TABLE IF EXISTS data_referrer_codes_backup;
DROP TABLE IF EXISTS data_backup;
DROP TABLE IF EXISTS data_currentbenefits_backup;
DROP TABLE IF EXISTS data_householdmembers_backup;
DROP TABLE IF EXISTS data_immediate_needs_backup;
DROP TABLE IF EXISTS data_previous_benefits_backup;
DROP TABLE IF EXISTS data_income_backup;
DROP TABLE IF EXISTS data_expenses_backup;
"
```

## Advanced Usage

### Multiple Environments

Use different .env files:

```bash
# Development
source .env.development
./update_materialized_views.sh

# Staging
source .env.staging
./update_materialized_views.sh

# Production
source .env.production
./update_materialized_views.sh
```

### SSH Tunnel to Remote Database

If your database requires SSH tunneling:

```bash
# Set up tunnel
ssh -L 5433:localhost:5432 user@remote-host

# Connect through tunnel
./update_materialized_views.sh --url "postgresql://localhost:5433/mydb"
```
