{{
  config(
    materialized='table'
  )
}}

-- Google Analytics KPI summary - daily grain by state
-- Powers the 4 scalar KPI cards and conversion funnel chart on the Google Analytics dashboard tab:
--   - Total Visitors (total_sessions)
--   - Started Screener % (pct_started_screener)
--   - Completed to Click Rate / D-C ratio (completed_to_click_rate_pct)
--   - Completion Time / median seconds from /step-1 to /results (median_completion_time_seconds)
--   - Conversion funnel steps A→B→C→D

select
    event_date,
    event_date_parsed,
    state_code,

    -- Total Visitors (A): all tracked sessions
    count(distinct ga_session_id) as total_sessions,
    count(distinct user_pseudo_id) as total_users,

    -- Started Screener (B): sessions that hit /step-1
    count(distinct case when hit_screener_start = 1 then ga_session_id end) as sessions_started_screener,

    -- Completed Screener (C): sessions that hit /results
    count(distinct case when hit_screener_results = 1 then ga_session_id end) as sessions_completed_screener,

    -- Clicked Link (D): sessions that completed AND clicked an outbound link
    count(distinct case when hit_screener_results = 1 and has_outbound_click = 1 then ga_session_id end) as sessions_clicked_after_completion,

    -- Started Screener %: B / A × 100
    round(
        count(distinct case when hit_screener_start = 1 then ga_session_id end) * 100.0
        / nullif(count(distinct ga_session_id), 0),
        2
    ) as pct_started_screener,

    -- Completed to Click Rate (D/C ratio): D / C × 100
    round(
        count(distinct case when hit_screener_results = 1 and has_outbound_click = 1 then ga_session_id end) * 100.0
        / nullif(count(distinct case when hit_screener_results = 1 then ga_session_id end), 0),
        2
    ) as completed_to_click_rate_pct,

    -- Average completion time (seconds) for sessions that completed the screener
    round(avg(completion_time_seconds), 1) as avg_completion_time_seconds,

    -- Median completion time using BigQuery approximate quantiles
    round(
        approx_quantiles(completion_time_seconds, 100 ignore nulls)[offset(50)],
        1
    ) as median_completion_time_seconds,

    current_timestamp() as updated_at

from {{ ref('int_ga4_sessions') }}
group by event_date, event_date_parsed, state_code
order by event_date desc, state_code
