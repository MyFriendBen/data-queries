{{ config(
    materialized='view',
    description='Intermediate model for enriched program translations'
) }}

SELECT
    sp.translation_translation_id,
    sp.master_id,
    sp.label,
    sp.language_code,
    sp.text,
    CASE
        WHEN sp.label ILIKE 'program.%-name' THEN 'Program Name'
        WHEN sp.label ILIKE 'program.%-apply_button_link' THEN 'Apply Button Link'
        WHEN sp.label ILIKE 'program.%-value_type' THEN 'Value Type'
        ELSE 'Other'
    END AS translation_type
FROM {{ ref('stg_programs') }} sp