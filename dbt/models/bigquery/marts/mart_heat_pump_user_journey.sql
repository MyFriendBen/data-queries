{{
  config(
    materialized='table'
  )
}}

-- Per-screening heat-pump journey summary (Stories 5 & 6). One row per screener_uid.
--
-- Story 6 (correlation) uses the milestone flags: of the screenings that reached a
-- contractor search, how many also clicked "Learn more" or engaged the calculator.
--
-- Story 5 (order of clickthrough) uses first_section / last_section. Debra chose a
-- step-by-step drop-off chart as the main view with a "where did they start, where
-- did they end" view beside it; these two columns power the second view. The
-- drop-off view is served by the funnel marts. A full ranked-path view was
-- deliberately deferred — it is noise until traffic builds.
--
-- screener_uid is the grain because this journey is post-screening, so the uid is
-- always present. Rows with a null uid are dropped: without the key there is no
-- journey to attribute.

with events as (
    select
        screener_state,
        screener_uid,
        event_name,
        cta,
        section,
        event_timestamp
    from {{ ref('stg_ga_heat_pump_journey') }}
    where screener_uid is not null
),

-- First and last SECTION the screening viewed. Ranked separately from the flag
-- aggregation because we want the section value at the boundary timestamps, not
-- an arbitrary one.
section_bounds as (
    select
        screener_uid,
        array_agg(section order by event_timestamp asc limit 1)[offset(0)] as first_section,
        array_agg(section order by event_timestamp desc limit 1)[offset(0)] as last_section
    from events
    where event_name = 'heat_pump_section_view'
        and section is not null
    group by screener_uid
),

-- First and last INTERACTION (any heat-pump event), for the coarse path view.
event_bounds as (
    select
        screener_uid,
        array_agg(event_name order by event_timestamp asc limit 1)[offset(0)] as first_event,
        array_agg(event_name order by event_timestamp desc limit 1)[offset(0)] as last_event
    from events
    group by screener_uid
),

flags as (
    select
        screener_state,
        screener_uid,

        logical_or(event_name = 'heat_pump_journey_learn_more_click') as clicked_learn_more,
        logical_or(event_name = 'heat_pump_cta_click' and cta = 'calculate_impact') as clicked_calculate_impact_cta,
        logical_or(event_name = 'heat_pump_calculator_field') as engaged_calculator,
        logical_or(event_name = 'heat_pump_calculator_result') as saw_calculator_results,
        logical_or(event_name = 'heat_pump_rebate_link_click') as clicked_rebate_link,
        logical_or(event_name in (
            'heat_pump_pdf_page',
            'heat_pump_pdf_print',
            'heat_pump_pdf_fullscreen'
        )) as opened_contractor_pdf,
        logical_or(event_name in (
            'heat_pump_connect_now_find_installer',
            'heat_pump_connect_now_expand_search'
        )) as reached_contractor_search,

        min(event_timestamp) as first_event_ts,
        max(event_timestamp) as last_event_ts,
        -- the day the journey started, so journey rows can be date-filtered
        date(timestamp_micros(min(event_timestamp))) as first_event_date
    from events
    group by screener_state, screener_uid
)

select
    f.screener_state,
    f.screener_uid,

    f.clicked_learn_more,
    f.clicked_calculate_impact_cta,
    f.engaged_calculator,
    f.saw_calculator_results,
    f.clicked_rebate_link,
    f.opened_contractor_pdf,
    f.reached_contractor_search,

    s.first_section,
    s.last_section,
    e.first_event,
    e.last_event,

    f.first_event_ts,
    f.last_event_ts,
    f.first_event_date,
    date_trunc(f.first_event_date, week(monday)) as first_event_week,

    current_timestamp() as updated_at

from flags f
left join section_bounds s on f.screener_uid = s.screener_uid
left join event_bounds e on f.screener_uid = e.screener_uid
