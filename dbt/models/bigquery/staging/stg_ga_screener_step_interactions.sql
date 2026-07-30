{{
  config(
    materialized='view'
  )
}}

-- Screener step interaction events (app-emitted screener_* events)
-- Covers screener_household_member, screener_income_source,
-- screener_has_benefits_load_error, screener_language_changed,
-- screener_confirmation_edit, screener_confirmation_proceed
-- Note: screener_income_source add/delete counts are NOT expected to reconcile
-- 1:1 — the form auto-appends an empty income row for 16+ members that is not
-- tracked as an add.

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
    max(case when ep.key = 'screener_step_name' then ep.value.string_value end) as screener_step_name,
    max(case when ep.key = 'screener_step_number' then ep.value.int_value end) as screener_step_number,

    -- Interaction action (household_member, income_source)
    max(case when ep.key = 'action' then ep.value.string_value end) as action,

    -- screener_language_changed
    max(case when ep.key = 'language_name' then ep.value.string_value end) as language_name,

    -- screener_confirmation_edit
    max(case when ep.key = 'section' then ep.value.string_value end) as section,

    -- Event timestamp
    timestamp_micros(event_timestamp) as event_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name in (
    'screener_household_member',
    'screener_income_source',
    'screener_has_benefits_load_error',
    'screener_language_changed',
    'screener_confirmation_edit',
    'screener_confirmation_proceed'
)

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
