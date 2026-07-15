{{
  config(
    materialized='view'
  )
}}

-- Screener share/save events (MFB-1268 app-emitted screener_* events)
-- Covers screener_share, screener_share_popup_shown, screener_results_save
-- No save_action:'error' or share-failure event exists yet — send-failure is
-- not distinguished from send-attempt (see analytics-dbt-notes.md).

select
    -- Event/date info
    event_date,
    event_timestamp,
    parse_date('%Y%m%d', event_date) as event_date_parsed,
    event_name,

    -- User info
    user_pseudo_id,
    user_id,
    -- Batch fields make each raw GA4 event unique. GA4 client batching can
    -- assign the SAME event_timestamp to multiple distinct events; without these,
    -- GROUP BY collapses them and max(case...) mixes their params (data loss).
    event_bundle_sequence_id,
    batch_event_index,

    -- Session info (extracted from event_params)
    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

    -- Screener identifiers (sent directly as params)
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,

    -- screener_share
    max(case when ep.key = 'share_location' then ep.value.string_value end) as share_location,
    max(case when ep.key = 'share_channel' then ep.value.string_value end) as share_channel,
    max(case when ep.key = 'share_provider' then ep.value.string_value end) as share_provider,
    max(case when ep.key = 'share_action' then ep.value.string_value end) as share_action,

    -- screener_results_save
    max(case when ep.key = 'save_channel' then ep.value.string_value end) as save_channel,
    max(case when ep.key = 'save_action' then ep.value.string_value end) as save_action,

    -- Event timestamp
    timestamp_micros(event_timestamp) as event_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name in (
    'screener_share',
    'screener_share_popup_shown',
    'screener_results_save'
)

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
