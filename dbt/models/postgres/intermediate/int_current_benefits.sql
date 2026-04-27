{{ config(
    materialized='view',
    description='Intermediate model aggregating current benefits counts by white_label_id, partner and program. Dynamic: joins stg_program_eligibility and programs_program so new programs are included automatically. benefit column contains the human-readable program name.'
) }}

SELECT
    prog.name AS benefit,
    count(*) AS count,
    msd.white_label_id,
    msd.partner
FROM {{ ref('int_complete_screener_data') }} AS msd
INNER JOIN {{ ref('stg_program_eligibility') }} AS pe
    ON
        msd.latest_snapshot_id = pe.eligibility_snapshot_id
        AND pe.annual_value > 0
INNER JOIN {{ source('django_apps', 'programs_program') }} AS prog
    ON pe.name_abbreviated = prog.name_abbreviated
GROUP BY
    prog.name,
    msd.white_label_id,
    msd.partner
