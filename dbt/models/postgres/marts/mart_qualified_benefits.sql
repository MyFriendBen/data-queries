{{
  config(
    materialized='table',
    post_hook="{{ setup_white_label_rls(this.name) }}",
    description='Materialized mart of per-program eligibility counts by partner and county. Dynamic: joins stg_program_eligibility and programs_program, so new programs are included automatically without code changes. benefit column contains the human-readable program name.'
  )
}}

SELECT
    prog.name AS benefit,
    count(*) AS count,
    msd.white_label_id,
    msd.partner,
    msd.county
FROM {{ ref('mart_screener_data') }} AS msd
INNER JOIN {{ ref('stg_program_eligibility') }} AS pe
    ON
        msd.latest_snapshot_id = pe.eligibility_snapshot_id
        AND pe.annual_value > 0
INNER JOIN {{ source('django_apps', 'programs_program') }} AS prog
    ON pe.name_abbreviated = prog.name_abbreviated
GROUP BY
    prog.name,
    msd.white_label_id,
    msd.partner,
    msd.county
