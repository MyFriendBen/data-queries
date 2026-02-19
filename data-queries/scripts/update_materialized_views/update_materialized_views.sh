#!/bin/bash
set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/../.."

# Configuration
DATABASE_URL="${DATABASE_URL:-}"
SKIP_BACKUP="${SKIP_BACKUP:-false}"
DRY_RUN="${DRY_RUN:-false}"
RESTORE_MODE="${RESTORE_MODE:-false}"

# Function to print colored output
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to execute SQL
execute_sql() {
    local sql="$1"
    local description="$2"

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would execute: $description"
        echo "$sql"
        return 0
    fi

    print_step "$description"
    if echo "$sql" | psql -v ON_ERROR_STOP=1 "$DATABASE_URL"; then
        print_success "Completed: $description"
        return 0
    else
        print_error "Failed: $description"
        return 1
    fi
}

# Function to execute SQL file
execute_sql_file() {
    local file_path="$1"
    local description="$2"

    if [ ! -f "$file_path" ]; then
        print_error "SQL file not found: $file_path"
        return 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would execute file: $file_path"
        return 0
    fi

    print_step "$description"
    if psql -v ON_ERROR_STOP=1 "$DATABASE_URL" < "$file_path"; then
        print_success "Completed: $description"
        return 0
    else
        print_error "Failed: $description"
        return 1
    fi
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Update materialized views on PostgreSQL database following CASCADE drop approach.

OPTIONS:
    -u, --url URL           PostgreSQL connection URL (required)
    -s, --skip-backup       Skip backup step
    -d, --dry-run           Show what would be executed without making changes
    -r, --restore           Restore views from backup tables (quick recovery)
    -h, --help              Show this help message

EXAMPLES:
    # Connect to local PostgreSQL database
    $0 --url "postgresql://localhost:5432/mydb"

    # Connect to local database with credentials
    $0 --url "postgresql://user:password@localhost:5432/mydb"

    # Connect to Heroku database (get URL from Heroku config)
    DATABASE_URL=\$(heroku config:get DATABASE_URL --app my-app)
    $0 --url "\$DATABASE_URL"

    # Dry run to see what would happen
    $0 --url "postgresql://localhost:5432/mydb" --dry-run

    # Skip backup (not recommended for production)
    $0 --url "postgresql://localhost:5432/mydb" --skip-backup

    # Restore from backups if something went wrong
    $0 --url "postgresql://localhost:5432/mydb" --restore

    # Using environment variable
    DATABASE_URL="postgresql://localhost:5432/mydb" $0

ENVIRONMENT VARIABLES:
    DATABASE_URL            PostgreSQL connection URL
    SKIP_BACKUP             Set to 'true' to skip backup
    DRY_RUN                 Set to 'true' for dry run
    RESTORE_MODE            Set to 'true' to restore from backups

PREREQUISITES:
    - psql command-line tool installed
    - SQL files updated with your changes in $SQL_DIR
    - Database connection credentials

PROCESS:
    1. Check dependencies
    2. Backup current data (optional)
    3. Drop materialized view with CASCADE
    4. Recreate materialized views in order:
       - data_referrer_codes
       - data
       - data_currentbenefits
       - data_householdmembers
       - data_immediate_needs
       - data_previous_benefits
       - data_income
       - data_expenses
       - data_tenant
    5. Verify recreated views

TESTING WORKFLOW:
    1. Test locally first:
       $0 --url "postgresql://localhost:5432/test_db" --dry-run
    2. Test locally without dry-run:
       $0 --url "postgresql://localhost:5432/test_db"
    3. Apply to production:
       DATABASE_URL=\$(heroku config:get DATABASE_URL --app my-app)
       $0 --url "\$DATABASE_URL" --dry-run  # verify first
       $0 --url "\$DATABASE_URL"           # then apply

EOF
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            DATABASE_URL="$2"
            shift 2
            ;;
        -s|--skip-backup)
            SKIP_BACKUP="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -r|--restore)
            RESTORE_MODE="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    print_error "DATABASE_URL is required (use --url flag or DATABASE_URL environment variable)"
    echo ""
    usage
fi

# Validate psql is installed
if ! command -v psql &> /dev/null; then
    print_error "psql command-line tool is not installed."
    print_error "Install PostgreSQL client: https://www.postgresql.org/download/"
    exit 1
fi

# Validate connection
print_step "Validating PostgreSQL connection"
if ! echo "SELECT 1;" | psql "$DATABASE_URL" > /dev/null 2>&1; then
    print_error "Cannot connect to PostgreSQL database"
    print_error "Please check:"
    print_error "  1. DATABASE_URL is correct"
    print_error "  2. Database server is running"
    print_error "  3. Credentials are valid"
    print_error "  4. Network connectivity"
    exit 1
