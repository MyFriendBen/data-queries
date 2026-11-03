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
--
-- screener_referrer is the partner referrer the session belongs to (null when
-- unreferred), joined from int_screener_referrer on the session key. It is a
-- session-constant attribute, so it adds no rows: the step card can group or
-- filter on it and still count each session once.

select
    furthest.session_key,
    furthest.furthest_step_rank,
    furthest.event_date,
    furthest.event_date_parsed,
    furthest.screener_state,
    furthest.is_cesn,
    referrer.screener_referrer,

    current_timestamp() as updated_at

from {{ ref('int_screener_furthest_step') }} as furthest
{{ join_screener_referrer('session', 'furthest.session_key') }}
