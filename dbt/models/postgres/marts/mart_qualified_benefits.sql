{{
  config(
    materialized='table',
    post_hook="{{ setup_white_label_rls(this.name) }}",
    description='Materialized mart of per-program eligibility counts by partner and county. Dynamic: joins stg_program_eligibility directly, so new programs are included automatically without code changes.'
  )
}}

SELECT
    COALESCE(MAX(pn.text), pe.name_abbreviated) AS benefit,
    pe.name_abbreviated,
    COUNT(DISTINCT msd.id) AS count,
    msd.white_label_id,
    msd.partner,
    msd.county,
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
GROUP BY
    pe.name_abbreviated,
    msd.white_label_id,
    msd.partner,
    msd.county,
    msd.utm_campaign,
    msd.utm_medium,
    msd.utm_source
