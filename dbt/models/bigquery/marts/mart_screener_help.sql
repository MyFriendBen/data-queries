{{
  config(
    materialized='table'
  )
}}

-- Screener help interactions - daily grain by state.
-- Two help signals share one mart via a `metric` discriminator:
--   1. help_click  — inline "?" tooltip opens, keyed by help_topic + step
--                    (the per-step confusion metric). dimension = help_topic,
--                    with screener_step_label for the step drill-down.
--   2. get_help_click — results-page "More Help / 211" CTA, keyed by location.
--                    dimension = location; screener_step_label is null.
-- Deduped by screener_uid for distinct-screening counts. help_click can fire
-- pre-uid on early steps, so uid may be null there — total_clicks is the robust
-- volume measure; distinct_screenings is a floor.

with help_click as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        'help_click' as metric,
        coalesce(help_topic, '(unspecified)') as dimension,
        screener_step_name
    from {{ ref('stg_ga_screener_help') }}
    where event_name = 'screener_help_click'
),

get_help_click as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        'get_help_click' as metric,
        coalesce(location, '(unspecified)') as dimension,
        cast(null as string) as screener_step_name
    from {{ ref('stg_ga_screener_help') }}
    where event_name = 'screener_get_help_click'
),

combined as (
    select * from help_click
    union all
    select * from get_help_click
)

select
    event_date,
    event_date_parsed,
    screener_state,
    metric,
    dimension,

    -- Human-readable step label for the help_click drill-down (null for the 211
    -- CTA, which isn't step-scoped — a null slug returns null from the macro).
    -- Shared screener_step_label macro (single source of truth).
    {{ screener_step_label('screener_step_name') }} as screener_step_label,

    count(*) as total_clicks,
    count(distinct screener_uid) as distinct_screenings,

    current_timestamp() as updated_at

from combined
group by event_date, event_date_parsed, screener_state, metric, dimension, screener_step_label
order by event_date desc, screener_state, metric, total_clicks desc
