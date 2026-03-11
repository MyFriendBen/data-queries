{{ config(
    materialized='view',
    description='Intermediate model for program translations with white_label_id'
) }}

SELECT
    sp.program_id,
    sp.translation_translation_id,
    sp.master_id,
    sp.label,
    sp.language_code,
    sp.text,
    sp.white_label_id
FROM {{ ref('stg_programs_value_types') }} AS sp
