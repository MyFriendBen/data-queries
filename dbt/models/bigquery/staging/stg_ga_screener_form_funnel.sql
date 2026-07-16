{{
  config(
    materialized='view'
  )
}}

-- Screener form funnel events (app-emitted screener_* events)
-- Covers screener_form_start, screener_form_step, screener_form_complete,
-- screener_form_error, screener_form_back
-- screener_state / screener_uid are sent directly as event params by the app,
-- so no page_location regex is needed to derive state (unlike the legacy GA4 events).
-- Do NOT filter out null screener_uid here — top-of-funnel steps (language,
-- select-state) fire before a screening uuid exists, so uid is null on them.
--
-- is_cesn is a SESSION-LEVEL flag: true for every row of a session that is CESN
-- anywhere in its lifetime. It cannot be derived per-row, because CESN's
-- entry path (energysavings.colorado.gov → /cesn/landing-page redirect) and the
-- bare-domain pre-state pages fire generic, null-state events (language,
-- select-state, zip-code) that carry no cesn marker on their own. Marking the
-- whole session lets the global dashboard exclude ALL of a CESN session's rows —
-- including those unmarked null-state ones — via a single flag instead of each
-- card re-deriving the cesn-% logic. A session is CESN if any of its events has
-- screener_state = 'cesn' OR a cesn-* / cesn-landing step name.

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

        -- Step details
        max(case when ep.key = 'screener_step_name' then ep.value.string_value end) as screener_step_name,
        max(case when ep.key = 'screener_step_number' then ep.value.int_value end) as screener_step_number,
        max(case when ep.key = 'step_action' then ep.value.string_value end) as step_action,

        -- Error details (screener_form_error only)
        max(case when ep.key = 'form_error_message' then ep.value.string_value end) as form_error_message,
        max(case when ep.key = 'form_error_count' then ep.value.int_value end) as form_error_count,

        -- Event timestamp
        timestamp_micros(event_timestamp) as event_datetime

    from {{ source('google_analytics', 'events_*') }}
    cross join unnest(event_params) as ep

    where event_name in (
        'screener_form_start',
        'screener_form_step',
        'screener_form_complete',
        'screener_form_error',
        'screener_form_back'
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
    -- Session-level CESN flag: true for EVERY row of a session that is CESN
    -- anywhere. Partitioned by the session key so an unmarked null-state event
    -- (e.g. the pre-state language page of a CESN session) inherits the flag.
    logical_or(
        lower(screener_state) = 'cesn'
        or lower(screener_step_name) like 'cesn-%'
    ) over (partition by user_pseudo_id, ga_session_id) as is_cesn

from per_event