fi
print_success "Connected to PostgreSQL database"

# All materialized views that will be affected by CASCADE drop
ALL_VIEWS=(
    "data_referrer_codes"
    "data"
    "data_currentbenefits"
    "data_householdmembers"
    "data_immediate_needs"
    "data_previous_benefits"
    "data_income"
    "data_expenses"
)

# Restore mode - quick recovery from backup tables
if [ "$RESTORE_MODE" = "true" ]; then
    echo ""
    print_warning "RESTORE MODE - Recreating views from backup tables"
    echo ""

    # Check that backup tables exist
    print_step "Checking backup tables exist"
    BACKUP_CHECK_SQL="SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE '%_backup' ORDER BY tablename;"
    echo "$BACKUP_CHECK_SQL" | psql "$DATABASE_URL"

    read -p "Continue with restore from backups? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_warning "Restore cancelled by user"
        exit 0
    fi

    # Drop existing (possibly broken) materialized views and data_tenant view
    print_step "Dropping existing materialized views"
    for view in "${ALL_VIEWS[@]}"; do
        DROP_SQL="DROP MATERIALIZED VIEW IF EXISTS ${view} CASCADE;"
        execute_sql "$DROP_SQL" "Drop ${view}"
    done
    execute_sql "DROP VIEW IF EXISTS data_tenant CASCADE;" "Drop data_tenant view"

    # Recreate materialized views from backup tables
    print_step "Recreating materialized views from backups"
    for view in "${ALL_VIEWS[@]}"; do
        CREATE_SQL="CREATE MATERIALIZED VIEW ${view} AS SELECT * FROM ${view}_backup;"
        execute_sql "$CREATE_SQL" "Restore ${view} from backup"
    done

    # Recreate data_tenant view (this one needs the actual SQL since it has security logic)
    print_step "Recreating data_tenant security view"
    execute_sql_file "$SQL_DIR/data_tenant.sql" "Create data_tenant security view"

    # Verify restoration
    print_step "Verifying restored views"
    VERIFY_SQL=$(cat << 'EOF'
SELECT 'data_referrer_codes' as view_name, COUNT(*) as rows FROM data_referrer_codes
UNION ALL SELECT 'data', COUNT(*) FROM data
UNION ALL SELECT 'data_currentbenefits', COUNT(*) FROM data_currentbenefits
UNION ALL SELECT 'data_householdmembers', COUNT(*) FROM data_householdmembers
UNION ALL SELECT 'data_immediate_needs', COUNT(*) FROM data_immediate_needs
UNION ALL SELECT 'data_previous_benefits', COUNT(*) FROM data_previous_benefits
UNION ALL SELECT 'data_income', COUNT(*) FROM data_income
UNION ALL SELECT 'data_expenses', COUNT(*) FROM data_expenses;
EOF
)
    execute_sql "$VERIFY_SQL" "Verify restored view row counts"

    echo ""
    print_success "Restore completed successfully!"
    print_success "All views have been restored from backup tables"
    print_warning "Note: Backup tables are still available if needed"
    exit 0
fi

echo ""
if [ "$DRY_RUN" = "true" ]; then
    print_warning "DRY RUN MODE - No changes will be made"
else
    print_warning "UPDATE MODE - This will modify the database"
fi
echo ""

# Step 1: Check Dependencies
print_step "STEP 1: Checking dependencies for data_referrer_codes"
DEPENDENCY_CHECK=$(cat << 'EOF'
-- Check all objects that depend on the view
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
EOF
)

if [ "$DRY_RUN" = "true" ]; then
    print_warning "DRY RUN: Would check dependencies"
else
    print_step "Dependencies that will be dropped with CASCADE:"
    echo "$DEPENDENCY_CHECK" | psql "$DATABASE_URL"
    echo ""
    read -p "Continue with CASCADE drop? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_warning "Operation cancelled by user"
        exit 0
    fi
fi

