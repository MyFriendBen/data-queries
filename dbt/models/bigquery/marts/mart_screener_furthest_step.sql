{{
  config(
    materialized='table'
  )
}}

-- Session-grain "furthest screener step reached" — one row per session, carrying
-- the deepest canonical step rank it reached (see int_screener_furthest_step for
-- how the rank is derived and why raw screener_step_number is not used).
--
-- Deliberately NOT pre-aggregated to a "reached >= N" funnel here: the step funnel
-- card must respect the dashboard date range, and cumulative-per-day counts can't
-- be re-summed across a window. Keeping session grain lets the card apply the date
-- filter first, then expand each surviving session across the step ladder
-- (furthest_step_rank >= rank) to produce a monotonic funnel for exactly the
-- selected window.
--
-- event_date is the session's last-active day (from the intermediate) so a session
-- lands in the window by when it was last engaged.

select
    session_key,
    furthest_step_rank,
    event_date,
    event_date_parsed,
    screener_state,
    is_cesn,

    current_timestamp() as updated_at

from {{ ref('int_screener_furthest_step') }}
