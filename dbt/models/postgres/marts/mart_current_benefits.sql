{{
  config(
    materialized='table',
    post_hook="{{ setup_white_label_rls(this.name) }}",
    description='One row per screen × benefit sourced from the screener_current_benefits join table. Replaces the old has_* column approach.'
  )
}}

SELECT
    cb.screen_id,
    pp.white_label_id,
    msd.partner,
    msd.county,
    msd.submission_date,
    msd.utm_campaign,
    msd.utm_medium,
    msd.utm_source,
    pp.name_abbreviated AS benefit_name,
    COALESCE(pn.text, pp.name_abbreviated) AS benefit_display_name
FROM {{ ref('stg_current_benefits') }} AS cb
INNER JOIN {{ source('django_apps', 'programs_program') }} AS pp
    ON cb.program_id = pp.id
INNER JOIN {{ ref('mart_screener_data') }} AS msd
    ON cb.screen_id = msd.id
    -- Defensive: also require the program's white_label to match the screen's.
    -- Silently drops any anomalous join-table rows that point at a program from
    -- a different white_label than the screen (should never happen, but safer
    -- to drop than to leak across WL boundaries).
    AND pp.white_label_id = msd.white_label_id
LEFT JOIN {{ source('django_apps', 'translations_translation_translation') }} AS pn
    ON pp.name_id = pn.master_id
    AND pn.language_code = 'en-us'
