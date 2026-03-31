{{
  config(
    materialized='view'
  )
}}

-- Google Analytics session-level data
-- Extracts session metadata from session_start events including traffic source attribution

select
    -- Event/date info
    event_date,
    event_timestamp,
    parse_date('%Y%m%d', event_date) as event_date_parsed,

    -- User info
    user_pseudo_id,
    user_id,

    -- Session info (extracted from event_params)
    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

    -- Traffic source (utm params or GA4 attribution from session_start)
    max(case when ep.key = 'medium' then ep.value.string_value end) as session_medium,
    max(case when ep.key = 'source' then ep.value.string_value end) as session_source,
    max(case when ep.key = 'campaign' then ep.value.string_value end) as session_campaign,

    -- Session start timestamp
    timestamp_micros(event_timestamp) as session_start_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name = 'session_start'

group by
    event_date,
    event_timestamp,
    user_pseudo_id,
    user_id
