{{
  config(
    materialized='table'
  )
}}

-- Session-grain "furthest CESN step reached" over the combined ladder (steps
-- common to both the homeowner and renter paths). One row per CESN session with
-- the deepest combined-ladder rank it reached; the card applies the date window
-- then expands each session across the ladder (reached >= rank N) for a funnel
-- that is monotonic by construction.
--
-- Combined, not per-path: classifying a session's path requires the emitted
-- screener_path param (not yet flowing) or reaching a path-exclusive step, which
-- the homeowner path only hits near the end — so a per-path split can't show
-- early homeowner drop-off yet. The combined funnel uses every CESN session and
-- needs no path classification, so its drop-off is real. Split back into two
-- path funnels once the screener_path param is available.
--
-- Session grain = (user_pseudo_id, ga_session_id). The two path-exclusive steps
-- (appliances, energy-expenses) carry no combined rank, so they're excluded.

with ladder as (
    select screener_step_name, funnel_rank
    from ({{ screener_cesn_combined_ladder() }})
    where funnel_rank > 0
),

reached as (
    select
        f.event_date,
        f.event_date_parsed,
        to_json_string(struct(f.user_pseudo_id, f.ga_session_id)) as session_key,
        l.funnel_rank as step_rank
    from {{ ref('stg_ga_screener_form_funnel') }} f
    join ladder l on f.screener_step_name = l.screener_step_name
    where f.is_cesn
        and f.event_name = 'screener_form_step'
        and f.step_action = 'view'

    union all

    -- form_start is the rank-0 top rung.
    select
        f.event_date,
        f.event_date_parsed,
        to_json_string(struct(f.user_pseudo_id, f.ga_session_id)) as session_key,
        0 as step_rank
    from {{ ref('stg_ga_screener_form_funnel') }} f
    where f.is_cesn
        and f.event_name = 'screener_form_start'
)

select
    session_key,
    max(step_rank) as furthest_step_rank,
    max(event_date) as event_date,
    max(event_date_parsed) as event_date_parsed,

    current_timestamp() as updated_at

from reached
group by session_key
