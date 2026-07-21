{{
  config(
    materialized='table'
  )
}}

-- Screener results-page scroll depth - FURTHEST depth reached per screening,
-- daily grain by state, tab, and depth. Powers the Results tab scroll
-- distribution (25 / 50 / 75 / 100), split by tab_name (long_term_benefits vs
-- additional_resources).
--
-- The FE fires each threshold at most once per tab per screening, so someone who
-- scrolls to 75% fires 25, 50 AND 75. Counting each threshold independently gives
-- a CUMULATIVE "reached >= depth" funnel — NOT what the card wants. Instead we
-- take the MAX depth per screening per tab, so each screening lands in exactly one
-- bucket (its deepest scroll). The result is a DISTRIBUTION (partition), so the
-- per-tab shares sum to ~100% of that tab's scrollers: "X% got no further than
-- 25%, Y% stopped at 50%, ...". depth here means "furthest reached", not
-- "reached at least".
--
-- Deduped by screener_uid (results events are post-step-3, so uid exists).
-- event_date is the screening's first scroll day so a screening attributes to one
-- day even if it scrolled across a midnight boundary.

with scroll as (
    select
        screener_uid,
        tab_name,
        depth,
        event_date_parsed,
        screener_state
    from {{ ref('stg_ga_screener_scroll_depth') }}
    where depth is not null
        and tab_name is not null
),

-- One row per (screening, tab): the DEEPEST threshold it reached.
furthest as (
    select
        screener_uid,
        tab_name,
        max(depth) as furthest_depth,
        min(event_date_parsed) as event_date_parsed,
        any_value(screener_state) as screener_state
    from scroll
    group by screener_uid, tab_name
)

select
    event_date_parsed,
    screener_state,
    tab_name,
    furthest_depth as depth,

    -- screenings whose DEEPEST scroll on this tab was exactly this depth
    count(distinct screener_uid) as screenings_reached_depth,

    current_timestamp() as updated_at

from furthest
group by event_date_parsed, screener_state, tab_name, furthest_depth
order by event_date_parsed desc, screener_state, tab_name, depth
