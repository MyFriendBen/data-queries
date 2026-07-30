{{
  config(
    materialized='table'
  )
}}

-- Screening (screener_uid) grain — ONE ROW PER SCREENER, carrying its funnel-stage
-- flags and how many GA sessions it spanned. This is the screening-grain companion
-- to the session-grain step funnel (mart_screener_form_funnel / furthest_step).
-- Cards aggregate it:
--   * Screener Conversion Funnel: COUNTIF over the stage flags (created ->
--     saw_results -> viewed_details -> applied), a true distinct-screener subset
--     chain (every stage is the same screener_uid).
--   * Sessions per Screener: distribution of distinct_sessions across screeners
--     (how fragmented a screening is across visits).
--
-- Stage flags:
--   saw_results   = fired screener_results_loaded (clean load; matches the
--                   Results-Page "Results Viewed" card so the two agree)
--   viewed_details= clicked "More info" on any program (screener_program_more_info)
--   applied       = clicked Apply on any program (screener_apply_click)
-- created is implicit — the screener exists (one row here).
--
-- A screener is attributed to the state + date of its FIRST event, so it lands in
-- one (date, state) bucket regardless of how many sessions/days it spans. is_cesn
-- is logical_or across the screener's events. distinct_sessions counts the distinct
-- ga_session_ids the screener_uid appeared under.

with events as (
    select
        (select value.string_value from unnest(event_params) where key = 'screener_uid'  limit 1) as screener_uid,
        (select value.string_value from unnest(event_params) where key = 'screener_state' limit 1) as screener_state,
        (select value.int_value    from unnest(event_params) where key = 'ga_session_id'  limit 1) as ga_session_id,
        parse_date('%Y%m%d', event_date) as event_date_parsed,
        event_timestamp,
        event_name
    from {{ source('google_analytics', 'events_*') }}
    -- No date bound here: every screener mart reads the full events_* history and
    -- the dashboard cards apply the single analytics epoch. Bounding this mart on a
    -- different date desynced first-event dates from the other marts (a screener
    -- that first loaded results pre-epoch but revisited in-window landed in
    -- different date buckets across marts). The card-level epoch is the one floor.
    where (select value.string_value from unnest(event_params) where key = 'screener_uid' limit 1) is not null
),

per_screener as (
    select
        screener_uid,
        -- Attribute the screener to the earliest event whose state is a known
        -- lowercase code — a screening's early events can carry the legacy
        -- display-name format (e.g. "Colorado") that the dashboard state IN-list
        -- doesn't recognize, which would drop the screener from state-filtered
        -- cards even though its later events use the clean code ("co").
        array_agg(
            if(screener_state in ('co','nc','tx','wa','il','ma','cesn'), screener_state, null)
            ignore nulls order by event_timestamp limit 1
        )[safe_offset(0)] as screener_state,
        min(event_date_parsed) as event_date_parsed,
        logical_or(lower(screener_state) = 'cesn') as is_cesn,
        count(distinct ga_session_id) as distinct_sessions,
        -- Clean results load only (matches the Results-Page "Results Viewed"
        -- card, mart_screener_results_revisits). Error / none-eligible outcomes
        -- are deliberately excluded so the two cards agree.
        logical_or(event_name = 'screener_results_loaded') as reached_results,
        logical_or(event_name = 'screener_program_more_info') as clicked_more_info,
        logical_or(event_name = 'screener_apply_click') as clicked_apply
    from events
    group by screener_uid
)

-- Cumulative funnel flags: a later stage implies every earlier one, so the
-- dashboard COUNTIFs form a true monotonic subset chain (created >= saw_results
-- >= viewed_details >= applied) even if a screener fired a later event without a
-- recorded earlier one.
select
    screener_uid,
    screener_state,
    event_date_parsed,
    is_cesn,
    distinct_sessions,
    reached_results or clicked_more_info or clicked_apply as saw_results,
    clicked_more_info or clicked_apply                    as viewed_details,
    clicked_apply                                         as applied,
    current_timestamp() as updated_at
from per_screener
