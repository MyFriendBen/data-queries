{{ config(
    materialized='table',
    description='Mart model for programs data with row-level security by white_label_id',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

SELECT
    ip.program_id,
    ip.translation_translation_id AS id,
    ip.master_id,
    ip.label,
    ip.language_code,
    ip.text,
    ip.white_label_id
FROM {{ ref('int_programs_value_types') }} ip
WHERE ip.label ILIKE 'program.%-value_type'
ORDER BY ip.white_label_id, ip.program_id