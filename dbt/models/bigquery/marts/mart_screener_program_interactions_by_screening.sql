{{
  config(
    materialized='table'
  )
}}

-- Screener program interactions at screening (screener_uid) grain — one row per
-- screening × state × interaction_type × program, rather than the daily distinct
-- counts in mart_screener_program_interactions. This lets a card
-- COUNT(DISTINCT screener_uid) across an arbitrary date range without
-- double-counting a screening active on multiple days (summing the daily mart's
-- screenings_with_interaction over a range over-counts such screenings).
-- Same interaction_type vocabulary as the daily mart.

with interactions as (
    select
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
    and program_id is not null
),

-- One row per screening × state × interaction_type × program (× document, for
-- document rows). program_name is resolved by a join below, not kept in this
-- grain, so a name that drifts in spelling can't split a screening into two rows.
distinct_rows as (
    select distinct
        event_date_parsed,
        screener_state,
        interaction_type,
        program_id,
        document_name,
        screener_uid
    from interactions
)

-- Program display name from the shared name-resolution model (document/apply
-- events carry program_id but not the name); fall back to the id.
select
    d.event_date_parsed,
    d.screener_state,
    d.interaction_type,
    d.program_id,
    coalesce(pn.program_name, d.program_id) as program_name,
    d.document_name,
    d.screener_uid
from distinct_rows d
left join {{ ref('int_screener_program_names') }} pn
    on d.program_id = pn.program_id
