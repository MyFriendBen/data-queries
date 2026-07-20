{{
  config(
    materialized='table'
  )
}}

-- Screener program interaction breakdown - daily grain by state, program, and
-- interaction type
-- Powers the Results dashboard tab: apply / more-info / visit-website / phone
-- / document-download counts per program.
-- Grouped by program_id, not program_name — program_name is the English
-- display label and can vary in spelling for the same program; program_id is
-- the stable key. One arbitrary program_name is carried through per program_id
-- as the display label.

with interactions as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        program_id,
        program_name,
        case event_name
            when 'screener_apply_click' then 'apply'
            when 'screener_program_more_info' then 'more_info'
            when 'screener_program_visit_website' then 'visit_website'
            when 'screener_program_phone_click' then 'phone_click'
            when 'screener_program_document_download' then 'document_download'
            when 'screener_required_program_click' then 'required_program_click'
            when 'screener_eligibility_tags_shown' then 'eligibility_tags_shown'
            -- Per-program impression: the "shown" denominator for conversion
            -- rates (more_info / apply ÷ shown).
            when 'screener_program_shown' then 'shown'
        end as interaction_type
    from {{ ref('stg_ga_screener_program_interactions') }}
    where event_name in (
        'screener_apply_click',
        'screener_program_more_info',
        'screener_program_visit_website',
        'screener_program_phone_click',
        'screener_program_document_download',
        'screener_required_program_click',
        'screener_eligibility_tags_shown',
        'screener_program_shown'
    )
    -- program_id is expected on every one of these events; guard against
    -- unmapped/legacy rows polluting the grain
    and program_id is not null
)

select
    event_date,
    event_date_parsed,
    screener_state,
    program_id,

    -- Arbitrary display label per program_id (see note above on spelling drift)
    max(program_name) as program_name,

    interaction_type,

    count(*) as total_interactions,
    count(distinct screener_uid) as screenings_with_interaction,

    current_timestamp() as updated_at

from interactions
group by event_date, event_date_parsed, screener_state, program_id, interaction_type
order by event_date desc, screener_state, total_interactions desc
