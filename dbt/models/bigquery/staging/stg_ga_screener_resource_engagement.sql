{{
  config(
    materialized='view'
  )
}}

-- Screener results-page resource + tab engagement (MFB-1268 app-emitted events)
-- Covers:
--   screener_results_tab_click        — which results tab was opened
--                                        (long_term_benefits vs additional_resources)
--   screener_additional_resource_click — a resource under "Additional Resources"
--                                        was clicked (resource_name is the real
--                                        resource label, e.g. "Hunger Free Colorado")
-- screener_state / screener_uid arrive directly as event params.
-- NOTE (see analytics-dbt-notes.md / MFB-1306): resource clicks today are
-- website clicks only — the phone tel: link on resource cards is not yet
-- tracked, and there is no website-vs-phone `contact_method` split. Treat resource
-- click counts as "website clicks" until MFB-1306 adds the contact_method param.

select
    -- Event/date info
    event_date,
    event_timestamp,
    parse_date('%Y%m%d', event_date) as event_date_parsed,
    event_name,

    -- User info
    user_pseudo_id,
    user_id,

    -- Session info
    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

    -- Screener identifiers (sent directly as params)
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,

    -- Tab click detail (screener_results_tab_click)
    max(case when ep.key = 'tab_name' then ep.value.string_value end) as tab_name,

    -- Resource click detail (screener_additional_resource_click)
    max(case when ep.key = 'resource_name' then ep.value.string_value end) as resource_name,
    max(case when ep.key = 'url' then ep.value.string_value end) as url,

    -- Event timestamp
    timestamp_micros(event_timestamp) as event_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name in (
    'screener_results_tab_click',
    'screener_additional_resource_click'
)

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id
