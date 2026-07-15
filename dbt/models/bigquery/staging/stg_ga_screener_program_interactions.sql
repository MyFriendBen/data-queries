{{
  config(
    materialized='view'
  )
}}

-- Screener program interaction events (MFB-1268 app-emitted screener_* events)
-- Covers screener_apply_click, screener_program_more_info,
-- screener_program_visit_website, screener_program_phone_click,
-- screener_program_document_download, screener_required_program_click,
-- screener_eligibility_tags_shown, screener_filter_engaged,
-- screener_results_tab_click
-- Group downstream by program_id, not program_name — program_name is the
-- English display label and can vary in spelling for the same program
-- (see analytics-dbt-notes.md).

select
    -- Event/date info
    event_date,
    event_timestamp,
    parse_date('%Y%m%d', event_date) as event_date_parsed,
    event_name,

    -- User info
    user_pseudo_id,
    user_id,

    -- Session info (extracted from event_params)
    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

    -- Screener identifiers (sent directly as params)
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,

    -- Program identifiers
    -- program_id is sent as a NUMBER by the FE, so it lands in int_value, not
    -- string_value. Coalesce both so it's robust regardless of value type
    -- (verified 2026-07-15: prod events carry program_id in int_value).
    max(case when ep.key = 'program_id'
        then coalesce(cast(ep.value.int_value as string), ep.value.string_value)
    end) as program_id,
    max(case when ep.key = 'program_name' then ep.value.string_value end) as program_name,
    max(case when ep.key = 'url' then ep.value.string_value end) as url,
    max(case when ep.key = 'document_name' then ep.value.string_value end) as document_name,

    -- screener_filter_engaged
    max(case when ep.key = 'filter_type' then ep.value.string_value end) as filter_type,

    -- screener_results_tab_click
    max(case when ep.key = 'tab_name' then ep.value.string_value end) as tab_name,

    -- Event timestamp
    timestamp_micros(event_timestamp) as event_datetime

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name in (
    'screener_apply_click',
    'screener_program_more_info',
    'screener_program_visit_website',
    'screener_program_phone_click',
    'screener_program_document_download',
    'screener_required_program_click',
    'screener_eligibility_tags_shown',
    'screener_filter_engaged',
    'screener_results_tab_click'
)

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id
