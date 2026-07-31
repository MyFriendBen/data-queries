{{
  config(
    materialized='table'
  )
}}

-- Screener program interaction breakdown - daily grain by state, program,
-- interaction type, and (for document downloads) document_name.
-- Powers the Results dashboard tab: apply / more-info / visit-website / phone
-- / document-download counts per program.
-- Grouped by program_id, not program_name — program_name is the English
-- display label and can vary in spelling for the same program; program_id is
-- the stable key. One arbitrary program_name is carried through per program_id
-- as the display label.
-- document_name is in the grain so the document-download card can break out
-- WHICH document was downloaded. It is null for every non-download interaction
-- type, so those rows are unaffected (they still collapse to one null-doc row) —
-- only document_download rows split by document, which is the intent.

with interactions as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        program_id,
        document_name,
        case event_name
            when 'screener_apply_click' then 'apply'
            when 'screener_program_more_info' then 'more_info'
            when 'screener_program_visit_website' then 'visit_website'
            when 'screener_program_phone_click' then 'phone_click'
            when 'screener_program_document_download' then 'document_download'
            when 'screener_program_document_shown' then 'document_shown'
            when 'screener_required_program_click' then 'required_program_click'
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
        'screener_program_document_shown',
        'screener_required_program_click',
        'screener_program_shown'
    )
    -- program_id is expected on every one of these events; guard against
    -- unmapped/legacy rows polluting the grain. '(not set)' is the placeholder
    -- GA4 fabricates when a view_item_list is sent with an empty items array (no
    -- eligible programs to show); it's not a real program, so exclude it here.
    -- The same marker is what mart_screener_results_outcomes reads as a
    -- none-eligible screening.
    and program_id is not null
    and program_id != '(not set)'
),

aggregated as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        program_id,
        interaction_type,
        -- null except for document_download and document_shown rows
        document_name,
        count(*) as total_interactions,
        count(distinct screener_uid) as screenings_with_interaction
    from interactions
    group by event_date, event_date_parsed, screener_state, program_id, interaction_type, document_name
)

select
    a.event_date,
    a.event_date_parsed,
    a.screener_state,
    a.program_id,
    -- fall back to the id if a name was never captured for this program
    coalesce(pn.program_name, a.program_id) as program_name,
    a.interaction_type,
    a.document_name,
    a.total_interactions,
    a.screenings_with_interaction,
    current_timestamp() as updated_at

from aggregated a
left join {{ ref('int_screener_program_names') }} pn
    on a.program_id = pn.program_id
order by a.event_date desc, a.screener_state, a.total_interactions desc
