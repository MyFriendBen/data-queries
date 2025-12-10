{{ config(
    materialized='table',
    description='Mart model for programs data - reproduces data_programs.sql output'
) }}

-- Note: Program translations are global and not white-label specific,
-- so RLS is not applied to this table
SELECT
    ip.translation_translation_id AS id,
    ip.master_id,
    ip.label,
    ip.language_code,
    ip.text
FROM {{ ref('int_programs') }} ip
WHERE ip.label ILIKE 'program.%-value_type'
ORDER BY ip.master_id