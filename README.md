# Updating Materialized Views - Documentation

## Overview

This document provides instructions for updating materialized views, primarily using `data_referrer_codes` since that's the one that I'm working through right now, using a CASCADE DROP approach.

## Dependencies Chain

```
data_referrer_codes
    └── data (materialized view)
        ├── data_current_benefits
        ├── data_householdmembers
        ├── data_immediate_needs
        ├── data_previous_benefits
        └── data_tenant (security view with row-level security)
```

## Pre-Update Analysis

### IMPORTANT: Check All Dependencies First

Before proceeding with CASCADE drop, run these queries to identify ALL objects that will be dropped:

```sql
-- Check all objects that depend on data_referrer_codes
-- Note: Use text search approach since pg_depend doesn't capture all materialized view dependencies
SELECT
    schemaname,
    viewname,
    'view' as object_type
FROM pg_views
WHERE definition ILIKE '%from data_referrer_codes%'
   OR definition ILIKE '%join data_referrer_codes%'
   OR definition ILIKE '%data_referrer_codes.%'
UNION ALL
SELECT
    schemaname,
    matviewname,
    'materialized view' as object_type
FROM pg_matviews
WHERE definition ILIKE '%from data_referrer_codes%'
   OR definition ILIKE '%join data_referrer_codes%'
   OR definition ILIKE '%data_referrer_codes.%';

-- Check what depends on the 'data' materialized view (including data_tenant)
-- Note: Use text search approach since pg_depend doesn't capture all materialized view dependencies
SELECT
    schemaname,
    viewname,
    'view' as object_type
FROM pg_views
WHERE definition ILIKE '%from data%'
   OR definition ILIKE '%join data%'
   OR definition ILIKE '%data.%'
UNION ALL
SELECT
    schemaname,
    matviewname,
    'materialized view' as object_type
FROM pg_matviews
WHERE definition ILIKE '%from data%'
   OR definition ILIKE '%join data%'
   OR definition ILIKE '%data.%';
```

**Save the output of these queries!** You'll need to know exactly what was dropped so you can recreate everything.

### Extract DDL for Unknown Dependencies

For any views not in the data-queries folder (like data_tenant), extract their definitions:

```sql
-- Get view definition
SELECT pg_get_viewdef('data_tenant'::regclass, true);

-- Or for materialized views
SELECT definition
FROM pg_matviews
WHERE matviewname = 'data_tenant';
```

## Update Process Using CASCADE

### Step 1: Backup Current Data (Optional but Recommended)

```sql
-- Create a backup table of the current data
CREATE TABLE data_referrer_codes_backup AS
SELECT * FROM data_referrer_codes;

-- Verify backup
SELECT COUNT(*) FROM data_referrer_codes_backup;
```

### Step 2: Drop with CASCADE

```sql
-- This will drop data_referrer_codes and all dependent objects
DROP MATERIALIZED VIEW data_referrer_codes CASCADE;
```

**Warning**: This will also drop:

- `data` materialized view
- All views that depend on `data`: `data_current_benefits`, `data_householdmembers`, `data_immediate_needs`, `data_previous_benefits`
- `data_tenant` security view (and any associated permissions)

### Step 3: Recreate data_referrer_codes

```sql
-- Copy the entire contents from data_referrer_codes.sql with your updates
-- Make sure to add your new referrer codes in the VALUES clause
CREATE MATERIALIZED VIEW data_referrer_codes AS
SELECT *
FROM (
    VALUES
        (null, 'No Partner'),
        ('', 'No Partner'),
        -- ... existing values ...
        -- ADD YOUR NEW VALUES HERE
        ('newcode1', 'New Partner Name 1'),
        ('newcode2', 'New Partner Name 2')
) AS data_referrer_codes (referrer_code, partner);
```

### Step 4: Recreate the data Materialized View

```sql
-- Execute the entire data.sql file to recreate the main data view
-- This view joins with data_referrer_codes on lines 564-565
```

### Step 5: Recreate Dependent Views

Execute each of these SQL files in any order (they all depend on `data`, not on each other):

- `data_current_benefits.sql`
- `data_householdmembers.sql`
- `data_immediate_needs.sql`
- `data_previous_benefits.sql`

### Step 6: Recreate data_tenant Security View

Use `data_tenant.sql` to restore the secure view

**Note**: You may need to grant permissions to additional roles that were using data_tenant. Check the dependency analysis output from Step 2 to identify all roles that need access.

### Step 7: Verify Everything is Working

```sql
-- Check that all materialized views exist
SELECT schemaname, matviewname
FROM pg_matviews
WHERE matviewname IN (
    'data_referrer_codes',
    'data',
    'data_current_benefits',
    'data_householdmembers',
    'data_immediate_needs',
    'data_previous_benefits'
);

-- Check that data_tenant view exists
SELECT schemaname, viewname
FROM pg_views
WHERE viewname = 'data_tenant';

-- Verify data_tenant permissions
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_name = 'data_tenant';

-- Test the new referrer codes
SELECT * FROM data_referrer_codes
WHERE referrer_code IN ('newcode1', 'newcode2');

-- Verify data view is working
SELECT COUNT(*) FROM data;
```

## Alternative Approach for Future Updates

Consider converting `data_referrer_codes` to a regular table for easier maintenance:

```sql
-- Convert to regular table
CREATE TABLE referrer_codes_table AS
SELECT * FROM data_referrer_codes;

-- Create a view with the same name
CREATE VIEW data_referrer_codes AS
SELECT * FROM referrer_codes_table;

-- Future updates become simple INSERT statements
INSERT INTO referrer_codes_table VALUES ('newcode', 'Partner Name');
```

## Important Notes

1. **Production Impact**: This process will temporarily break all dependent views. Plan for downtime.

2. **Order Matters**:

   - Drop order: Automatic with CASCADE
   - Recreation order: data_referrer_codes → data → all other views

3. **Testing**: Always test this process in a development environment first.

4. **Permissions**: Ensure you have the necessary permissions to drop and create materialized views.

5. **Performance**: After recreation, you may want to refresh the materialized views if they contain stale data:

   ```sql
   REFRESH MATERIALIZED VIEW data;
   REFRESH MATERIALIZED VIEW data_current_benefits;
   -- etc. for other views
   ```

6. **CASCADE Safety**: CASCADE will NOT delete database roles (users) from pg_roles. It only drops dependent database objects like views, functions, and triggers.

## Files to Execute in Order

1. `/data-queries/data_referrer_codes.sql` (with your updates)
2. `/data-queries/data.sql`
3. These can be run in any order:
   - `/data-queries/data_current_benefits.sql`
   - `/data-queries/data_householdmembers.sql`
   - `/data-queries/data_immediate_needs.sql`
   - `/data-queries/data_previous_benefits.sql`
4. Recreate data_tenant view and permissions (see Step 6)

## Rollback Plan

If something goes wrong:

```sql
-- Restore from backup
CREATE MATERIALIZED VIEW data_referrer_codes AS
SELECT * FROM data_referrer_codes_backup;

-- Then recreate all dependent views as shown above
```
