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
-- events/grains) and comes out non-monotonic (e.g. "Reached Results" exceeding
-- later step bars because people reach results via a saved link without
-- re-viewing steps). This model instead computes, per session, the DEEPEST step
-- it reached on a single canonical ordering, so a downstream "reached >= step N"
-- count is monotonic by construction.
--
-- Ordering is an explicit step_rank (NOT the raw screener_step_number, which is
-- null for select-state and inconsistent across the household sub-steps). Results
-- is folded in as the terminal rank via screener_results_loaded (results is not a
-- screener_form_step event yet — see MFB-1344; when it is, it will slot in here as
-- an ordinary step view and this results union can retire).
--
-- Session grain = (user_pseudo_id, ga_session_id), matching the funnel-dedup key
-- used everywhere else. is_cesn is carried at session level for downstream
-- exclusion. Deliberately excludes referral-source (conditionally shown, reported
-- separately) and select-state (pre-white-label bare-domain page) from the ranked
-- ladder so a skip can't distort "furthest reached".

with step_ranks as (
    -- Canonical funnel order. Keep in sync with mart_screener_form_funnel's label
    -- CASE. CESN energy steps are intentionally omitted (CESN excluded from the
    -- global step funnel); referral-source / select-state omitted (see header).
    select 'language' as screener_step_name, 1 as step_rank, 'Language' as screener_step_label union all
    select 'disclaimer', 2, 'Disclaimer' union all
    select 'zip-code', 3, 'Zip Code' union all
    select 'household-size', 4, 'Household Size' union all
    select 'household-basics', 5, 'Household Basics' union all
    select 'household-members', 6, 'Household Members' union all
    select 'member-details', 7, 'Member Details' union all
    select 'expenses', 8, 'Expenses' union all
    select 'assets', 9, 'Assets' union all
    select 'current-benefits', 10, 'Current Benefits' union all
    select 'additional-resources', 11, 'Additional Resources' union all
    select 'sign-up', 12, 'Sign Up' union all
    select 'confirm-information', 13, 'Confirm Information' union all
    select 'results', 14, 'Reached Results'
),

-- Step VIEWS from the funnel staging, mapped to a rank. Only ranked steps count.
step_views as (
    select
        f.event_date,
        f.event_date_parsed,
        f.screener_state,
        f.is_cesn,
        to_json_string(struct(f.user_pseudo_id, f.ga_session_id)) as session_key,
        r.step_rank
    from {{ ref('stg_ga_screener_form_funnel') }} f
    join step_ranks r on f.screener_step_name = r.screener_step_name
    where f.event_name = 'screener_form_step'
        and f.step_action = 'view'
),

-- Results reached, folded in as the terminal rank (14). screener_results_loaded
-- lives in a separate staging model; dedupe to the same session key.
results_reached as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        is_cesn,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        14 as step_rank
    from {{ ref('stg_ga_screener_results_outcomes') }}
    where event_name = 'screener_results_loaded'
),

reached as (
    select * from step_views
    union all
    select * from results_reached
)

-- One row per session: the deepest rank it reached, plus a stable date/state for
-- windowing. event_date is the session's max (last-seen) day so a session is
-- attributed to when it was last active. is_cesn / state via ANY_VALUE (constant
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
