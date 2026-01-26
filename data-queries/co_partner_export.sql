-- CO Partner Data Export
-- Flat format for pivot table analysis in Excel
-- Filters: CO white label, completed screens, Jan 2024 onwards
--
-- TO EXPORT AS CSV:
-- Option 1: From psql command line
--   \COPY (SELECT * FROM co_partner_export) TO '/path/to/co_export.csv' WITH CSV HEADER
--
-- Option 2: From shell (replace connection details)
--   psql -h HOST -U USER -d DATABASE -c "\COPY (SELECT * FROM co_partner_export) TO 'co_export.csv' WITH CSV HEADER"
--
-- Option 3: Create as a view first, then export
--   CREATE VIEW co_partner_export AS <this query>;
--   \COPY (SELECT * FROM co_partner_export) TO 'co_export.csv' WITH CSV HEADER

WITH co_screens AS (
    SELECT d.*
    FROM data d
    WHERE d.white_label_id = 1  -- CO white label
      AND d.submission_date >= '2024-01-01'
),

-- Get opt-in status from user table (if user exists)
user_optins AS (
    SELECT
        s.id as screen_id,
        u.send_offers,
        u.send_updates,
        u.tcpa_consent,
        u.explicit_tcpa_consent
    FROM screener_screen s
    LEFT JOIN authentication_user u ON s.user_id = u.id
    WHERE s.user_id IS NOT NULL
)

