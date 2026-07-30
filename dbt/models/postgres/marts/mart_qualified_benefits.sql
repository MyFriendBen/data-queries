{{
  config(
    materialized='table',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

-- One row per screen x benefit (mirrors mart_current_benefits grain).
-- The pre-aggregated form (COUNT + GROUP BY tuple) caused a semi-join leak in
-- dashboard queries: tuple matches could pull in benefit counts from screens
-- outside the selected date range.  Exposing screen_id lets the dashboard SQL
-- filter with `WHERE screen_id IN (SELECT id FROM mart_screener_data WHERE ...)`
-- instead, which correctly enforces the date boundary.
SELECT
    msd.id                                              AS screen_id,
    COALESCE(pn.text, pe.name_abbreviated)              AS benefit_display_name,
    pe.name_abbreviated                                 AS benefit_name,
    msd.white_label_id,
    msd.partner,
    msd.county,
    msd.submission_date,
    msd.utm_campaign,
    msd.utm_medium,
    msd.utm_source
FROM {{ ref('mart_screener_data') }} AS msd
INNER JOIN {{ ref('stg_program_eligibility') }} AS pe
    ON
        msd.latest_snapshot_id = pe.eligibility_snapshot_id
        AND pe.annual_value > 0
        AND msd.white_label_id = pe.white_label_id
LEFT JOIN {{ source('django_apps', 'programs_program') }} AS pp
    ON
        pe.name_abbreviated = pp.name_abbreviated
        AND msd.white_label_id = pp.white_label_id
LEFT JOIN {{ source('django_apps', 'translations_translation_translation') }} AS pn
    ON
        pp.name_id = pn.master_id
        AND pn.language_code = 'en-us'
