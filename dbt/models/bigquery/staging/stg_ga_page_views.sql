{{
  config(
    materialized='view'
  )
}}

-- Google Analytics page views staging model
-- Extracts event_params into columns using efficient single UNNEST with conditional aggregation
-- This is a lightweight staging layer - derived fields are added in intermediate models

select
    -- Event information
    event_date,
    event_timestamp,
    event_name,

    -- User information
    user_pseudo_id,
    user_id,

    -- Session information (extracted from event_params)
    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

    -- Page information (extracted from event_params)
    max(case when ep.key = 'page_location' then ep.value.string_value end) as page_location,

    -- Timestamp conversion
    timestamp_micros(event_timestamp) as event_datetime,
    parse_date('%Y%m%d', event_date) as event_date_parsed

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name = 'page_view'

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id