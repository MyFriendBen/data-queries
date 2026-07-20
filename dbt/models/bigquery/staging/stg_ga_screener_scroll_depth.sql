{{
  config(
    materialized='view'
  )
}}

-- Screener results-page scroll depth (app-emitted screener_results_scroll_depth).
-- Fires only on the two browsable results tabs (form steps force scrolling, so
-- they're excluded), once per depth threshold (25/50/75/100) per tab per
-- screening. tab_name is 'long_term_benefits' or 'additional_resources'.
-- screener_state / screener_uid arrive directly as event params.

select
    -- Event/date info
    event_date,
    event_timestamp,
    parse_date('%Y%m%d', event_date) as event_date_parsed,
    event_name,

    -- User info
    user_pseudo_id,
    user_id,
    -- Batch fields make each raw GA4 event unique (GA4 client batching can reuse
    -- event_timestamp across distinct events).
    event_bundle_sequence_id,
    batch_event_index,

    -- Session info
    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

    -- Screener identifiers
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,

    -- Scroll detail. depth is sent as a NUMBER (int_value); coalesce for safety.
    max(case when ep.key = 'depth'
        then coalesce(ep.value.int_value, safe_cast(ep.value.string_value as int64))
    end) as depth,
    max(case when ep.key = 'tab_name' then ep.value.string_value end) as tab_name,

    -- Event timestamp
    timestamp_micros(event_timestamp) as event_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name = 'screener_results_scroll_depth'

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
