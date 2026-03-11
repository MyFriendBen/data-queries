{{ config(
    materialized='view',
    description='Staging model for translations_translation and translations_translation_translation tables with white_label_id'
) }}

WITH translations_t AS (
    SELECT
        tt.id AS translation_id,
        tt.label
    FROM {{ source('django_apps', 'translations_translation') }} AS tt
    WHERE
        tt.label ILIKE 'program.%-name'
        OR tt.label ILIKE 'program.%-apply_button_link'
        OR tt.label ILIKE 'program.%-value_type'
),

translations_tt AS (
    SELECT
        ttt.id AS translation_translation_id,
        ttt.master_id,
        ttt.language_code,
        ttt.text
    FROM {{ source('django_apps', 'translations_translation_translation') }} AS ttt
    INNER JOIN translations_t AS tt ON ttt.master_id = tt.translation_id
    WHERE ttt.language_code = 'en-us'
)

SELECT
    pp.id AS program_id,
    ttt.translation_translation_id,
    ttt.master_id,
    tt.label,
    ttt.language_code,
    ttt.text,
    pp.white_label_id
FROM translations_t AS tt
INNER JOIN translations_tt AS ttt ON tt.translation_id = ttt.master_id
INNER JOIN {{ source('django_apps', 'programs_program') }} AS pp ON tt.translation_id = pp.value_type_id
