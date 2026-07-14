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
-- (see analytics-dbt-notes.md). Dedupe by screener_uid so back-nav re-views of
-- a step don't inflate "distinct screenings that reached step X".
-- screener_uid is null for top-of-funnel steps (language, select-state) before
-- a screening uuid exists; these rows are intentionally kept, not filtered.
--
-- screener_form_start / screener_form_complete are not step-scoped events, so
-- they are surfaced as synthetic '__form_start__' / '__form_complete__' step
-- rows in screenings_viewed_step, giving one table that covers both the
-- step-by-step drop-off funnel and the overall start-to-complete funnel
-- (screener_form_start fires once per screening, guarded by a sessionStorage
-- flag, so it's a clean funnel denominator per analytics-dbt-notes.md).

with step_views as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_step_name,
        screener_step_number,
        screener_uid
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
        screener_uid
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_start'

    union all

    select
        event_date,
        event_date_parsed,
        screener_state,
        '__form_complete__' as screener_step_name,
        null as screener_step_number,
        screener_uid
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_complete'
),

step_completes as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_step_name,
        screener_uid
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
        screener_uid
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_back'
),

form_errors as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_step_name,
        screener_uid,
        form_error_count
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_error'
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
    max(sv.screener_step_number) as screener_step_number,

    count(distinct sv.screener_uid) as screenings_viewed_step,
    count(distinct sc.screener_uid) as screenings_completed_step,
    count(distinct fb.screener_uid) as screenings_navigated_back,
    count(distinct fe.screener_uid) as screenings_with_error,
    coalesce(sum(fe.form_error_count), 0) as total_error_count,

    current_timestamp() as updated_at

from step_grain g
left join step_views sv
    on g.event_date = sv.event_date
    and g.screener_state = sv.screener_state
    and g.screener_step_name = sv.screener_step_name
left join step_completes sc
    on g.event_date = sc.event_date
    and g.screener_state = sc.screener_state
    and g.screener_step_name = sc.screener_step_name
left join form_backs fb
    on g.event_date = fb.event_date
    and g.screener_state = fb.screener_state
    and g.screener_step_name = fb.screener_step_name
left join form_errors fe
    on g.event_date = fe.event_date
    and g.screener_state = fe.screener_state
    and g.screener_step_name = fe.screener_step_name
group by g.event_date, g.event_date_parsed, g.screener_state, g.screener_step_name
order by g.event_date desc, g.screener_state, screener_step_number
