{{
  config(
    materialized='table'
  )
}}

-- Google Analytics traffic medium breakdown - daily grain by state and medium
-- Powers the Traffic Mediums bar chart and table on the Google Analytics dashboard tab
-- Shows sessions by channel (organic, direct, referral, etc.)

select
    event_date,
    event_date_parsed,
    state_code,
    session_medium,
    session_source,

    count(distinct ga_session_id) as total_sessions,
    count(distinct user_pseudo_id) as total_users,

    current_timestamp() as updated_at

from {{ ref('int_ga4_sessions') }}
group by event_date, event_date_parsed, state_code, session_medium, session_source
order by event_date desc, total_sessions desc
