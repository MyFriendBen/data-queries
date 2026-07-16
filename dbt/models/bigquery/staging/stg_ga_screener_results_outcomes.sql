{{
  config(
    materialized='view'
  )
}}

-- Screener results outcome events (app-emitted screener_* events)
-- Covers screener_results_loaded, screener_results_none_eligible,
-- screener_results_error, screener_results_error_recovery
-- program_count on screener_results_loaded is the count returned by the results
-- API (eligible programs in MFB); confirm whether partners want eligible vs total.
--
-- is_cesn is a SESSION-LEVEL flag (see stg_ga_screener_form_funnel for the full
-- rationale): results events fire deep in the flow so they normally carry
-- screener_state = 'cesn', but flagging the whole session keeps the mart robust
-- if any results event lands with a null state, and matches the funnel mart's
-- exclusion mechanism so global cards filter CESN identically everywhere.

with per_event as (
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

        -- screener_results_loaded
        max(case when ep.key = 'program_count' then ep.value.int_value end) as program_count,
        -- total_estimated_value's GA4 value type is value-dependent: it lands in
        -- int_value for whole-dollar amounts and double_value only when fractional,
        -- so read both and coalesce to avoid nulling out whole-dollar values.
        max(case when ep.key = 'total_estimated_value'
            then coalesce(ep.value.double_value, cast(ep.value.int_value as float64))
        end) as total_estimated_value,

        -- screener_results_error
        max(case when ep.key = 'reference_id' then ep.value.string_value end) as reference_id,

        -- Event timestamp
        timestamp_micros(event_timestamp) as event_datetime

    from {{ source('google_analytics', 'events_*') }}
    cross join unnest(event_params) as ep

    where event_name in (
        'screener_results_loaded',
        'screener_results_none_eligible',
        'screener_results_error',
        'screener_results_error_recovery'
    )

    group by
        event_date,
        event_timestamp,
        event_name,
        user_pseudo_id,
        user_id,
        event_bundle_sequence_id,
        batch_event_index
)

select
    *,
    -- Session-level CESN flag (results events carry screener_state, so the cesn
    -- signal is the state itself; windowed by session for null-state robustness).
    logical_or(lower(screener_state) = 'cesn')
        over (partition by user_pseudo_id, ga_session_id) as is_cesn

from per_event
