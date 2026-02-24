{{
  config(
    materialized='table'
  )
}}

-- Screener conversion funnel analysis
-- Tracks how many users/sessions started vs completed the screener

WITH session_page_views AS (
    SELECT
        event_date,
        event_timestamp,
        user_pseudo_id,
        ga_session_id,
        page_path,
        state_code
    FROM {{ ref('int_ga4_page_views') }}
),

session_funnel_events AS (
    SELECT
        event_date,
        user_pseudo_id,
        ga_session_id,
        state_code,
        -- Funnel step identification
        event_timestamp,
        CASE
            WHEN page_path LIKE '%/step-1%' THEN 'started'
            WHEN page_path LIKE '%/results%' THEN 'completed'
        END AS funnel_step

    FROM session_page_views
    WHERE
        (page_path LIKE '%/step-1%' OR page_path LIKE '%/results%')
        AND ga_session_id IS NOT null
),

session_summary AS (
    SELECT
        event_date,
        user_pseudo_id,
        ga_session_id,
        state_code,
        -- First event timestamps (to avoid double counting revisits)
        min(CASE WHEN funnel_step = 'started' THEN event_timestamp END) AS first_started_timestamp,
        min(CASE WHEN funnel_step = 'completed' THEN event_timestamp END) AS first_completed_timestamp,
        -- Session-level funnel tracking (based on first events only)
        max(CASE WHEN funnel_step = 'started' THEN 1 ELSE 0 END) AS session_started,
        max(CASE WHEN funnel_step = 'completed' THEN 1 ELSE 0 END) AS session_completed

    FROM session_funnel_events
    GROUP BY event_date, user_pseudo_id, ga_session_id, state_code
),

daily_conversion_metrics AS (
    SELECT
        event_date,
        coalesce(state_code, 'unknown') AS state_code,

        -- Session-level metrics
        count(*) AS total_sessions_with_funnel_activity,
        sum(session_started) AS sessions_started,
        sum(session_completed) AS sessions_completed,
        sum(CASE
            WHEN
                session_completed = 1
                AND first_completed_timestamp IS NOT null
                AND (first_started_timestamp IS null OR first_completed_timestamp > first_started_timestamp)
                THEN 1
            ELSE 0
        END) AS sessions_converted,

        -- User-level metrics
        count(DISTINCT user_pseudo_id) AS total_users_with_funnel_activity,
        count(DISTINCT CASE WHEN session_started = 1 THEN user_pseudo_id END) AS users_started,
        count(DISTINCT CASE WHEN session_completed = 1 THEN user_pseudo_id END) AS users_completed,
        count(DISTINCT CASE
            WHEN
                session_completed = 1
                AND first_completed_timestamp IS NOT null
                AND (first_started_timestamp IS null OR first_completed_timestamp > first_started_timestamp)
                THEN user_pseudo_id
        END) AS users_converted,

        -- Conversion rates
        round(sum(session_completed) / nullif(sum(session_started), 0) * 100, 2) AS session_conversion_rate_pct,
        round(
            count(DISTINCT CASE WHEN session_completed = 1 THEN user_pseudo_id END)
            / nullif(count(DISTINCT CASE WHEN session_started = 1 THEN user_pseudo_id END), 0) * 100, 2
        ) AS user_conversion_rate_pct

    FROM session_summary
    GROUP BY event_date, state_code
)

SELECT
    event_date,
    state_code,

    -- Session metrics
    sessions_started,
    sessions_completed,
    sessions_converted,
    session_conversion_rate_pct,

    -- User metrics
    users_started,
    users_completed,
    users_converted,
    user_conversion_rate_pct,

    -- Additional context
    total_sessions_with_funnel_activity,
    total_users_with_funnel_activity,

    -- Data freshness
    current_timestamp() AS updated_at

FROM daily_conversion_metrics
ORDER BY event_date DESC, state_code ASC
