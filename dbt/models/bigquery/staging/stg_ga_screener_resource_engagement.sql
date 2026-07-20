{{
  config(
    materialized='view'
  )
}}

-- Screener results-page resource + tab engagement (app-emitted events)
-- Covers:
--   screener_results_tab_click              — which results tab was opened
--                                              (long_term_benefits vs additional_resources)
--   screener_additional_resource_more_info  — a resource card was expanded
--                                              ("More Info"); first step of the
--                                              resource engagement funnel
--   screener_additional_resource_click      — a resource contact link was clicked;
--                                              contact_method distinguishes website
--                                              vs phone (both now tracked)
-- screener_state / screener_uid arrive directly as event params. resource_name is
-- the real resource label (e.g. "Hunger Free Colorado").

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

    -- Session info
    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

    -- Screener identifiers (sent directly as params)
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,

    -- Tab click detail (screener_results_tab_click)
    max(case when ep.key = 'tab_name' then ep.value.string_value end) as tab_name,

    -- Resource detail (screener_additional_resource_more_info / _click)
    max(case when ep.key = 'resource_name' then ep.value.string_value end) as resource_name,
    max(case when ep.key = 'url' then ep.value.string_value end) as url,
    -- contact_method: 'website' | 'phone' on screener_additional_resource_click
    max(case when ep.key = 'contact_method' then ep.value.string_value end) as contact_method,

    -- Event timestamp
    timestamp_micros(event_timestamp) as event_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name in (
    'screener_results_tab_click',
    'screener_additional_resource_more_info',
    'screener_additional_resource_click'
)

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
