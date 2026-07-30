{{
  config(
    materialized='table'
  )
}}

-- Screening (screener_uid) conversion funnel — daily grain by state.
-- One row per (event_date, state) with distinct-screening counts for each funnel
-- stage. This is the SCREENING-grain companion to the session-grain step funnel
-- (mart_screener_form_funnel / furthest_step): it answers "of screeners created,
-- how many converted" and every stage is distinct screener_uid, so the ratios are
-- a true subset chain. The session -> screener handoff is a SEPARATE metric (what
-- % of sessions create a screener) — deliberately not a stage here, because ~15%+
-- of screenings span multiple sessions and a cross-grain stage ratio would be
-- invalid.
--
-- Stages:
--   created       = the screening exists (any event carried its screener_uid)
--   saw_results   = reached the results stage, any outcome
--                   (results_loaded OR results_error OR results_none_eligible)
--   viewed_details= clicked "More info" on any program (screener_program_more_info)
--   applied       = clicked Apply on any program (screener_apply_click)
--
-- A screening is attributed to the state + date of its FIRST event, so it lands
-- in one (date, state) bucket regardless of how many sessions/days it spans.
-- is_cesn is logical_or across the screening's events (CESN if any session is).

with events as (
    select
        (select value.string_value from unnest(event_params) where key = 'screener_uid'  limit 1) as screener_uid,
        (select value.string_value from unnest(event_params) where key = 'screener_state' limit 1) as screener_state,
        parse_date('%Y%m%d', event_date) as event_date_parsed,
        event_timestamp,
        event_name
    from {{ source('google_analytics', 'events_*') }}
    where (select value.string_value from unnest(event_params) where key = 'screener_uid' limit 1) is not null
),

per_screening as (
    select
        screener_uid,
        -- attribute the screening to the state/date of its earliest event
        array_agg(screener_state ignore nulls order by event_timestamp limit 1)[safe_offset(0)] as screener_state,
        min(event_date_parsed) as event_date_parsed,
        logical_or(lower(screener_state) = 'cesn') as is_cesn,
        logical_or(event_name in (
            'screener_results_loaded', 'screener_results_error', 'screener_results_none_eligible'
        )) as saw_results,
        logical_or(event_name = 'screener_program_more_info') as viewed_details,
        logical_or(event_name = 'screener_apply_click') as applied
    from events
    group by screener_uid
)

select
    event_date_parsed,
    screener_state,
    is_cesn,
    count(distinct screener_uid) as screenings_created,
    count(distinct if(saw_results, screener_uid, null)) as screenings_saw_results,
    count(distinct if(viewed_details, screener_uid, null)) as screenings_viewed_details,
    count(distinct if(applied, screener_uid, null)) as screenings_applied,
    current_timestamp() as updated_at
from per_screening
group by event_date_parsed, screener_state, is_cesn
order by event_date_parsed desc, screener_state
