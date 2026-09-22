{{
  config(
    materialized='table',
    description='Privacy-safe per-screening attributes (income band, region, utility) exported to BigQuery so GA4 event marts can be segmented',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

-- The bridge between Postgres screener data and the BigQuery GA4 event marts.
--
-- WHY THIS EXISTS: the heat-pump (and screener) event marts live in BigQuery,
-- keyed on screener_uid. Income, county and utility provider live in Postgres.
-- Metabase cannot join across databases in a native query, so a card cannot
-- segment GA4 events by household attributes. This model produces the small,
-- bucketed slice of household data those cards need, and the nightly job loads
-- it into BigQuery where the event marts can join it on uuid = screener_uid.
--
-- PRIVACY: this table crosses a boundary, so it carries only what a dashboard
-- filter needs and nothing that identifies a household. No raw income (band
-- only), no address, no ZIP, no name, no member detail. County is kept because
-- the region rollups are built from it and it is already on the tenant
-- dashboards. Cards suppress groups below a minimum size on top of this.
--
-- Built for every white label, not just CESN: the same three filters are useful
-- on any tenant's GA4 tabs, and scoping it to one partner now would just mean
-- rewriting it for the next one.

WITH screenings AS (
    SELECT
        s.uuid,
        s.household_size,
        s.monthly_income,
        s.submission_date,
        s.county,
        s.electric_provider,
        s.gas_heat_provider,
        s.white_label_id,
        wl.white_label_code
    FROM {{ ref('int_complete_screener_data') }} AS s
    LEFT JOIN {{ ref('stg_white_label') }} AS wl
        ON s.white_label_id = wl.white_label_id
),

-- The screening's own year decides which FPL table applies. Banding against the
-- CURRENT year instead would silently restate history every January, so a number
-- a partner quoted to a funder would stop matching the dashboard. Screenings
-- from a year OUTSIDE the covered range clamp to the nearest year inside it.
-- A gap INSIDE the range is not filled: it would leave annual_limit NULL and the
-- band 'No income on record'. The published table is contiguous, so this does not arise today.
fpl_periods AS (
    SELECT
        min(period::int) AS earliest_period,
        max(period::int) AS latest_period
    FROM {{ source('django_apps', 'programs_federalpovertylimitvalue') }}
),

with_period AS (
    SELECT
        s.*,
        -- Explicit NULL for a missing date. Postgres greatest() IGNORES NULLs, so
        -- a NULL year silently came out as earliest_period and the screening was
        -- banded against the oldest FPL table on record. int_complete_screener_data
        -- filters to completed = TRUE so it should not occur; wrong-by-default is
        -- the wrong failure mode for it if it ever does.
        CASE WHEN s.submission_date IS NULL THEN NULL
             ELSE least(
                 greatest(extract(YEAR FROM s.submission_date)::int, p.earliest_period),
                 p.latest_period
             )::text
        END AS fpl_period
    FROM screenings AS s
    CROSS JOIN fpl_periods AS p
),

-- Household sizes beyond the materialized ceiling clamp to the largest row.
-- The benefits-api side materializes well past any realistic household, so this
-- only guards against a bad size value.
with_limit AS (
    SELECT
        w.*,
        fv.annual_limit
    FROM with_period AS w
    LEFT JOIN {{ source('django_apps', 'programs_federalpovertylimitvalue') }} AS fv
        ON w.fpl_period = fv.period
        AND fv.household_size = least(
            greatest(w.household_size, 1),
            (SELECT max(household_size) FROM {{ source('django_apps', 'programs_federalpovertylimitvalue') }})
        )
),

banded AS (
    SELECT
        *,
        CASE
            WHEN monthly_income IS NULL OR annual_limit IS NULL OR annual_limit = 0 THEN NULL
            ELSE round((monthly_income * 12.0) / annual_limit * 100, 1)
        END AS fpl_percent
    FROM with_limit
),

-- County text arrives as either "Denver" or "Denver County" depending on where it
-- was set, so normalize both sides to a bare, lowercased name before matching.
regions AS (
    SELECT
        b.uuid,
        r.region,
        r.region_sort
    FROM banded AS b
    INNER JOIN {{ ref('co_county_regions') }} AS r
        ON lower(regexp_replace(trim(b.county), '\s+county$', '', 'i'))
         = lower(trim(r.county_name))
        -- Colorado tenants only. The seed is a CO county list and this model is
        -- built for every white label, so without this a Jefferson County,
        -- Missouri screening is labelled ',DRCOG,Front Range,'. CO shares county
        -- names with most states — Jefferson, Washington, Lincoln, Adams,
        -- Douglas, Logan, Morgan, Boulder. Add a state column to the seed if a
        -- second state ever needs rollups.
        AND b.white_label_code IN ('co', 'cesn')
),

region_lists AS (
    SELECT
        uuid,
        -- one comma-wrapped string rather than a row per region: joining a
        -- one-row-per-region bridge into the event marts would multiply click
        -- counts for every county that sits in two rollups, and Debra's rollups
        -- deliberately overlap. Cards match with a LIKE on the wrapped value.
        ',' || string_agg(region, ',' ORDER BY region_sort) || ',' AS region_memberships
    FROM regions
    GROUP BY uuid
)

SELECT
    b.uuid,
    -- The column the RLS policy filters on. Not exported to BigQuery: the load
    -- script names its columns and does not take this one.
    b.white_label_id,
    b.white_label_code,
    b.county,

    -- Income: bucket only, never the underlying figure.
    b.fpl_period,
    CASE
        WHEN b.fpl_percent IS NULL THEN 'No income on record'
        WHEN b.fpl_percent < 100 THEN 'Below 100% FPL'
        WHEN b.fpl_percent < 200 THEN '100–200% FPL'
        ELSE 'Above 200% FPL'
    END AS income_band,
    CASE
        WHEN b.fpl_percent IS NULL THEN 4
        WHEN b.fpl_percent < 100 THEN 1
        WHEN b.fpl_percent < 200 THEN 2
        ELSE 3
    END AS income_band_sort,
    -- The partner's default quick filter is "below 200% FPL", which spans two
    -- bands, so it gets its own flag rather than making the card express it.
    coalesce(b.fpl_percent IS NOT NULL AND b.fpl_percent < 200, FALSE)
        AS is_below_200_fpl,

    coalesce(rl.region_memberships, ',No county on record,') AS region_memberships,

    -- Utility: Xcel supplies both electricity and gas in Colorado, and the
    -- partner reads "Xcel customers" as either. Matched on a substring rather
    -- than the exact slug: the frontend pins the electric side as
    -- 'co-xcel-energy' (providers.tsx), but the provider list is fetched per-ZIP
    -- from the Rewiring America API and the gas-side id is not pinned anywhere,
    -- so an equality check would quietly miss gas-only Xcel customers. Confirm
    -- the real values with:
    --   select distinct electric_provider, gas_heat_provider from this model
    b.electric_provider,
    b.gas_heat_provider,
    coalesce(
        b.white_label_code IN ('co', 'cesn')
        AND (
            lower(coalesce(b.electric_provider, '')) LIKE '%xcel%'
            OR lower(coalesce(b.gas_heat_provider, '')) LIKE '%xcel%'
            -- Xcel's CO gas utility is legally Public Service Company of Colorado,
            -- so a gas-only Xcel household can carry a PSCo slug and never match
            -- '%xcel%' — the exact case the substring match exists to catch.
            -- Scoped to CO because "public service" also names unrelated utilities
            -- in other states (PNM, PSO, PSE&G).
            OR lower(coalesce(b.gas_heat_provider, '')) LIKE '%public service%'
            OR lower(coalesce(b.gas_heat_provider, '')) LIKE '%psco%'
        ), FALSE) AS is_xcel_customer,

    current_timestamp AS updated_at

FROM banded AS b
LEFT JOIN region_lists AS rl ON b.uuid = rl.uuid
