{{
  config(
    materialized='view'
  )
}}

-- Google Analytics outbound link click events
-- Captures click events tracked by GA4 enhanced measurement
-- GA4 auto-tracks outbound links when enhanced measurement is enabled

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

    -- Link details (extracted from event_params)
    max(case when ep.key = 'link_url' then ep.value.string_value end) as link_url,
    max(case when ep.key = 'link_domain' then ep.value.string_value end) as link_domain,
    max(case when ep.key = 'outbound' then ep.value.string_value end) as is_outbound,

    -- Click timestamp
    timestamp_micros(event_timestamp) as click_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name = 'click'

group by
    event_date,
    event_timestamp,
    user_pseudo_id,
    user_id
