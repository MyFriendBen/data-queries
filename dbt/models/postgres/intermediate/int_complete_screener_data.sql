{{ config(
    materialized='view',
    description='Complete screener data with eligibility calculations, broken into base tables for clarity'
) }}

WITH base_table_1 AS (
    SELECT
        ss.id,
        les.latest_snapshot_id,
        ss.user_id,
        ss.external_id,
        ss.uuid,
        ss.white_label_id,
        ss.path,
        ss.alternate_path,
        les.snapshots,

        -- Partner inference logic
        ss.is_test,

        ss.is_test_data,
        ss.is_verified,
        ss.completed,
        ss.start_date AS start_timestamp,
        ss.start_date::date AS start_date,
        ss.submission_date AS submission_timestamp,
        ss.submission_date::date AS submission_date,
        ss.agree_to_tos,
        ss.referrer_code,
        ss.referral_source,
        ss.utm_id,
        ss.utm_source,
        ss.utm_medium,
        ss.utm_campaign,
        ss.utm_content,
        ss.utm_term,
        ss.is_13_or_older,
        ss.last_tax_filing_year,
        ss.zipcode,
        COALESCE(NULLIF(TRIM(ss.county), ''), 'Unspecified') AS county,
        ss.household_assets,

        -- Language code mapping - matches data.sql exactly
        ss.housing_situation,

        ss.household_size,
        hd."<18 (#)",
        hd."<18 (%)",
        hd."18-24 (#)",
        hd."18-24 (%)",
        hd."25-34 (#)",
        hd."25-34 (%)",

        -- Household demographics
        hd."35-49 (#)",
        hd."35-49 (%)",
        hd."50-64 (#)",
        hd."50-64 (%)",
        hd."65-84 (#)",
        hd."65-84 (%)",
        hd.">84 (#)",
        hd.">84 (%)",
        mi.monthly_income,
        me.monthly_expenses,
        ss.has_ssdi,
        ss.has_chp_hi,
        ss.has_employer_hi,
        ss.has_medicaid_hi,
        ss.has_medicare_hi,
        ss.has_no_hi,

        -- Health Insurance
        ss.has_private_hi,
        ss.has_benefits,
        ss.has_acp,
        ss.has_andcs,
        ss.has_ccb,
        ss.has_ccap,
        ss.has_ccdf,

        -- Benefits
        ss.has_cdhcs,
        ss.has_chp,
        ss.has_head_start,
        ss.has_co_andso,
        ss.has_coctc,
        ss.has_coeitc,
        ss.has_cowap,
        ss.has_cpcr,
        ss.has_csfp,
        ss.has_ctc,
        ss.has_dpp,
        ss.has_ede,
        ss.has_eitc,
        ss.has_erc,
        ss.has_fatc,
        ss.has_leap,
        ss.has_lifeline,
        ss.has_ma_eaedc,
        ss.has_ma_macfc,
        ss.has_ma_maeitc,
        ss.has_ma_mbta,
        ss.has_ma_ssp,
        ss.has_medicaid,
        ss.has_mydenver,
        ss.has_nc_lieap,
        ss.has_nccip,
        ss.has_ncscca,
        ss.has_ncwap,
        ss.has_nfp,
        ss.has_nslp,
        ss.has_oap,
        ss.has_pell_grant,
        ss.has_rag,
        ss.has_rtdlive,
        ss.has_section_8,
        ss.has_snap,
        ss.has_ssi,
        ss.has_sunbucks,
        ss.has_tanf,
        ss.has_ubp,
        ss.has_upk,
        ss.has_va,
        ss.has_wic,
        ss.needs_baby_supplies,
        ss.needs_child_dev_help,
        ss.needs_food,
        ss.needs_funeral_help,
        ss.needs_housing_help,
        ss.needs_mental_health_help,

        -- Immediate Needs
        ss.needs_family_planning_help,
        ss.needs_dental_care,
        ss.needs_job_resources,
        ss.needs_legal_services,
        ss.needs_college_savings,
        ss.needs_veteran_services,
        secs.is_home_owner,
        secs.is_renter,
        secs.electric_provider,
        secs.electric_provider_name,
        secs.gas_provider AS gas_heat_provider,
        secs.gas_provider_name AS gas_heat_provider_name,
        secs.electricity_is_disconnected,
        secs.has_past_due_energy_bills,

        -- Energy calculator fields
        secs.has_old_car,
        secs.needs_dryer,
        secs.needs_hvac,
        secs.needs_stove,
        secs.needs_water_heater,
        CASE
            WHEN ss.referral_source ~* '^(testOrProspect|stagingTest|test)$' THEN 'Test'
            WHEN ss.referrer_code IS NOT NULL AND TRIM(ss.referrer_code) <> ''
                THEN COALESCE(drc1.partner, 'Other')
            WHEN ss.referral_source IS NOT NULL AND TRIM(ss.referral_source) <> ''
                THEN COALESCE(drc2.partner, 'Other')
            ELSE 'No Partner'
        END AS partner,
        TO_CHAR(ss.start_date, 'ID') AS start_day,
        TO_CHAR(ss.start_date, 'HH24') AS start_hour,
        TO_CHAR(ss.submission_date, 'ID') AS submission_day,
        TO_CHAR(ss.submission_date, 'HH24') AS submission_hour,
        CASE
            WHEN ss.request_language_code = 'af' THEN 'Afrikaans'
            WHEN ss.request_language_code = 'ar' THEN 'Arabic'
            WHEN ss.request_language_code = 'ar-dz' THEN 'Algerian Arabic'
            WHEN ss.request_language_code = 'ast' THEN 'Asturian'
            WHEN ss.request_language_code = 'az' THEN 'Azerbaijani'
            WHEN ss.request_language_code = 'bg' THEN 'Bulgarian'
            WHEN ss.request_language_code = 'be' THEN 'Belarusian'
            WHEN ss.request_language_code = 'bn' THEN 'Bengali'
            WHEN ss.request_language_code = 'br' THEN 'Breton'
            WHEN ss.request_language_code = 'bs' THEN 'Bosnian'
            WHEN ss.request_language_code = 'ca' THEN 'Catalan'
            WHEN ss.request_language_code = 'ckb' THEN 'Central Kurdish (Sorani)'
            WHEN ss.request_language_code = 'cs' THEN 'Czech'
            WHEN ss.request_language_code = 'cy' THEN 'Welsh'
            WHEN ss.request_language_code = 'da' THEN 'Danish'
            WHEN ss.request_language_code = 'de' THEN 'German'
            WHEN ss.request_language_code = 'dsb' THEN 'Lower Sorbian'
            WHEN ss.request_language_code = 'el' THEN 'Greek'
            WHEN ss.request_language_code = 'en' THEN 'English'
            WHEN ss.request_language_code = 'en-us' THEN 'English'
            WHEN ss.request_language_code = 'en-au' THEN 'Australian English'
            WHEN ss.request_language_code = 'en-gb' THEN 'British English'
            WHEN ss.request_language_code = 'eo' THEN 'Esperanto'
            WHEN ss.request_language_code = 'es' THEN 'Spanish'
            WHEN ss.request_language_code = 'es-ar' THEN 'Argentinian Spanish'
            WHEN ss.request_language_code = 'es-co' THEN 'Colombian Spanish'
            WHEN ss.request_language_code = 'es-mx' THEN 'Mexican Spanish'
            WHEN ss.request_language_code = 'es-ni' THEN 'Nicaraguan Spanish'
            WHEN ss.request_language_code = 'es-ve' THEN 'Venezuelan Spanish'
            WHEN ss.request_language_code = 'et' THEN 'Estonian'
            WHEN ss.request_language_code = 'eu' THEN 'Basque'
            WHEN ss.request_language_code = 'fa' THEN 'Persian'
            WHEN ss.request_language_code = 'fi' THEN 'Finnish'
            WHEN ss.request_language_code = 'fr' THEN 'French'
            WHEN ss.request_language_code = 'fy' THEN 'Frisian'
            WHEN ss.request_language_code = 'ga' THEN 'Irish'
            WHEN ss.request_language_code = 'gd' THEN 'Scottish Gaelic'
            WHEN ss.request_language_code = 'gl' THEN 'Galician'
            WHEN ss.request_language_code = 'he' THEN 'Hebrew'
            WHEN ss.request_language_code = 'hi' THEN 'Hindi'
            WHEN ss.request_language_code = 'hr' THEN 'Croatian'
            WHEN ss.request_language_code = 'hsb' THEN 'Upper Sorbian'
            WHEN ss.request_language_code = 'hu' THEN 'Hungarian'
            WHEN ss.request_language_code = 'hy' THEN 'Armenian'
            WHEN ss.request_language_code = 'ia' THEN 'Interlingua'
            WHEN ss.request_language_code = 'id' THEN 'Indonesian'
            WHEN ss.request_language_code = 'ig' THEN 'Igbo'
            WHEN ss.request_language_code = 'io' THEN 'Ido'
            WHEN ss.request_language_code = 'is' THEN 'Icelandic'
            WHEN ss.request_language_code = 'it' THEN 'Italian'
            WHEN ss.request_language_code = 'ja' THEN 'Japanese'
            WHEN ss.request_language_code = 'ka' THEN 'Georgian'
            WHEN ss.request_language_code = 'kab' THEN 'Kabyle'
            WHEN ss.request_language_code = 'kk' THEN 'Kazakh'
            WHEN ss.request_language_code = 'km' THEN 'Khmer'
            WHEN ss.request_language_code = 'kn' THEN 'Kannada'
            WHEN ss.request_language_code = 'ko' THEN 'Korean'
            WHEN ss.request_language_code = 'ky' THEN 'Kyrgyz'
            WHEN ss.request_language_code = 'lb' THEN 'Luxembourgish'
            WHEN ss.request_language_code = 'lt' THEN 'Lithuanian'
            WHEN ss.request_language_code = 'lv' THEN 'Latvian'
            WHEN ss.request_language_code = 'mk' THEN 'Macedonian'
            WHEN ss.request_language_code = 'ml' THEN 'Malayalam'
            WHEN ss.request_language_code = 'mn' THEN 'Mongolian'
            WHEN ss.request_language_code = 'mr' THEN 'Marathi'
            WHEN ss.request_language_code = 'ms' THEN 'Malay'
            WHEN ss.request_language_code = 'my' THEN 'Burmese'
            WHEN ss.request_language_code = 'nb' THEN 'Norwegian Bokmål'
            WHEN ss.request_language_code = 'ne' THEN 'Nepali'
            WHEN ss.request_language_code = 'nl' THEN 'Dutch'
            WHEN ss.request_language_code = 'nn' THEN 'Norwegian Nynorsk'
            WHEN ss.request_language_code = 'os' THEN 'Ossetic'
            WHEN ss.request_language_code = 'pa' THEN 'Punjabi'
            WHEN ss.request_language_code = 'pl' THEN 'Polish'
            WHEN ss.request_language_code = 'pt' THEN 'Portuguese'
            WHEN ss.request_language_code = 'pt-br' THEN 'Brazilian Portuguese'
            WHEN ss.request_language_code = 'ro' THEN 'Romanian'
            WHEN ss.request_language_code = 'ru' THEN 'Russian'
            WHEN ss.request_language_code = 'sk' THEN 'Slovak'
            WHEN ss.request_language_code = 'sl' THEN 'Slovenian'
            WHEN ss.request_language_code = 'sq' THEN 'Albanian'
            WHEN ss.request_language_code = 'sr' THEN 'Serbian'
            WHEN ss.request_language_code = 'sr-latn' THEN 'Serbian Latin'
            WHEN ss.request_language_code = 'sv' THEN 'Swedish'
            WHEN ss.request_language_code = 'sw' THEN 'Swahili'
            WHEN ss.request_language_code = 'ta' THEN 'Tamil'
            WHEN ss.request_language_code = 'te' THEN 'Telugu'
            WHEN ss.request_language_code = 'tg' THEN 'Tajik'
            WHEN ss.request_language_code = 'th' THEN 'Thai'
            WHEN ss.request_language_code = 'tk' THEN 'Turkmen'
            WHEN ss.request_language_code = 'tr' THEN 'Turkish'
            WHEN ss.request_language_code = 'tt' THEN 'Tatar'
            WHEN ss.request_language_code = 'udm' THEN 'Udmurt'
            WHEN ss.request_language_code = 'ug' THEN 'Uyghur'
            WHEN ss.request_language_code = 'uk' THEN 'Ukrainian'
            WHEN ss.request_language_code = 'ur' THEN 'Urdu'
            WHEN ss.request_language_code = 'uz' THEN 'Uzbek'
            WHEN ss.request_language_code = 'vi' THEN 'Vietnamese'
            WHEN ss.request_language_code = 'zh-hans' THEN 'Simplified Chinese'
            WHEN ss.request_language_code = 'zh-hant' THEN 'Traditional Chinese'
            ELSE '(blank)'
        END AS request_language_code

    FROM {{ source('django_apps', 'screener_screen') }} AS ss
    LEFT JOIN {{ ref('stg_referrer_codes') }} AS drc1
        ON ss.referrer_code = drc1.referrer_code AND ss.white_label_id = drc1.white_label_id
    LEFT JOIN {{ ref('stg_referrer_codes') }} AS drc2
        ON ss.referral_source = drc2.referrer_code AND ss.white_label_id = drc2.white_label_id
    LEFT JOIN {{ ref('stg_latest_eligibility_snapshot') }} AS les ON ss.id = les.screen_id
    LEFT JOIN {{ ref('stg_monthly_income') }} AS mi ON ss.id = mi.screen_id
    LEFT JOIN {{ ref('stg_monthly_expenses') }} AS me ON ss.id = me.screen_id
    LEFT JOIN {{ ref('stg_household_demographics') }} AS hd ON ss.id = hd.screen_id
    LEFT JOIN {{ source('django_apps', 'screener_energycalculatorscreen') }} AS secs ON ss.id = secs.screen_id
),

