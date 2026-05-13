{{ config(
    materialized='view',
    description='Program eligibility aggregated by snapshot — one row per eligibility_snapshot_id × name_abbreviated. white_label_id is sourced from screener_screen via the eligibility snapshot chain. No join to programs_program: the snapshot rows are already correctly scoped per-screen at eligibility run time, so cross-WL contamination is not possible, and joining to programs_program would silently drop historical rows whenever a program is renamed, deleted, or reassigned.'
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
WHERE pe.eligible = TRUE
GROUP BY pe.eligibility_snapshot_id, pe.name_abbreviated, pe.name, pe.value_type, scr.white_label_id
