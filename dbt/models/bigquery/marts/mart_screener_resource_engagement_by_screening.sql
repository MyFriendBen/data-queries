{{
  config(
    materialized='table'
  )
}}

-- Screener resource & tab engagement at screening (screener_uid) grain — one row
-- per screening × metric × resource, rather than the daily distinct counts in
-- mart_screener_resource_engagement. This lets a card COUNT(DISTINCT screener_uid)
-- across an arbitrary date range without double-counting a screening that was
-- active on more than one day (summing the daily mart's distinct_screenings
-- over-counts such screenings). Same event/metric shape as the daily mart.
-- contact_method ('website' | 'phone') is set only on resource_click, null else.

with tab_clicks as (
    select
        event_date_parsed,
        screener_state,
        screener_uid,
        is_cesn,
        'tab_open' as metric,
        tab_name as dimension,
        cast(null as string) as contact_method
    from {{ ref('stg_ga_screener_resource_engagement') }}
    where event_name = 'screener_results_tab_click'
        and tab_name is not null
),

resource_shown as (
    select
        event_date_parsed,
        screener_state,
        screener_uid,
        is_cesn,
        'resource_shown' as metric,
        resource_name as dimension,
        cast(null as string) as contact_method
    from {{ ref('stg_ga_screener_resource_engagement') }}
    where event_name = 'screener_resource_shown'
        and resource_name is not null
),

resource_more_info as (
    select
        event_date_parsed,
        screener_state,
        screener_uid,
        is_cesn,
        'resource_more_info' as metric,
        resource_name as dimension,
        cast(null as string) as contact_method
    from {{ ref('stg_ga_screener_resource_engagement') }}
    where event_name = 'screener_additional_resource_more_info'
        and resource_name is not null
),

resource_clicks as (
    select
        event_date_parsed,
        screener_state,
        screener_uid,
        is_cesn,
        'resource_click' as metric,
        resource_name as dimension,
        contact_method
    from {{ ref('stg_ga_screener_resource_engagement') }}
    where event_name = 'screener_additional_resource_click'
        and resource_name is not null
),

combined as (
    select * from tab_clicks
    union all
    select * from resource_shown
    union all
    select * from resource_more_info
    union all
    select * from resource_clicks
)

-- One row per screening × metric × resource (× contact_method) across the whole
-- history. A card counts distinct screener_uid over its date range for a true
-- cross-day distinct.
select distinct
    event_date_parsed,
    screener_state,
    is_cesn,
    metric,
    dimension,
    contact_method,
    screener_uid
from combined
