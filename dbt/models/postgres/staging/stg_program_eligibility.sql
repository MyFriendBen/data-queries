{{ config(
    materialized='view',
    description='Program eligibility aggregated by snapshot — one row per eligibility_snapshot_id × name_abbreviated × tax_category. pe.name (translated display name) is intentionally excluded: it varies by language and would fan-out rows per translation. white_label_id is sourced from screener_screen via the eligibility snapshot chain. The program is resolved through stg_white_label_programs on name_abbreviated + white_label_id (programs of the screen white label plus federal ones, federal winning a shared name) to get tax_category from ProgramCategory; LEFT JOIN ensures historical rows for deleted or reassigned programs are retained (tax_category coalesces to FALSE).'
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
LEFT JOIN {{ ref('stg_white_label_programs') }} AS wp
    ON pe.name_abbreviated = wp.name_abbreviated
    AND scr.white_label_id = wp.white_label_id
LEFT JOIN {{ source('django_apps', 'programs_programcategory') }} AS pc
    ON wp.category_id = pc.id
WHERE pe.eligible = TRUE
GROUP BY pe.eligibility_snapshot_id, pe.name_abbreviated, COALESCE(pc.tax_category, FALSE), scr.white_label_id
