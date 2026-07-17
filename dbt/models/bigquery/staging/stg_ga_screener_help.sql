{{
  config(
    materialized='view'
  )
}}

-- Screener help interactions (app-emitted events):
--   screener_help_click     — an inline "?" field tooltip was opened; help_topic
--                             identifies which tooltip (e.g. income-frequency).
--                             Carries step context (screener_step_name/number).
--   screener_get_help_click — the results-page "More Help / 211" CTA; `location`
--                             is where it was clicked (e.g. results). Kept
--                             separate so it doesn't pollute the per-step
--                             confusion metric.
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
    event_bundle_sequence_id,
    batch_event_index,

    -- Session info
    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

    -- Screener identifiers
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,

    -- screener_help_click
    max(case when ep.key = 'help_topic' then ep.value.string_value end) as help_topic,
    max(case when ep.key = 'screener_step_name' then ep.value.string_value end) as screener_step_name,
    max(case when ep.key = 'screener_step_number' then ep.value.int_value end) as screener_step_number,

    -- screener_get_help_click
    max(case when ep.key = 'location' then ep.value.string_value end) as location,

    -- Event timestamp
    timestamp_micros(event_timestamp) as event_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name in (
    'screener_help_click',
    'screener_get_help_click'
)

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
