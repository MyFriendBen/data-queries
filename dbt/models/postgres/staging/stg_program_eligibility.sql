{{ config(
    materialized='view',
    description='Program eligibility aggregated by snapshot — one row per eligibility_snapshot_id × name_abbreviated × tax_category. pe.name (translated display name) is intentionally excluded: it varies by language and would fan-out rows per translation. white_label_id is sourced from screener_screen via the eligibility snapshot chain. programs_program is joined on name_abbreviated + white_label_id to resolve tax_category from ProgramCategory; LEFT JOIN ensures historical rows for deleted or reassigned programs are retained (tax_category coalesces to FALSE).'
) }}

SELECT
    pe.eligibility_snapshot_id,
    pe.name_abbreviated,
    COALESCE(pc.tax_category, FALSE) AS tax_category,
    scr.white_label_id,
    SUM(pe.estimated_value) AS annual_value
FROM {{ source('django_apps', 'screener_programeligibilitysnapshot') }} AS pe
INNER JOIN {{ source('django_apps', 'screener_eligibilitysnapshot') }} AS es
    ON pe.eligibility_snapshot_id = es.id
INNER JOIN {{ source('django_apps', 'screener_screen') }} AS scr
    ON es.screen_id = scr.id
LEFT JOIN {{ source('django_apps', 'programs_program') }} AS pp
    ON pe.name_abbreviated = pp.name_abbreviated
    AND scr.white_label_id = pp.white_label_id
LEFT JOIN {{ source('django_apps', 'programs_programcategory') }} AS pc
    ON pp.category_id = pc.id
WHERE pe.eligible = TRUE
GROUP BY pe.eligibility_snapshot_id, pe.name_abbreviated, COALESCE(pc.tax_category, FALSE), scr.white_label_id