SELECT
    -- Identifiers
    cs.id as screen_id,

    -- Time dimensions (for time period analysis)
    cs.submission_date,
    cs.start_date,
    EXTRACT(YEAR FROM cs.submission_date) as submission_year,
    EXTRACT(MONTH FROM cs.submission_date) as submission_month,
    TO_CHAR(cs.submission_date, 'YYYY-MM') as year_month,
    TO_CHAR(cs.submission_date, 'Day') as day_of_week,

    -- Season classification
    CASE
        WHEN EXTRACT(MONTH FROM cs.submission_date) IN (1, 2, 3, 4) THEN 'Tax Season (Jan-Apr)'
        WHEN EXTRACT(MONTH FROM cs.submission_date) IN (10, 11, 12) THEN 'LIHEAP Season (Oct-Dec)'
        ELSE 'Other'
    END as season,

    -- Channel/Partner dimensions
    cs.partner,
    cs.referrer_code,
    cs.referral_source,

    -- UTM dimensions (for campaign analysis)
    cs.utm_source,
    cs.utm_medium,
    cs.utm_campaign,
    cs.utm_content,
    cs.utm_term,

    -- Campaign type inference from UTM
    CASE
        WHEN cs.utm_medium ILIKE '%email%' THEN 'Email'
        WHEN cs.utm_medium ILIKE '%sms%' OR cs.utm_medium ILIKE '%text%' THEN 'Text'
        WHEN cs.utm_medium ILIKE '%social%' OR cs.utm_source ILIKE '%facebook%' OR cs.utm_source ILIKE '%instagram%' THEN 'Social Media'
        WHEN cs.utm_medium ILIKE '%print%' OR cs.utm_medium ILIKE '%poster%' OR cs.utm_medium ILIKE '%flyer%' THEN 'Print'
        WHEN cs.utm_medium ILIKE '%qr%' THEN 'QR Code'
        WHEN cs.referrer_code IS NULL OR cs.referrer_code = '' THEN 'Organic/Direct'
        ELSE 'Other/Partner'
    END as campaign_type_inferred,

    -- Language dimension
    cs.request_language_code as language,

    -- Geographic dimensions
    cs.county,
    cs.zipcode,

    -- Household composition dimensions
    cs.household_size,
    cs."<18 (#)" as children_under_18,
    cs."18-24 (#)" as young_adults_18_24,
    cs."25-34 (#)" as adults_25_34,
    cs."35-49 (#)" as adults_35_49,
    cs."50-64 (#)" as adults_50_64,
    cs."65-84 (#)" as seniors_65_84,
    cs.">84 (#)" as seniors_over_84,

    -- Household segment classification (nuanced elderly breakdown)
    CASE
        -- Elderly alone (single senior)
        WHEN cs.household_size = 1
             AND (cs."65-84 (#)" > 0 OR cs.">84 (#)" > 0)
            THEN 'Elderly Alone'

        -- Elderly couple (2-person household, both 65+)
        WHEN cs.household_size = 2
             AND (cs."65-84 (#)" + cs.">84 (#)") = 2
            THEN 'Elderly Couple'

        -- Multigenerational: elderly + children (3-gen household)
        WHEN (cs."65-84 (#)" > 0 OR cs.">84 (#)" > 0)
             AND cs."<18 (#)" > 0
            THEN 'Multigenerational (3-gen)'

        -- Elderly with adult children (65+ living with 18-64, no kids)
        WHEN (cs."65-84 (#)" > 0 OR cs.">84 (#)" > 0)
             AND cs."<18 (#)" = 0
             AND (cs."18-24 (#)" + cs."25-34 (#)" + cs."35-49 (#)" + cs."50-64 (#)") > 0
            THEN 'Elderly with Adult Children'

        -- Family with children (has kids, no elderly)
        WHEN cs."<18 (#)" > 0
             AND cs."65-84 (#)" = 0
             AND cs.">84 (#)" = 0
            THEN 'Family with Children'

        -- Single adult (1 person, working age)
        WHEN cs.household_size = 1
             AND cs."<18 (#)" = 0
             AND cs."65-84 (#)" = 0
             AND cs.">84 (#)" = 0
            THEN 'Single Adult'

        -- Adults only (multiple working-age adults, no kids/elderly)
        WHEN cs."<18 (#)" = 0
             AND cs."65-84 (#)" = 0
             AND cs.">84 (#)" = 0
            THEN 'Adults Only'

        ELSE 'Other'
    END as household_segment,

    -- More granular child classification
    CASE
        WHEN cs."<18 (#)" = 0 THEN 'No Children'
        WHEN cs."<18 (#)" > 0 THEN 'Has Children'
    END as has_children_flag,

    -- Elderly classification
    CASE
        WHEN cs."65-84 (#)" > 0 OR cs.">84 (#)" > 0 THEN 'Has Elderly (65+)'
        ELSE 'No Elderly'
    END as has_elderly_flag,

    -- Disability proxy (based on benefit receipt)
    CASE
        WHEN cs.has_ssdi = true OR cs.has_ssi = true THEN 'Has Disability Benefits'
        ELSE 'No Disability Benefits'
    END as disability_proxy,

    -- Financial dimensions
    cs.monthly_income,
    cs.monthly_expenses,
    cs.household_assets,

    -- Opt-in status (funnel metric)
    COALESCE(uo.send_offers, false) as opted_in_offers,
    COALESCE(uo.send_updates, false) as opted_in_updates,
    COALESCE(uo.tcpa_consent, false) as tcpa_consent,
    CASE
        WHEN uo.send_offers = true OR uo.send_updates = true THEN 'Opted In'
        ELSE 'Not Opted In'
    END as opt_in_status,

    -- Total benefits eligible
    cs.non_tax_credit_benefits_annual,
    cs.tax_credits_annual,
    (cs.non_tax_credit_benefits_annual + cs.tax_credits_annual) as total_benefits_annual,

    -- Individual CO-relevant program eligibility (value > 0 means eligible)
    -- SNAP
    CASE WHEN COALESCE(cs.co_snap_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_co_snap,
    cs.co_snap_annual,

    -- Medicaid
    CASE WHEN COALESCE(cs.co_medicaid_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_co_medicaid,
    cs.co_medicaid_annual,

    -- TANF
    CASE WHEN COALESCE(cs.co_tanf_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_co_tanf,
    cs.co_tanf_annual,

    -- WIC
    CASE WHEN COALESCE(cs.co_wic_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_co_wic,
    cs.co_wic_annual,

    -- LEAP (energy assistance)
    CASE WHEN COALESCE(cs.leap_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_leap,
    cs.leap_annual,

    -- CCCAP (childcare)
    CASE WHEN COALESCE(cs.cccap_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_cccap,
    cs.cccap_annual,

    -- CHP+ (children's health)
    CASE WHEN COALESCE(cs.chp_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_chp,
    cs.chp_annual,

    -- RTD LiVE (transit)
    CASE WHEN COALESCE(cs.rtdlive_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_rtdlive,
    cs.rtdlive_annual,

    -- COEITC (tax credit)
    CASE WHEN COALESCE(cs.coeitc_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_coeitc,
    cs.coeitc_annual,

    -- COCTC (tax credit)
    CASE WHEN COALESCE(cs.coctc_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_coctc,
    cs.coctc_annual,

    -- Federal EITC
    CASE WHEN COALESCE(cs.eitc_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_eitc,
    cs.eitc_annual,

    -- Federal CTC
    CASE WHEN COALESCE(cs.ctc_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_ctc,
    cs.ctc_annual,

    -- Lifeline
    CASE WHEN COALESCE(cs.lifeline_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_lifeline,
    cs.lifeline_annual,

    -- NSLP (school meals)
    CASE WHEN COALESCE(cs.nslp_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_nslp,
    cs.nslp_annual,

    -- Pell Grant
    CASE WHEN COALESCE(cs.pell_grant_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_pell_grant,
    cs.pell_grant_annual,

    -- MyDenver
    CASE WHEN COALESCE(cs.mydenver_annual, 0) > 0 THEN 1 ELSE 0 END as eligible_mydenver,
    cs.mydenver_annual,

    -- Energy calculator programs
    cs.co_energy_calculator_leap_annual,
    cs.co_energy_calculator_care_annual,
    cs.co_energy_calculator_ubp_annual,

    -- Count of programs eligible for
    (
        CASE WHEN COALESCE(cs.co_snap_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.co_medicaid_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.co_tanf_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.co_wic_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.leap_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.cccap_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.chp_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.rtdlive_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.coeitc_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.coctc_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.eitc_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.ctc_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.lifeline_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.nslp_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.pell_grant_annual, 0) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COALESCE(cs.mydenver_annual, 0) > 0 THEN 1 ELSE 0 END
    ) as programs_eligible_count

FROM co_screens cs
LEFT JOIN user_optins uo ON cs.id = uo.screen_id
ORDER BY cs.submission_date DESC;
