{{
  config(
    materialized='table'
  )
}}

-- Screener conversion funnel analysis
-- Tracks how many users/sessions started vs completed the screener

with session_page_views as (
  select
    event_date,
    event_timestamp,
    user_pseudo_id,
    ga_session_id,
    page_path,
    state_code
  from {{ ref('int_ga4_page_views') }}
),

session_funnel_events as (
  select
    event_date,
    user_pseudo_id,
    ga_session_id,
    state_code,
    -- Funnel step identification
    case 
      when page_path like '%/step-1%' then 'started'
      when page_path like '%/results%' then 'completed'
      else null
    end as funnel_step,
    event_timestamp
  
  from session_page_views
  where (page_path like '%/step-1%' or page_path like '%/results%')
    and ga_session_id is not null
),

session_summary as (
  select
    event_date,
    user_pseudo_id,
    ga_session_id,
    state_code,
    -- First event timestamps (to avoid double counting revisits)
    min(case when funnel_step = 'started' then event_timestamp end) as first_started_timestamp,
    min(case when funnel_step = 'completed' then event_timestamp end) as first_completed_timestamp,
    -- Session-level funnel tracking (based on first events only)
    max(case when funnel_step = 'started' then 1 else 0 end) as session_started,
    max(case when funnel_step = 'completed' then 1 else 0 end) as session_completed
  
  from session_funnel_events
  group by event_date, user_pseudo_id, ga_session_id, state_code
),

daily_conversion_metrics as (
  select
    event_date,
    coalesce(state_code, 'unknown') as state_code,
    
    -- Session-level metrics
    count(*) as total_sessions_with_funnel_activity,
    sum(session_started) as sessions_started,
    sum(session_completed) as sessions_completed,
    sum(case
      when session_completed = 1
        and first_completed_timestamp is not null
        and (first_started_timestamp is null or first_completed_timestamp > first_started_timestamp)
      then 1
      else 0
    end) as sessions_converted,

    -- User-level metrics
    count(distinct user_pseudo_id) as total_users_with_funnel_activity,
    count(distinct case when session_started = 1 then user_pseudo_id end) as users_started,
    count(distinct case when session_completed = 1 then user_pseudo_id end) as users_completed,
    count(distinct case
      when session_completed = 1
        and first_completed_timestamp is not null
        and (first_started_timestamp is null or first_completed_timestamp > first_started_timestamp)
      then user_pseudo_id
    end) as users_converted,
    
    -- Conversion rates
    round(sum(session_completed) / nullif(sum(session_started), 0) * 100, 2) as session_conversion_rate_pct,
    round(count(distinct case when session_completed = 1 then user_pseudo_id end) / 
          nullif(count(distinct case when session_started = 1 then user_pseudo_id end), 0) * 100, 2) as user_conversion_rate_pct
  
  from session_summary
  group by event_date, state_code
)

select
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
  current_timestamp() as updated_at

from daily_conversion_metrics
order by event_date desc, state_code