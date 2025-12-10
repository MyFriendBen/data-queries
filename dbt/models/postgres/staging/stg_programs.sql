{{ config(
    materialized='view',
    description='Staging model for translations_translation and translations_translation_translation tables'
) }}

WITH translations_t AS (
    SELECT
        tt.id AS translation_id,
        tt.label
    FROM {{ source('django_apps', 'translations_translation') }} tt
    WHERE tt.label ILIKE 'program.%-name'
       OR tt.label ILIKE 'program.%-apply_button_link'
       OR tt.label ILIKE 'program.%-value_type'
),
translations_tt AS (
    SELECT
        ttt.id AS translation_translation_id,
        ttt.master_id,
        ttt.language_code,
        ttt.text
    FROM {{ source('django_apps', 'translations_translation_translation') }} ttt
    INNER JOIN translations_t tt ON ttt.master_id = tt.translation_id
    WHERE ttt.language_code = 'en-us'
)

SELECT
    ttt.translation_translation_id,
    ttt.master_id,
    tt.label,
    ttt.language_code,
    ttt.text
FROM translations_t tt
LEFT JOIN translations_tt ttt ON tt.translation_id = ttt.master_id