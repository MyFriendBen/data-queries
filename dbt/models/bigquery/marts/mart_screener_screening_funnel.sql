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
-- Stage flags (cumulative — a later stage implies every earlier one):
--   saw_results   = fired screener_results_loaded (clean load) OR any later stage.
--                   The base signal is the same event the Results-Page "Results
--                   Viewed" card counts, so the two are CLOSE but not guaranteed
--                   equal: this flag is cumulative (a screener that clicked
--                   More-info/Apply with no recorded results_loaded still counts
--                   here), and date attribution differs (see below), so under a
--                   date filter a screener can bucket differently in the two marts.
--   viewed_details= clicked "More info" on any program (screener_program_more_info)
--   applied       = clicked Apply on any program (screener_apply_click)
-- created is implicit — the screener exists (one row here).
--
-- A screener is attributed to the state + date of its FIRST event, so it lands in
-- one (date, state) bucket regardless of how many sessions/days it spans.
-- is_cesn is logical_or(state='cesn') over the screener's events — NOT
-- session-windowed like the staging models. Those window it because CESN's
-- top-of-funnel events carry a null state; but this mart is uid-grain and a uid
-- only exists post-disclaimer (after the white label is set), so every event here
-- carries the resolved state and per-event derivation is equivalent (verified: 0
-- of 66 CESN uids carry a mixed/non-cesn state).
-- distinct_sessions counts the distinct ga_session_ids the screener_uid appeared under.

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
        -- Time-to-completion inputs: earliest event overall (screening start) and
        -- earliest clean results load, both at screener_uid grain so a screening
        -- that spans multiple sessions/days still measures from its true start.
        min(event_timestamp) as first_event_ts,
        min(case when event_name = 'screener_results_loaded' then event_timestamp end) as first_results_ts,
        -- Base "reached results" = clean results load only, the same event the
        -- Results-Page "Results Viewed" card counts (error / none-eligible
        -- outcomes excluded). Note saw_results below is the CUMULATIVE flag, so it
        -- can exceed Results Viewed for a screener that engaged programs without a
        -- recorded results_loaded.
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
--
-- completion_time_seconds: first tracked event for the screener_uid (its earliest
-- moment on the ladder, post-disclaimer) to its first clean screener_results_loaded.
-- Null when the screener never reached a clean results load (reached_results
-- false) — cumulative saw_results can still be true via more_info/apply with no
-- recorded results_loaded, which correctly excludes those from a completion-time
-- calculation since there's no results timestamp to measure to.
select
    screener_uid,
    screener_state,
    event_date_parsed,
    is_cesn,
    distinct_sessions,
    reached_results or clicked_more_info or clicked_apply as saw_results,
    clicked_more_info or clicked_apply                    as viewed_details,
    clicked_apply                                         as applied,
    case
        when reached_results and first_results_ts > first_event_ts
        then (first_results_ts - first_event_ts) / 1000000.0
    end as completion_time_seconds,
    current_timestamp() as updated_at
from per_screener
