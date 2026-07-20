{{
  config(
    materialized='view'
  )
}}

-- Screener program interaction events (app-emitted screener_* events)
-- Covers screener_apply_click, screener_program_more_info,
-- screener_program_visit_website, screener_program_phone_click,
-- screener_program_document_download, screener_required_program_click,
-- screener_eligibility_tags_shown, screener_filter_engaged,
-- screener_results_tab_click, screener_program_shown, screener_navigator_engaged
-- Group downstream by program_id, not program_name — program_name is the
-- English display label and can vary in spelling for the same program.

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

    -- Program identifiers
    -- program_id is sent as a NUMBER by the FE, so it lands in int_value, not
    -- string_value. Coalesce both so it's robust regardless of value type.
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

    -- screener_navigator_engaged — program-page "Get Help Applying" navigators.
    -- navigator_id is sent as a NUMBER by the FE (int_value); coalesce both types.
    max(case when ep.key = 'navigator_id'
        then coalesce(cast(ep.value.int_value as string), ep.value.string_value)
    end) as navigator_id,
    max(case when ep.key = 'navigator_name' then ep.value.string_value end) as navigator_name,
    max(case when ep.key = 'contact_method' then ep.value.string_value end) as contact_method,

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
    'screener_results_tab_click',
    'screener_program_shown',
    'screener_navigator_engaged'
)

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
