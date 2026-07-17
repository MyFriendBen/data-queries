{{
  config(
    materialized='table'
  )
}}

-- Screener results-page scroll depth - daily grain by state, tab, and depth.
-- Powers the Results tab scroll funnel (25 → 50 → 75 → 100), split by tab_name
-- (long_term_benefits vs additional_resources).
-- The FE fires each threshold at most once per tab per screening, so
-- distinct-screening counts naturally form a monotonic funnel (everyone who hit
-- 75 also hit 50, etc.). Deduped by screener_uid (results events are post-step-3,
-- so uid exists).

with scroll as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        tab_name,
        depth
    from {{ ref('stg_ga_screener_scroll_depth') }}
    where depth is not null
        and tab_name is not null
)

select
    event_date,
    event_date_parsed,
    screener_state,
    tab_name,
    depth,

    count(*) as total_scroll_events,
    count(distinct screener_uid) as screenings_reached_depth,

    current_timestamp() as updated_at

from scroll
group by event_date, event_date_parsed, screener_state, tab_name, depth
order by event_date desc, screener_state, tab_name, depth
