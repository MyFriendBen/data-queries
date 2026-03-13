{{ config(
    materialized='table',
    description='Pre-aggregated mart for the Households dashboard in Metabase. One row per screener (head of household). Includes Census Bureau age bins, household size, income, expenses, assets, and language for all charts on the Households page.',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

-- Household size per screener (count of members)
WITH household_sizes AS (
    SELECT
        screen_id,
        count(*) AS household_size
    FROM {{ source('django_apps', 'screener_householdmember') }}
    GROUP BY screen_id
),

-- Age of the head of household (relationship = 'headOfHousehold' or lowest id per screen)
head_of_household AS (
    SELECT DISTINCT ON (screen_id)
        screen_id,
        age AS head_age
    FROM {{ source('django_apps', 'screener_householdmember') }}
    ORDER BY screen_id ASC, (relationship = 'headOfHousehold') DESC, id ASC
),

-- Census Bureau age bins for all household members
all_member_ages AS (
    SELECT
        screen_id,
        -- Census Bureau bins matching Looker Studio dashboard
        count(CASE WHEN age < 5 THEN 1 END) AS age_lt5_count,
        count(CASE WHEN age >= 5 AND age <= 18 THEN 1 END) AS age_5_18_count,
        count(CASE WHEN age >= 19 AND age <= 24 THEN 1 END) AS age_19_24_count,
        count(CASE WHEN age >= 25 AND age <= 44 THEN 1 END) AS age_25_44_count,
        count(CASE WHEN age >= 45 AND age <= 64 THEN 1 END) AS age_45_64_count,
        count(CASE WHEN age >= 65 THEN 1 END) AS age_65plus_count,
        count(*) AS total_members
    FROM {{ source('django_apps', 'screener_householdmember') }}
    GROUP BY screen_id
)

SELECT
    -- Screener identifiers
    s.id AS screener_id,
    s.white_label_id,
    s.partner,
    s.submission_date,
    s.request_language_code,

    -- Household size (from member count, not screener field)
    coalesce(hs.household_size, 1) AS household_size,

    -- Financials (from mart_screener_data which already has monthly_income/expenses)
    s.monthly_income,
    s.monthly_expenses,
    s.monthly_income * 12 AS annual_income,
    s.household_assets,

    -- Head of household age bin (Census Bureau bins matching Looker)
    CASE
        WHEN hoh.head_age BETWEEN 0 AND 18 THEN '0-18'
        WHEN hoh.head_age BETWEEN 19 AND 24 THEN '19-24'
        WHEN hoh.head_age BETWEEN 25 AND 44 THEN '25-44'
        WHEN hoh.head_age BETWEEN 45 AND 64 THEN '45-64'
        WHEN hoh.head_age >= 65 THEN '65+'
        ELSE 'Unknown'
    END AS head_age_bin,

    -- Head of household age bin sort order (for chart ordering)
    CASE
        WHEN hoh.head_age BETWEEN 0 AND 18 THEN 1
        WHEN hoh.head_age BETWEEN 19 AND 24 THEN 2
        WHEN hoh.head_age BETWEEN 25 AND 44 THEN 3
        WHEN hoh.head_age BETWEEN 45 AND 64 THEN 4
        WHEN hoh.head_age >= 65 THEN 5
        ELSE 6
    END AS head_age_bin_order,

    -- All-member age counts (for "What are the ages of all household members?" chart)
    coalesce(am.age_lt5_count, 0) AS members_age_lt5,
    coalesce(am.age_5_18_count, 0) AS members_age_5_18,
    coalesce(am.age_19_24_count, 0) AS members_age_19_24,
    coalesce(am.age_25_44_count, 0) AS members_age_25_44,
    coalesce(am.age_45_64_count, 0) AS members_age_45_64,
    coalesce(am.age_65plus_count, 0) AS members_age_65plus,
    coalesce(am.total_members, 1) AS total_members,

    -- Household income bin (for "What is the breakdown of household income?" chart)
    CASE
        WHEN s.monthly_income * 12 < 15000 THEN '$0-15K'
        WHEN s.monthly_income * 12 < 30000 THEN '$15-30K'
        WHEN s.monthly_income * 12 < 45000 THEN '$30-45K'
        WHEN s.monthly_income * 12 < 60000 THEN '$45-60K'
        WHEN s.monthly_income * 12 < 75000 THEN '$60-75K'
        WHEN s.monthly_income * 12 < 100000 THEN '$75-100K'
        WHEN s.monthly_income * 12 >= 100000 THEN '$100K+'
        ELSE 'Unknown'
    END AS annual_income_bin,

    CASE
        WHEN s.monthly_income * 12 < 15000 THEN 1
        WHEN s.monthly_income * 12 < 30000 THEN 2
        WHEN s.monthly_income * 12 < 45000 THEN 3
        WHEN s.monthly_income * 12 < 60000 THEN 4
        WHEN s.monthly_income * 12 < 75000 THEN 5
        WHEN s.monthly_income * 12 < 100000 THEN 6
        WHEN s.monthly_income * 12 >= 100000 THEN 7
        ELSE 8
    END AS annual_income_bin_order,

    -- Household assets bin (for "What is the breakdown of household assets?" chart)
    CASE
        WHEN s.household_assets < 1000 THEN '$0-1K'
        WHEN s.household_assets < 2000 THEN '$1-2K'
        WHEN s.household_assets < 5000 THEN '$2-5K'
        WHEN s.household_assets < 10000 THEN '$5-10K'
        WHEN s.household_assets < 50000 THEN '$10-50K'
        WHEN s.household_assets >= 50000 THEN '$50K+'
        ELSE 'Unknown'
    END AS assets_bin,

    CASE
        WHEN s.household_assets < 1000 THEN 1
        WHEN s.household_assets < 2000 THEN 2
        WHEN s.household_assets < 5000 THEN 3
        WHEN s.household_assets < 10000 THEN 4
        WHEN s.household_assets < 50000 THEN 5
        WHEN s.household_assets >= 50000 THEN 6
        ELSE 7
    END AS assets_bin_order

FROM {{ ref('mart_screener_data') }} s
LEFT JOIN household_sizes hs ON s.id = hs.screen_id
LEFT JOIN head_of_household hoh ON s.id = hoh.screen_id
LEFT JOIN all_member_ages am ON s.id = am.screen_id
