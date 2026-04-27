{{
  config(
    materialized='view'
  )
}}

-- Session-level summary combining session metadata with page activity and link clicks
-- One row per (user_pseudo_id, ga_session_id); reporting date comes from the session-start row
-- Powers all Google Analytics KPI and chart models

with sessions as (
    select
        event_date,
        user_pseudo_id,
        ga_session_id,
        session_medium,
        session_source,
        session_campaign,
        session_start_datetime,
        event_date_parsed
    from {{ ref('stg_ga_sessions') }}
    where ga_session_id is not null
),

page_activity as (
    -- Summarize page activity per session: state, screener funnel flags, and timestamps
    select
        user_pseudo_id,
        ga_session_id,
        -- Use first non-null state_code seen in session
        max(state_code) as state_code,
        max(case when page_path like '%/step-1%' then 1 else 0 end) as hit_screener_start,
        max(case when page_path like '%/results%' then 1 else 0 end) as hit_screener_results,
        min(case when page_path like '%/step-1%' then event_timestamp end) as first_screener_start_ts,
        min(case when page_path like '%/results%' then event_timestamp end) as first_screener_results_ts
    from {{ ref('int_ga4_page_views') }}
    where ga_session_id is not null
    group by user_pseudo_id, ga_session_id
),

link_click_events as (
    -- Raw outbound click events, not pre-aggregated so we can compare each click
    -- timestamp against first_screener_results_ts after joining with page_activity
    select
        user_pseudo_id,
        ga_session_id,
        event_timestamp as click_ts
    from {{ ref('stg_ga_link_clicks') }}
    where ga_session_id is not null
      and is_outbound = 'true'
),

link_clicks as (
    -- Session-level aggregation: first click timestamp and total count
    select
        user_pseudo_id,
        ga_session_id,
        min(click_ts) as first_outbound_click_ts,
        count(*)      as total_link_clicks
    from link_click_events
    group by user_pseudo_id, ga_session_id
),

post_completion_clicks as (
    -- Sessions where at least one outbound click occurred AFTER /results.
    -- Computed separately because min(click_ts) in link_clicks would return 0
    -- for sessions that have clicks both before and after screener completion.
    select distinct
        lce.user_pseudo_id,
        lce.ga_session_id
    from link_click_events lce
    inner join page_activity pa
        on  lce.user_pseudo_id = pa.user_pseudo_id
        and lce.ga_session_id  = pa.ga_session_id
    where pa.first_screener_results_ts is not null
      and lce.click_ts > pa.first_screener_results_ts
)

select
    s.event_date,
    s.event_date_parsed,
    s.user_pseudo_id,
    s.ga_session_id,

    -- State code from page activity (null if no page views in session)
    coalesce(pa.state_code, 'unknown') as state_code,

    -- Traffic source
    coalesce(s.session_medium, '(none)') as session_medium,
    coalesce(s.session_source, '(direct)') as session_source,
    s.session_campaign,

    -- Session timing
    s.session_start_datetime,

    -- Screener funnel activity
    coalesce(pa.hit_screener_start, 0) as hit_screener_start,
    coalesce(pa.hit_screener_results, 0) as hit_screener_results,

    -- Completion time in seconds (null if session did not complete the screener)
    -- Exclude sessions where gap < 20s to filter out direct /results navigations
    case
        when pa.first_screener_start_ts is not null
            and pa.first_screener_results_ts is not null
            and (pa.first_screener_results_ts - pa.first_screener_start_ts) / 1000000.0 >= 20
        then (pa.first_screener_results_ts - pa.first_screener_start_ts) / 1000000.0
        else null
    end as completion_time_seconds,

    -- Link click activity
    -- has_outbound_click = 1 when ANY outbound click occurred after screener completion;
    -- uses post_completion_clicks CTE to avoid the min(click_ts) bug where an early
    -- pre-completion click would wrongly suppress a later post-completion click
    case when pcc.user_pseudo_id is not null then 1 else 0 end as has_outbound_click,
    lc.first_outbound_click_ts,
    coalesce(lc.total_link_clicks, 0) as total_link_clicks

from sessions s
left join page_activity pa
    on s.user_pseudo_id = pa.user_pseudo_id
    and s.ga_session_id = pa.ga_session_id
left join link_clicks lc
    on  s.user_pseudo_id = lc.user_pseudo_id
    and s.ga_session_id  = lc.ga_session_id
left join post_completion_clicks pcc
    on  s.user_pseudo_id = pcc.user_pseudo_id
    and s.ga_session_id  = pcc.ga_session_id
