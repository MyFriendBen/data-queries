{{
  config(
    materialized='table'
  )
}}

-- Screener form funnel - daily grain by state and step
-- Powers the Form Journey dashboard tab: step-by-step drop-off funnel,
-- back-navigation, and error counts. Also powers the Overview tab's
-- start-to-complete funnel via the synthetic '__form_start__' /
-- '__form_complete__' step rows (see below).
--
-- Grain is (event_date, screener_state, screener_step_name) — NOT step number,
-- since select-state is a pre-numbered page with a null screener_step_number
-- (see analytics-dbt-notes.md).
--
-- Dedupe by SESSION KEY (user_pseudo_id, ga_session_id), NOT screener_uid.
-- screener_uid is the app-minted screening UUID, which does not exist until
-- step 3 (zip/county creates the Screen record) — so it is null on form_start,
-- language, disclaimer, and select-state. Counting distinct screener_uid would
-- therefore collapse the top-of-funnel denominator to ~0 (form_start is ~4%
-- uid-populated in prod). The GA4 session key is present on 100% of events from
-- the first pageview, so it is the correct funnel-dedup key — this matches the
-- proven approach in mart_ga_kpi_summary (the old GA tab). The output columns
-- keep the screenings_* names for consistency with sibling marts / existing
-- cards, but each is a distinct-SESSION count. screener_uid is kept in staging
-- for screening-level joins (results revisits, conversion) but is NOT the
-- funnel denominator.
--
-- screener_form_start / screener_form_complete are not step-scoped events, so
-- they are surfaced as synthetic '__form_start__' / '__form_complete__' step
-- rows in sessions_viewed_step, giving one table that covers both the
-- step-by-step drop-off funnel and the overall start-to-complete funnel
-- (screener_form_start fires once per screening, guarded by a sessionStorage
-- flag, so one session ≈ one start per analytics-dbt-notes.md).

with step_views as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_step_name,
        screener_step_number,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_step'
        and step_action = 'view'

    union all

    select
        event_date,
        event_date_parsed,
        screener_state,
        '__form_start__' as screener_step_name,
        null as screener_step_number,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_start'

    union all

    select
        event_date,
        event_date_parsed,
        screener_state,
        '__form_complete__' as screener_step_name,
        null as screener_step_number,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_complete'
),

step_completes as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_step_name,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_step'
        and step_action = 'complete'
),

form_backs as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_step_name,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_back'
),

form_errors as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_step_name,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        form_error_count
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_error'
),

-- Pre-aggregate each event source to the (date, state, step) grain BEFORE
-- joining. Joining the raw per-event CTEs directly would fan out (cartesian
-- product per grain group): the COUNT(DISTINCT session_key) measures survive
-- that (DISTINCT collapses dupes) but SUM(form_error_count) would be inflated
-- by (views x completes x backs). Aggregating first makes every side one row
-- per grain, so the join can't multiply. Same pattern as mart_screener_saves.
step_views_summary as (
    select
        event_date, event_date_parsed, screener_state, screener_step_name,
        max(screener_step_number) as screener_step_number,
        count(distinct session_key) as screenings_viewed_step
    from step_views
    group by event_date, event_date_parsed, screener_state, screener_step_name
),

step_completes_summary as (
    select
        event_date, screener_state, screener_step_name,
        count(distinct session_key) as screenings_completed_step
    from step_completes
    group by event_date, screener_state, screener_step_name
),

form_backs_summary as (
    select
        event_date, screener_state, screener_step_name,
        count(distinct session_key) as screenings_navigated_back
    from form_backs
    group by event_date, screener_state, screener_step_name
),

form_errors_summary as (
    select
        event_date, screener_state, screener_step_name,
        count(distinct session_key) as screenings_with_error,
        sum(form_error_count) as total_error_count
    from form_errors
    group by event_date, screener_state, screener_step_name
),

step_grain as (
    -- One row per (date, state, step) present in any step-scoped event, so
    -- steps with e.g. only errors and no views still surface in the funnel
    select event_date, event_date_parsed, screener_state, screener_step_name from step_views
    union distinct
    select event_date, event_date_parsed, screener_state, screener_step_name from step_completes
    union distinct
    select event_date, event_date_parsed, screener_state, screener_step_name from form_backs
    union distinct
    select event_date, event_date_parsed, screener_state, screener_step_name from form_errors
)

select
    g.event_date,
    g.event_date_parsed,
    g.screener_state,
    g.screener_step_name,

    -- Most common step number seen for this step name; null for pre-numbered
    -- pages (select-state) and the synthetic start/complete rows
    sv.screener_step_number,

    -- Column names kept as screenings_* for consistency with the sibling marts
    -- and existing dashboard cards, but these are deduped on the SESSION key
    -- (see header) — screener_uid is null pre-step-3 and would zero out the
    -- top of the funnel. "screenings" here == distinct GA4 sessions.
    coalesce(sv.screenings_viewed_step, 0) as screenings_viewed_step,
    coalesce(sc.screenings_completed_step, 0) as screenings_completed_step,
    coalesce(fb.screenings_navigated_back, 0) as screenings_navigated_back,
    coalesce(fe.screenings_with_error, 0) as screenings_with_error,
    coalesce(fe.total_error_count, 0) as total_error_count,

    current_timestamp() as updated_at

-- NULL-SAFE state join. screener_state is NULL for landing/language-page events
-- fired before the user reaches a white-label (bare entry at screener.myfriendben.org
-- vs. direct /co/... entry). step_grain UNIONs those null-state rows in, but a
-- plain `g.screener_state = x.screener_state` join evaluates NULL = NULL as
-- UNKNOWN, stranding every null-state grain row (it never matches its own summary
-- and coalesces to 0). Verified in prod: ~90% of form_start/complete sessions are
-- null-state, so the plain join undercounted "Started" by ~8x. IFNULL both sides
-- to a sentinel so null-state matches null-state.
-- NOTE (per-tenant limitation): pre-state landing sessions genuinely can't be
-- attributed to a tenant (only ~7% ever resolve a state within the session), so
-- per-tenant funnels (WHERE screener_state IN ('co')) legitimately exclude them —
-- their top-of-funnel is understated by unattributable landing traffic. The
-- global (all-states) funnel counts them correctly via this null-safe join.
from step_grain g
left join step_views_summary sv
    on g.event_date = sv.event_date
    and ifnull(g.screener_state, '∅') = ifnull(sv.screener_state, '∅')
    and g.screener_step_name = sv.screener_step_name
left join step_completes_summary sc
    on g.event_date = sc.event_date
    and ifnull(g.screener_state, '∅') = ifnull(sc.screener_state, '∅')
    and g.screener_step_name = sc.screener_step_name
left join form_backs_summary fb
    on g.event_date = fb.event_date
    and ifnull(g.screener_state, '∅') = ifnull(fb.screener_state, '∅')
    and g.screener_step_name = fb.screener_step_name
left join form_errors_summary fe
    on g.event_date = fe.event_date
    and ifnull(g.screener_state, '∅') = ifnull(fe.screener_state, '∅')
    and g.screener_step_name = fe.screener_step_name
order by g.event_date desc, g.screener_state, screener_step_number
