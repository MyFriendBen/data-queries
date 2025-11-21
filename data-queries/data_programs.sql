-- ## Writes a table into materialized_views to translate program codes into proper Program Names
create materialized view
    data_programs as

With translations_t as (
    select
        tt.id
        ,tt.label
    from translations_translation tt
    where label ilike 'program.%-name' or label ilike 'program.%-apply_button_link' or label ilike 'program.%-value_type'
    order by tt.id
    ),

translations_tt as (
    select ttt.id, master_id, language_code, text
    from translations_translation_translation ttt
    left join translations_t tt on ttt.master_id = tt.id
    where master_id in(tt.id) and language_code='en-us'
    )

select ttt.id, ttt.master_id, tt.label, ttt.language_code, ttt.text
from translations_t tt
left join translations_tt ttt on tt.id = ttt.master_id
where tt.label ilike 'program.%-value_type'
