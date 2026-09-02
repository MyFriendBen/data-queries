#!/usr/bin/env bash
#
# Copy the Postgres household-attribute bridge into BigQuery.
#
# The GA4 event marts live in BigQuery; income, county and utility provider live
# in Postgres. Metabase cannot join across databases in a native query, so the
# bucketed attributes are copied over. Runs between the two dbt builds: after
# Postgres has rebuilt mart_screener_household_attributes, and before the
# BigQuery build whose models read it.
#
# Shared by dbt-nightly.yml and dbt-on-merge.yml — both run the BigQuery build,
# so both need the source table to exist. Keep it in one place so they cannot
# drift apart.
#
# PRIVACY: bands and flags only — no raw income, address or ZIP leaves Postgres.
# See mart_screener_household_attributes for what is deliberately excluded.
#
# Requires: DB_HOST, DB_USER, DB_PASS, DB_NAME, GCP_PROJECT_ID

set -euo pipefail

: "${DB_HOST:?}" "${DB_USER:?}" "${DB_PASS:?}" "${DB_NAME:?}" "${GCP_PROJECT_ID:?}"

CSV="$(mktemp -t household_attributes.XXXXXX).csv"
trap 'rm -f "$CSV"' EXIT

# Explicit column list, not SELECT *, for two reasons:
#   1. psql renders a Postgres boolean as t/f, and BigQuery's CSV parser only
#      accepts true/false for BOOL. Under --autodetect those columns would land
#      as STRING while the marts compare them as booleans, so the BigQuery build
#      would fail on a type mismatch. Casting to ::text yields 'true'/'false',
#      which autodetect types correctly as BOOL.
#   2. It pins column order, so adding a column to the mart cannot silently
#      shift what --autodetect maps where.
PGPASSWORD="$DB_PASS" psql \
  -h "$DB_HOST" \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  --csv \
  -c "SELECT
        uuid,
        white_label_code,
        county,
        fpl_period,
        income_band,
        income_band_sort,
        is_below_200_fpl::text AS is_below_200_fpl,
        region_memberships,
        electric_provider,
        gas_heat_provider,
        is_xcel_customer::text AS is_xcel_customer,
        updated_at
      FROM analytics.mart_screener_household_attributes;" \
  > "$CSV"

ROWS=$(($(wc -l < "$CSV") - 1))
echo "Exported ${ROWS} row(s) from Postgres."

# A truncating load of an empty export would wipe segmentation on every card, so
# fail loudly instead. An empty result means the upstream mart did not build, not
# that there are no screenings.
if [ "$ROWS" -le 0 ]; then
  echo "::error::Household-attribute export is empty — refusing to truncate the BigQuery copy"
  exit 1
fi

bq load \
  --project_id="${GCP_PROJECT_ID}" \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --autodetect \
  --replace \
  "${GCP_PROJECT_ID}:analytics.screener_household_attributes" \
  "$CSV"

echo "Loaded ${ROWS} row(s) into ${GCP_PROJECT_ID}:analytics.screener_household_attributes"
