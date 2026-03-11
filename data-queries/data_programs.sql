-- ## Writes a table into materialized_views to translate program codes into proper Program Names
CREATE MATERIALIZED VIEW
data_programs AS

WITH translations_t AS (
    SELECT
        tt.id,
        tt.label
    FROM translations_translation AS tt
    WHERE
        tt.label ILIKE 'program.%-name'
        OR tt.label ILIKE 'program.%-apply_button_link'
        OR tt.label ILIKE 'program.%-value_type'
    ORDER BY tt.id
),

translations_tt AS (
    SELECT
        ttt.id,
        master_id,
        language_code,
        text
    FROM translations_translation_translation AS ttt
    LEFT JOIN translations_t AS tt ON ttt.master_id = tt.id
    WHERE master_id IN (tt.id) AND language_code = 'en-us'
)

SELECT
    ttt.id,
    ttt.master_id,
    tt.label,
    ttt.language_code,
    ttt.text
FROM translations_t AS tt
LEFT JOIN translations_tt AS ttt ON tt.id = ttt.master_id
WHERE tt.label ILIKE 'program.%-value_type'
