{{
  config(
    materialized='table'
  )
}}

-- Screening x step view facts at DAY grain. The SCREENING-keyed sibling of
-- mart_screener_step_facts (which is session-keyed): one row per (screener_uid,
-- screener_step_name, event_date_parsed) with a `viewed` flag. Exists so a card can
-- compute a screening-level "% of screenings that reached step X and did Y" with
-- numerator and denominator on the SAME key (screener_uid) as the action marts (e.g.
-- mart_screener_section_engagement) — a session-keyed denominator would mix grains
-- and can exceed 100% (a browser session can run multiple screenings; up to 4
-- distinct screener_uid per session×step observed).
--
-- Day grain (not one row per uid/step): the row stays on the actual day the view
-- happened, so a dashboard date filter selects the right days and a downstream
-- COUNT(DISTINCT screener_uid) dedupes to the screening WITHIN the chosen window.
-- Collapsing to a single MAX(date) per uid/step would misplace early views onto a
-- later active day and drop them from custom date ranges.
--
-- Kept minimal (viewed only) — add flags here if a future screening-level step rate
-- needs them. screener_uid is required (the whole point is the screening key), so
-- pre-white-label/null-uid rows are excluded.

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

-- Grain: one row per (screener_uid, step, DAY) — day-level membership, NOT collapsed
-- to a single date per (uid, step). Keeping the day means a dashboard date filter on
-- event_date_parsed selects exactly the days a view actually happened; a downstream
-- COUNT(DISTINCT screener_uid) then dedupes to the screening within the chosen window.
-- (A single MAX(date) per uid/step would move an early view onto a later active day,
-- so a view could fall outside a custom date range or land on a day it didn't occur.)
per_screening_step_day as (
    select
        screener_uid,
        screener_step_name,
        event_date_parsed,
        max(screener_state) as screener_state,
        max(event_name = 'screener_form_step' and step_action = 'view') as viewed
    from events
    group by screener_uid, screener_step_name, event_date_parsed
)

select
    *,
    {{ screener_step_label('screener_step_name') }} as screener_step_label
from per_screening_step_day
