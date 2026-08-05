{{
  config(
    materialized='view'
  )
}}

-- Household-member and income-source section engagement (app-emitted).
-- Covers:
--   screener_household_member  — add / edit / delete a household member
--   screener_income_source     — add / delete an income source
-- Both fire on the household-members step with an `action` param
-- (add | edit | delete). event_name distinguishes the two sections downstream.
-- screener_state / screener_uid arrive directly as event params (post step 3, so
-- uid exists). member_index (FE #2163, 0-based) ties an income action to the
-- member-detail page it happened on — the join key for a per-member-page rate.

select
    event_date,
    event_timestamp,
    parse_date('%Y%m%d', event_date) as event_date_parsed,
    event_name,

    user_pseudo_id,
    user_id,
    -- Batch fields keep each raw GA4 event unique under client batching.
    event_bundle_sequence_id,
    batch_event_index,

    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,
    max(case when ep.key = 'action' then ep.value.string_value end) as action,
    max(case when ep.key = 'member_index' then ep.value.int_value end) as member_index,

    timestamp_micros(event_timestamp) as event_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name in ('screener_household_member', 'screener_income_source')

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
