{{
  config(
    materialized='table'
  )
}}

-- Session x step facts, deduped across ALL days a session touched a step. This is
-- the correct grain for "% of viewers who errored / went back on a step": counting
-- distinct sessions here is immune to the multi-day double-count that summing the
-- per-(date,step) counts in mart_screener_form_funnel suffers (a session active on
-- two days would be counted twice by that SUM).
--
-- One row per (session_key, screener_step_name). Flags are session-level facts:
-- whether the session viewed the step, hit >=1 error on it, and navigated back
-- from it. error_events sums the raw failed-attempt count (for the "total errors"
-- hover, which is intentionally an attempt count, not distinct). screener_state
-- via MAX (ignores the null pre-state row; deterministic, unlike ANY_VALUE);
-- is_cesn is session-constant upstream. screener_step_label from the shared ladder
-- macro so cards read a ready label column.

with events as (
    select
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        screener_step_name,
        screener_state,
        is_cesn,
        event_date_parsed,
        event_name,
        step_action,
        form_error_count
    from {{ ref('stg_ga_screener_form_funnel') }}
    where screener_step_name is not null
        and screener_step_name not in ('__form_start__', '__form_complete__')
),

per_session_step as (
    select
        session_key,
        screener_step_name,
        max(screener_state) as screener_state,
        max(is_cesn) as is_cesn,
        -- attribute the session's step activity to its last-active day for windowing
        max(event_date_parsed) as event_date_parsed,
        max(event_name = 'screener_form_step' and step_action = 'view') as viewed,
        max(event_name = 'screener_form_error') as errored,
        max(event_name = 'screener_form_back') as navigated_back,
        sum(case when event_name = 'screener_form_error' then form_error_count else 0 end) as error_events
    from events
    group by session_key, screener_step_name
)

select
    *,
    {{ screener_step_label('screener_step_name') }} as screener_step_label
from per_session_step
