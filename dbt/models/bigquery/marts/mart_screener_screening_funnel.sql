{{
  config(
    materialized='table'
  )
}}

-- Screening (screener_uid) grain — ONE ROW PER SCREENER, carrying its funnel-stage
-- flags and how many GA sessions it spanned. This is the screening-grain companion
-- to the session-grain step funnel (mart_screener_form_funnel / furthest_step).
-- Cards aggregate it:
--   * Screener Conversion Funnel: COUNTIF over the stage flags (created ->
--     saw_results -> viewed_details -> applied), a true distinct-screener subset
--     chain (every stage is the same screener_uid).
--   * Sessions per Screener: distribution of distinct_sessions across screeners
--     (how fragmented a screening is across visits).
--
-- Stage flags:
--   saw_results   = reached results at any outcome
--                   (results_loaded OR results_error OR results_none_eligible)
--   viewed_details= clicked "More info" on any program (screener_program_more_info)
--   applied       = clicked Apply on any program (screener_apply_click)
-- created is implicit — the screener exists (one row here).
--
-- A screener is attributed to the state + date of its FIRST event, so it lands in
-- one (date, state) bucket regardless of how many sessions/days it spans. is_cesn
-- is logical_or across the screener's events. distinct_sessions counts the distinct
-- ga_session_ids the screener_uid appeared under.

with events as (
    select
        (select value.string_value from unnest(event_params) where key = 'screener_uid'  limit 1) as screener_uid,
        (select value.string_value from unnest(event_params) where key = 'screener_state' limit 1) as screener_state,
        (select value.int_value    from unnest(event_params) where key = 'ga_session_id'  limit 1) as ga_session_id,
        parse_date('%Y%m%d', event_date) as event_date_parsed,
        event_timestamp,
        event_name
    from {{ source('google_analytics', 'events_*') }}
    where (select value.string_value from unnest(event_params) where key = 'screener_uid' limit 1) is not null
)

-- One row per screener_uid.
select
    screener_uid,
    -- attribute the screener to the state/date of its earliest event
    array_agg(screener_state ignore nulls order by event_timestamp limit 1)[safe_offset(0)] as screener_state,
    min(event_date_parsed) as event_date_parsed,
    logical_or(lower(screener_state) = 'cesn') as is_cesn,
    count(distinct ga_session_id) as distinct_sessions,
    logical_or(event_name in (
        'screener_results_loaded', 'screener_results_error', 'screener_results_none_eligible'
    )) as saw_results,
    logical_or(event_name = 'screener_program_more_info') as viewed_details,
    logical_or(event_name = 'screener_apply_click') as applied,
    current_timestamp() as updated_at
from events
group by screener_uid
