{{
  config(
    materialized='view'
  )
}}

-- Furthest screener step reached per SESSION — the basis for a truly monotonic
-- step funnel.
--
-- The pre-aggregated mart_screener_form_funnel loses per-session sequence, so a
-- funnel built from it mixes step-view counts with results-load counts (different
-- events/grains) and comes out non-monotonic. This model computes, per session,
-- the DEEPEST funnel_rank it reached on the canonical ladder, so a downstream
-- "reached >= rank N" count is monotonic by construction.
--
-- Ranks come from screener_step_ladder() (single source of truth) via funnel_rank
-- — NOT raw screener_step_number (null/inconsistent). Off-ladder steps
-- (funnel_rank null: select-state, referral-source, member-basics, cesn-*,
-- legacy household-*) are excluded by the inner join dropping null ranks, so a
-- conditionally-shown or non-universal step can't distort "furthest reached".
--
-- Session grain = (user_pseudo_id, ga_session_id). is_cesn carried at session
-- level for downstream exclusion.

with ladder as (
    select screener_step_name, funnel_rank
    from ({{ screener_step_ladder() }})
    where funnel_rank is not null
),

-- Step VIEWS mapped to their funnel rank. Only ranked steps count.
step_views as (
    select
        f.event_date,
        f.event_date_parsed,
        f.screener_state,
        f.is_cesn,
        to_json_string(struct(f.user_pseudo_id, f.ga_session_id)) as session_key,
        r.funnel_rank as step_rank
    from {{ ref('stg_ga_screener_form_funnel') }} f
    join ladder r on f.screener_step_name = r.screener_step_name
    where f.event_name = 'screener_form_step'
        and f.step_action = 'view'
),

-- Results reached, folded in at the results rank from the ladder.
-- TRANSITION: once MFB-1348's `results` step-view is flowing, results arrives via
-- step_views above and this union is redundant (harmless under MAX) — retire it
-- then. Kept now so pre-MFB-1348 sessions still reach the terminal rank.
results_reached as (
    select
        r.event_date,
        r.event_date_parsed,
        r.screener_state,
        r.is_cesn,
        to_json_string(struct(r.user_pseudo_id, r.ga_session_id)) as session_key,
        (select funnel_rank from ladder where screener_step_name = 'results') as step_rank
    from {{ ref('stg_ga_screener_results_outcomes') }} r
    where r.event_name = 'screener_results_loaded'
),

reached as (
    select * from step_views
    union all
    select * from results_reached
)

-- One row per session: the deepest rank reached, plus a stable date/state for
-- windowing (session's last-active day). is_cesn / state via ANY_VALUE (constant
-- per session by construction).
select
    session_key,
    max(step_rank) as furthest_step_rank,
    max(event_date) as event_date,
    max(event_date_parsed) as event_date_parsed,
    any_value(screener_state) as screener_state,
    max(is_cesn) as is_cesn
from reached
group by session_key
