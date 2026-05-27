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
    AND msd.white_label_id = pp.white_label_id
LEFT JOIN {{ source('django_apps', 'translations_translation_translation') }} AS pn
    ON pp.name_id = pn.master_id
    AND pn.language_code = 'en-us'