# Step 2: Backup (Optional)
if [ "$SKIP_BACKUP" = "false" ]; then
    print_step "STEP 2: Creating backups of all materialized views"
    for view in "${ALL_VIEWS[@]}"; do
        # Drop existing backup table if it exists
        DROP_BACKUP_SQL="DROP TABLE IF EXISTS ${view}_backup;"
        execute_sql "$DROP_BACKUP_SQL" "Drop existing ${view}_backup (if any)"
        # Create backup
        BACKUP_SQL="CREATE TABLE ${view}_backup AS SELECT * FROM ${view};"
        execute_sql "$BACKUP_SQL" "Backup ${view}"
    done

    # Verify backups
    print_step "Verifying backup row counts"
    VERIFY_BACKUPS_SQL=$(cat << 'EOF'
SELECT 'data_referrer_codes_backup' as backup_table, COUNT(*) as rows FROM data_referrer_codes_backup
UNION ALL SELECT 'data_backup', COUNT(*) FROM data_backup
UNION ALL SELECT 'data_currentbenefits_backup', COUNT(*) FROM data_currentbenefits_backup
UNION ALL SELECT 'data_householdmembers_backup', COUNT(*) FROM data_householdmembers_backup
UNION ALL SELECT 'data_immediate_needs_backup', COUNT(*) FROM data_immediate_needs_backup
UNION ALL SELECT 'data_previous_benefits_backup', COUNT(*) FROM data_previous_benefits_backup
UNION ALL SELECT 'data_income_backup', COUNT(*) FROM data_income_backup
UNION ALL SELECT 'data_expenses_backup', COUNT(*) FROM data_expenses_backup;
EOF
)
    execute_sql "$VERIFY_BACKUPS_SQL" "Verify all backup row counts"
else
    print_warning "STEP 2: Skipping backup (--skip-backup flag set)"
fi

# Step 3: Drop with CASCADE
print_step "STEP 3: Dropping data_referrer_codes with CASCADE"
DROP_SQL="DROP MATERIALIZED VIEW IF EXISTS data_referrer_codes CASCADE;"
execute_sql "$DROP_SQL" "Drop data_referrer_codes and all dependents"

# Step 4: Recreate views in order
print_step "STEP 4: Recreating materialized views"

# 4.1: Recreate data_referrer_codes
print_step "4.1: Recreating data_referrer_codes"
execute_sql_file "$SQL_DIR/data_referrer_codes.sql" "Create data_referrer_codes"

# 4.2: Recreate data (main materialized view)
print_step "4.2: Recreating data materialized view"
execute_sql_file "$SQL_DIR/data.sql" "Create data materialized view"

# 4.3: Recreate dependent views (can be done in any order)
print_step "4.3: Recreating dependent materialized views"
execute_sql_file "$SQL_DIR/data_current_benefits.sql" "Create data_current_benefits"
execute_sql_file "$SQL_DIR/data_householdmembers.sql" "Create data_householdmembers"
execute_sql_file "$SQL_DIR/data_immediate_needs.sql" "Create data_immediate_needs"
execute_sql_file "$SQL_DIR/data_previous_benefits.sql" "Create data_previous_benefits"
execute_sql_file "$SQL_DIR/data_income.sql" "Create data_income"
execute_sql_file "$SQL_DIR/data_expenses.sql" "Create data_expenses"

# 4.4: Recreate data_tenant security view
print_step "4.4: Recreating data_tenant security view"
execute_sql_file "$SQL_DIR/data_tenant.sql" "Create data_tenant security view"

# Step 5: Verify everything is working
print_step "STEP 5: Verifying recreated views"

VERIFY_MATVIEWS=$(cat << 'EOF'
SELECT schemaname, matviewname, 'materialized view' as type
FROM pg_matviews
WHERE matviewname IN (
    'data_referrer_codes',
    'data',
    'data_currentbenefits',
    'data_householdmembers',
    'data_immediate_needs',
    'data_previous_benefits',
    'data_income',
    'data_expenses'
)
ORDER BY matviewname;
EOF
)

VERIFY_VIEWS=$(cat << 'EOF'
SELECT schemaname, viewname, 'view' as type
FROM pg_views
WHERE viewname = 'data_tenant';
EOF
)

VERIFY_DATA_COUNT=$(cat << 'EOF'
SELECT
    'data' as view_name,
    COUNT(*) as row_count
FROM data
UNION ALL
SELECT
    'data_referrer_codes' as view_name,
    COUNT(*) as row_count
FROM data_referrer_codes;
EOF
)

execute_sql "$VERIFY_MATVIEWS" "Verify materialized views exist"
execute_sql "$VERIFY_VIEWS" "Verify data_tenant view exists"
execute_sql "$VERIFY_DATA_COUNT" "Verify data counts"

# Cleanup backups if everything succeeded
if [ "$SKIP_BACKUP" = "false" ]; then
    read -p "Would you like to drop all backup tables? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        for view in "${ALL_VIEWS[@]}"; do
            CLEANUP_SQL="DROP TABLE IF EXISTS ${view}_backup;"
            execute_sql "$CLEANUP_SQL" "Drop ${view}_backup"
        done
    else
        print_warning "Backup tables retained"
    fi
fi

echo ""
print_success "Materialized view update completed successfully!"
print_success "All views have been recreated and verified"

if [ "$DRY_RUN" = "true" ]; then
    echo ""
    print_warning "This was a DRY RUN - no actual changes were made"
    print_warning "Run without --dry-run flag to execute the changes"
fi
