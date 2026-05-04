{{ config(
    materialized='view',
    description='Intermediate model counting per-program eligibility by white_label_id and partner. Tracks programs users qualify for (annual_value > 0) — distinct from int_previous_benefits which tracks programs users report already having via has_* columns. Dynamic: joins stg_program_eligibility so new programs are included automatically.'
) }}

SELECT
    pe.name AS benefit,
    count(*) AS count,
    msd.white_label_id,
    msd.partner
FROM {{ ref('int_complete_screener_data') }} AS msd
INNER JOIN {{ ref('stg_program_eligibility') }} AS pe
    ON
        msd.latest_snapshot_id = pe.eligibility_snapshot_id
        AND pe.annual_value > 0
        AND msd.white_label_id = pe.white_label_id
GROUP BY
    pe.name,
    msd.white_label_id,
    msd.partner
