{{
  config(
    materialized='view'
  )
}}

-- The Postgres household-attribute bridge, as it lands in BigQuery.
--
-- mart_screener_household_attributes is built on the Postgres side and copied
-- into the BigQuery analytics dataset by the nightly job (see the "Load the
-- household-attribute bridge into BigQuery" step in .github/workflows/
-- dbt-nightly.yml). Metabase cannot join across databases in a native query, so
-- this copy is what lets a GA4 event mart be segmented by income band, region
-- or utility.
--
-- The join key is uuid on the Postgres side and screener_uid on the GA4 side —
-- the same screening identifier. Renamed here so downstream models read
-- naturally.
--
-- PRIVACY: bands and flags only. See the Postgres model for what is
-- deliberately excluded.

select
    uuid as screener_uid,
    white_label_code,
    county,

    fpl_period,
    income_band,
    income_band_sort,
    is_below_200_fpl,

    -- comma-wrapped list, e.g. ',DRCOG,Front Range,'. Wrapped so a card can test
    -- membership with a LIKE '%,Front Range,%' and never partial-match a region
    -- whose name is a prefix of another.
    region_memberships,

    electric_provider,
    gas_heat_provider,
    is_xcel_customer,

    updated_at

from {{ source('screener_bridge', 'screener_household_attributes') }}
