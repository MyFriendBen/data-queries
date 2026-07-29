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
)

-- One row per screening × state × interaction_type × program across all history.
-- A card counts distinct screener_uid over its date range for a true cross-day
-- distinct.
select distinct
    event_date_parsed,
    screener_state,
    interaction_type,
    program_id,
    screener_uid
from interactions
