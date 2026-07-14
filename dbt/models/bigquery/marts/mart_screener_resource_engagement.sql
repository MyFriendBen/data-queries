{{
  config(
    materialized='table'
  )
}}

-- Screener results-page resource & tab engagement — daily grain by state.
-- Powers the Results dashboard tab's "Resources" sub-section:
--   1. Tab split: how many open the "long-term benefits" tab vs the
--      "additional resources" tab (from screener_results_tab_click.tab_name).
--   2. Top resources clicked: click counts per resource_name under Additional
--      Resources (from screener_additional_resource_click).
-- Two event types share one mart via a `metric` discriminator so a single
-- table backs both cards; `dimension` holds either the tab_name or the
-- resource_name depending on the metric.
-- Dedupe by screener_uid for the "distinct screenings" measure, per
-- analytics-dbt-notes.md. Resource clicks are website clicks only until
-- MFB-1306 adds the phone/website contact_method split.

with tab_clicks as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        'tab_open' as metric,
        tab_name as dimension
    from {{ ref('stg_ga_screener_resource_engagement') }}
    where event_name = 'screener_results_tab_click'
        and tab_name is not null
),

resource_clicks as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        'resource_click' as metric,
        resource_name as dimension
    from {{ ref('stg_ga_screener_resource_engagement') }}
    where event_name = 'screener_additional_resource_click'
        and resource_name is not null
),

combined as (
    select * from tab_clicks
    union all
    select * from resource_clicks
)

select
    event_date,
    event_date_parsed,
    screener_state,
    metric,
    dimension,

    count(*) as total_clicks,
    count(distinct screener_uid) as distinct_screenings,

    current_timestamp() as updated_at

from combined
group by event_date, event_date_parsed, screener_state, metric, dimension
order by event_date desc, screener_state, metric, total_clicks desc
