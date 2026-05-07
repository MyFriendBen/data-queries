{{ config(
    materialized='view',
    description='Program eligibility aggregated by snapshot — one row per eligibility_snapshot_id × name_abbreviated, filtered to only programs configured for the screen white label. Prevents cross-WL contamination for programs with shared name_abbreviated values (e.g. ctc, lifeline).'
) }}

SELECT
    pe.eligibility_snapshot_id,
    pe.name_abbreviated,
    pe.name,
    pe.value_type,
    scr.white_label_id,
    sum(pe.estimated_value) AS annual_value
FROM {{ source('django_apps', 'screener_programeligibilitysnapshot') }} AS pe
INNER JOIN {{ source('django_apps', 'screener_eligibilitysnapshot') }} AS es
    ON pe.eligibility_snapshot_id = es.id
INNER JOIN {{ source('django_apps', 'screener_screen') }} AS scr
    ON es.screen_id = scr.id
INNER JOIN {{ source('django_apps', 'programs_program') }} AS pp
    ON
        pe.name_abbreviated = pp.name_abbreviated
WHERE pe.eligible = TRUE
GROUP BY pe.eligibility_snapshot_id, pe.name_abbreviated, pe.name, pe.value_type, scr.white_label_id
