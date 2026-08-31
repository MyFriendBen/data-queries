{{
  config(
    materialized='table'
  )
}}

-- Per-screening heat-pump journey summary (Stories 5 & 6). One row per screener_uid
-- with boolean flags for the milestones reached and the first/last event times, so
-- cards can answer:
--   Story 6 correlation — of users who reached a contractor search, how many also
--     clicked "Learn more" and how many engaged the impact calculator.
--   Story 5 clickthrough order — first_event / last_event and the per-milestone
--     first-touch timestamps give a coarse path (a full click-sequence view can be
--     layered on later if needed).
-- screener_uid is the grain because the journey is post-screening (uid present).
-- Rows with a null uid are dropped: without the key we can't attribute a journey.

with events as (
    select
        screener_state,
        screener_uid,
        event_name,
        cta,
        event_timestamp
    from {{ ref('stg_ga_heat_pump_journey') }}
    where screener_uid is not null
)

select
    screener_state,
    screener_uid,

    -- milestone flags
    logical_or(event_name = 'heat_pump_journey_learn_more_click') as clicked_learn_more,
    logical_or(event_name = 'heat_pump_cta_click' and cta = 'calculate_impact') as clicked_calculate_impact_cta,
    logical_or(event_name = 'heat_pump_calculator_field') as engaged_calculator,
    logical_or(event_name = 'heat_pump_calculator_result') as saw_calculator_results,
    logical_or(event_name in (
        'heat_pump_connect_now_find_installer',
        'heat_pump_connect_now_expand_search'
    )) as reached_contractor_search,

    min(event_timestamp) as first_event_ts,
    max(event_timestamp) as last_event_ts,

    current_timestamp() as updated_at

from events
group by screener_state, screener_uid
