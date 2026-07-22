{{
  config(
    materialized='table'
  )
}}

-- Screening x step view facts, deduped across ALL days a screening touched a step.
-- The SCREENING-keyed sibling of mart_screener_step_facts (which is session-keyed):
-- one row per (screener_uid, screener_step_name) with a `viewed` flag. Exists so a
-- card can compute a screening-level "% of screenings that reached step X and did Y"
-- with numerator and denominator on the SAME key (screener_uid) as the action marts
-- (e.g. mart_screener_section_engagement) — a session-keyed denominator would mix
-- grains and can exceed 100% (a browser session can run multiple screenings; up to
-- 4 distinct screener_uid per session×step observed).
--
-- Kept minimal (viewed only) — add flags here if a future screening-level step rate
-- needs them. screener_uid is required (the whole point is the screening key), so
-- pre-white-label/null-uid rows are excluded. Deduped across days like the session
-- sibling, so COUNT(DISTINCT screener_uid) over any window is exact.

with events as (
    select
        screener_uid,
        screener_step_name,
        screener_state,
        event_date_parsed,
        event_name,
        step_action
    from {{ ref('stg_ga_screener_form_funnel') }}
    where screener_uid is not null
        and screener_step_name is not null
        and screener_step_name not in ('__form_start__', '__form_complete__')
),

per_screening_step as (
    select
        screener_uid,
        screener_step_name,
        max(screener_state) as screener_state,
        -- attribute to the screening's last-active day on this step for windowing
        max(event_date_parsed) as event_date_parsed,
        max(event_name = 'screener_form_step' and step_action = 'view') as viewed
    from events
    group by screener_uid, screener_step_name
)

select
    *,
    {{ screener_step_label('screener_step_name') }} as screener_step_label
from per_screening_step
