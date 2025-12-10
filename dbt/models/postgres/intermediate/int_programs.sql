{{ config(
    materialized='view',
    description='Intermediate model for program translations - passes through staging data'
) }}

SELECT
    sp.translation_translation_id,
    sp.master_id,
    sp.label,
    sp.language_code,
    sp.text
FROM {{ ref('stg_programs') }} sp