{{
  config(
    materialized='view'
  )
}}

-- Google Analytics page views staging model
-- This pulls page view data from Google Analytics 4 BigQuery export

select
    -- Event information
    event_date,
    event_timestamp,
    event_name,
    
    -- Page information  
    event_params.value.string_value as page_location,
    regexp_extract(event_params.value.string_value, r'[^/]+://[^/]+(/[^?]*)') as page_path,
    regexp_extract(event_params.value.string_value, r'[^/]+://([^/]+)') as page_hostname,
    
    -- User information
    user_pseudo_id,
    user_id,
    
    -- Timestamp conversion
    timestamp_micros(event_timestamp) as event_datetime,
    parse_date('%Y%m%d', event_date) as event_date_parsed

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as event_params

where 
    -- Filter for page_view events only
    event_name = 'page_view'
    -- Filter for page_location parameter
    and event_params.key = 'page_location'