{{
  config(
    materialized='table',
    post_hook="{{ setup_white_label_rls(this.name) }}",
    description='Materialized mart of per-program eligibility counts by partner and county. Dynamic: joins stg_program_eligibility directly, so new programs are included automatically without code changes.'
  )
}}

WITH program_names AS (
    SELECT
        pp.name_abbreviated,
        MAX(tt.text) AS benefit
    FROM {{ source('django_apps', 'programs_program') }} AS pp
    INNER JOIN {{ source('django_apps', 'translations_translation_translation') }} AS tt
        ON
            pp.name_id = tt.master_id
            AND tt.language_code = 'en-us'
    GROUP BY pp.name_abbreviated
),

benefit_counts AS (
    SELECT
        pe.name_abbreviated,
        COUNT(DISTINCT msd.id) AS count,
        msd.white_label_id,
        msd.partner,
        msd.county
    FROM {{ ref('mart_screener_data') }} AS msd
    INNER JOIN {{ ref('stg_program_eligibility') }} AS pe
        ON
            msd.latest_snapshot_id = pe.eligibility_snapshot_id
            AND pe.annual_value > 0
            AND msd.white_label_id = pe.white_label_id
    GROUP BY
        pe.name_abbreviated,
        msd.white_label_id,
        msd.partner,
        msd.county
)

SELECT
    COALESCE(pn.benefit, bc.name_abbreviated) AS benefit,
    bc.name_abbreviated,
    bc.count,
    bc.white_label_id,
    bc.partner,
    bc.county
FROM benefit_counts AS bc
LEFT JOIN program_names AS pn
    ON bc.name_abbreviated = pn.name_abbreviated
