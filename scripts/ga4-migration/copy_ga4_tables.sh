#!/usr/bin/env bash
#
# Copies GA4 events tables from benefits-mfb to mfb-data.
# Logs each copied table to a manifest file for tracking.
#
# Usage:
#   ./copy_ga4_tables.sh              # Copy all tables not yet copied
#   ./copy_ga4_tables.sh --dry-run    # List tables that would be copied
#
# The manifest file (ga4_copy_manifest.log) tracks what's been copied.
# Re-running the script will skip tables already in the manifest,
# making it safe to resume after interruption.
#

set -euo pipefail

SOURCE_PROJECT="benefits-mfb"
TARGET_PROJECT="mfb-data"
DATASET="analytics_335669714"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/ga4_copy_manifest.log"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Create manifest if it doesn't exist
touch "$MANIFEST"

echo "Source:   $SOURCE_PROJECT:$DATASET"
echo "Target:   $TARGET_PROJECT:$DATASET"
echo "Manifest: $MANIFEST"
echo ""

# List all events tables in the source dataset
echo "Listing tables in $SOURCE_PROJECT:$DATASET..."
TABLES=$(bq ls --max_results=10000 "$SOURCE_PROJECT:$DATASET" | grep events_ | awk '{print $1}')

TOTAL=$(echo "$TABLES" | wc -l | tr -d ' ')
SKIPPED=0
COPIED=0
FAILED=0

echo "Found $TOTAL events tables"
echo ""

for table in $TABLES; do
    # Skip if already in manifest
    if grep -q "^$table$" "$MANIFEST" 2>/dev/null; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if $DRY_RUN; then
        echo "[DRY RUN] Would copy: $table"
        COPIED=$((COPIED + 1))
        continue
    fi

    echo "Copying $table... ($((SKIPPED + COPIED + FAILED + 1))/$TOTAL)"
    if bq cp -n "$SOURCE_PROJECT:$DATASET.$table" "$TARGET_PROJECT:$DATASET.$table" 2>&1; then
        echo "$table" >> "$MANIFEST"
        COPIED=$((COPIED + 1))
    else
        echo "FAILED: $table"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "Done."
echo "  Copied:  $COPIED"
echo "  Skipped: $SKIPPED (already in manifest)"
echo "  Failed:  $FAILED"
echo "  Total:   $TOTAL"