benefit_aggregates AS (
    SELECT
        pe.eligibility_snapshot_id,
        SUM(
            CASE WHEN pe.value_type = 'tax_credit' THEN pe.annual_value ELSE 0 END
        ) AS tax_credits_annual,
        SUM(
            CASE
                WHEN pe.value_type IS DISTINCT FROM 'tax_credit'
                    THEN pe.annual_value
                ELSE 0
            END
        ) AS non_tax_credit_benefits_annual
    FROM {{ ref('stg_program_eligibility') }} AS pe
    GROUP BY pe.eligibility_snapshot_id
),

base_table_2 AS (
    SELECT
        bt1.*,
        COALESCE(ba.non_tax_credit_benefits_annual, 0) AS non_tax_credit_benefits_annual,
        COALESCE(ba.tax_credits_annual, 0) AS tax_credits_annual
    FROM base_table_1 AS bt1
    LEFT JOIN benefit_aggregates AS ba ON bt1.latest_snapshot_id = ba.eligibility_snapshot_id
)

SELECT
    *,
    non_tax_credit_benefits_annual / 12 AS non_tax_credit_benefits_monthly,
    tax_credits_annual / 12 AS tax_credits_monthly
FROM base_table_2
WHERE
    completed = TRUE
    AND is_test = FALSE
    AND is_test_data = FALSE
    AND partner IS DISTINCT FROM 'Test'
