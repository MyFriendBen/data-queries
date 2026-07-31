{{
  config(
    materialized='table'
  )
}}

-- Session-grain "furthest CESN step reached", split by path. One row per CESN
-- session, carrying its cesn_path (homeowner/renter) and the deepest per-path
-- funnel rank it reached. The homeowner/renter funnel cards apply the date
-- window, then expand each session across the ladder (reached >= rank N) for a
-- funnel that is monotonic by construction — mirroring mart_screener_furthest_step.
--
-- Ranks come from the per-path CESN ladder (screener_cesn_step_ladder macro), so
-- a step's rank reflects its position in THAT path (the paths order steps
-- differently). Session grain = (user_pseudo_id, ga_session_id).
--
-- cesn_path is the session-level classification from staging (emitted param, else
-- step-inference). Sessions with no resolvable path are excluded — they can't be
-- attributed to either funnel (mostly landing bounces, plus homeowners who drop
-- before the appliance step that step-inference keys on).

with ladder as (
    select cesn_path, screener_step_name, funnel_rank
    from ({{ screener_cesn_step_ladder() }})
),

-- Step views mapped to their per-path rank: a session's step counts on the rung
-- for that session's own path.
reached as (
    select
        f.event_date,
        f.event_date_parsed,
        f.cesn_path,
        to_json_string(struct(f.user_pseudo_id, f.ga_session_id)) as session_key,
        l.funnel_rank as step_rank
    from {{ ref('stg_ga_screener_form_funnel') }} f
    join ladder l
        on l.cesn_path = f.cesn_path
        and l.screener_step_name = f.screener_step_name
    where f.is_cesn
        and f.cesn_path is not null
        and f.event_name = 'screener_form_step'
        and f.step_action = 'view'

    union all

    -- form_start is the rank-0 top rung both paths share.
    select
        f.event_date,
        f.event_date_parsed,
        f.cesn_path,
        to_json_string(struct(f.user_pseudo_id, f.ga_session_id)) as session_key,
        0 as step_rank
    from {{ ref('stg_ga_screener_form_funnel') }} f
    where f.is_cesn
        and f.cesn_path is not null
        and f.event_name = 'screener_form_start'
)

select
    session_key,
    cesn_path,
    max(step_rank) as furthest_step_rank,
    max(event_date) as event_date,
    max(event_date_parsed) as event_date_parsed,

    current_timestamp() as updated_at

from reached
group by session_key, cesn_path
