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
-- screener_results_tab_click, screener_navigator_engaged, and the batched
-- impression event screener_programs_shown (exploded below).
-- Group downstream by program_id, not program_name — program_name is the
-- English display label and can vary in spelling for the same program.
--
-- PROGRAM IMPRESSIONS (FE #2163): the per-program screener_program_shown event
-- was replaced by ONE batched screener_programs_shown event carrying parallel
-- JSON-string arrays program_ids / program_names (GTM JSON.stringify's them so
-- commas inside names survive). GA4 dropped >half of the old per-program burst
-- (see FE gap #5). We EXPLODE the batched event back into one row per program —
-- re-emitting event_name = 'screener_program_shown' so every downstream consumer
-- (mart_screener_program_interactions' `when 'screener_program_shown' then 'shown'`)
-- is unchanged. Keyed off program_ids (short, never truncated); program_names is
-- carried positionally as the display label (may be truncated at GA4's 100-char
-- cap for very long lists — acceptable since it's display-only and the id drives
-- every join/group).
--
-- NAVIGATOR IMPRESSIONS (FE #2163): screener_navigators_shown fires once per
-- program page carrying navigator_ids / navigator_names JSON arrays plus the
-- program_id/program_name context. Exploded per navigator and re-emitted as
-- 'screener_navigator_shown' — the shown denominator for a navigator
-- shown->engaged rate (mart_screener_navigator_engagement).

with scalar_events as (
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
),

-- One row per raw screener_programs_shown event, with its params (incl. the two
-- JSON-string arrays) pulled up, before exploding.
programs_shown_raw as (
    select
        event_date,
        event_timestamp,
        parse_date('%Y%m%d', event_date) as event_date_parsed,
        user_pseudo_id,
        user_id,
        event_bundle_sequence_id,
        batch_event_index,
        max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,
        max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
        max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,
        -- GTM JSON.stringify's the arrays into a single string param each.
        max(case when ep.key = 'program_ids' then ep.value.string_value end) as program_ids_json,
        max(case when ep.key = 'program_names' then ep.value.string_value end) as program_names_json,
        timestamp_micros(event_timestamp) as event_datetime
    from {{ source('google_analytics', 'events_*') }}
    cross join unnest(event_params) as ep
    where event_name = 'screener_programs_shown'
    group by
        event_date, event_timestamp, user_pseudo_id, user_id,
        event_bundle_sequence_id, batch_event_index
),

-- Explode to one row per (event, program). WITH OFFSET zips the two parallel
-- arrays positionally: element i of program_ids pairs with element i of
-- program_names. Re-emit event_name = 'screener_program_shown' so downstream is
-- unchanged. Guard a null/empty ids array (JSON_EXTRACT_STRING_ARRAY -> null).
programs_shown as (
    select
        r.event_date,
        r.event_timestamp,
        r.event_date_parsed,
        'screener_program_shown' as event_name,
        r.user_pseudo_id,
        r.user_id,
        r.event_bundle_sequence_id,
        -- keep each exploded row distinct within the event: offset the batch index
        -- by the array position so (bundle_seq, batch_event_index) stays unique.
        r.batch_event_index + off as batch_event_index,
        r.ga_session_id,
        r.screener_state,
        r.screener_uid,
        pid as program_id,
        -- positional display label; null-safe if names is shorter/truncated
        json_extract_string_array(r.program_names_json)[safe_offset(off)] as program_name,
        cast(null as string) as url,
        cast(null as string) as document_name,
        cast(null as string) as filter_type,
        cast(null as string) as tab_name,
        cast(null as string) as navigator_id,
        cast(null as string) as navigator_name,
        cast(null as string) as contact_method,
        r.event_datetime
    from programs_shown_raw r,
    unnest(json_extract_string_array(r.program_ids_json)) as pid with offset as off
),

-- Batched screener_navigators_shown: one raw event per program page carrying
-- navigator_ids / navigator_names JSON arrays plus scalar program_id/program_name.
navigators_shown_raw as (
    select
        event_date,
        event_timestamp,
        parse_date('%Y%m%d', event_date) as event_date_parsed,
        user_pseudo_id,
        user_id,
        event_bundle_sequence_id,
        batch_event_index,
        max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,
        max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
        max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,
        max(case when ep.key = 'program_id'
            then coalesce(cast(ep.value.int_value as string), ep.value.string_value)
        end) as program_id,
        max(case when ep.key = 'program_name' then ep.value.string_value end) as program_name,
        max(case when ep.key = 'navigator_ids' then ep.value.string_value end) as navigator_ids_json,
        max(case when ep.key = 'navigator_names' then ep.value.string_value end) as navigator_names_json,
        timestamp_micros(event_timestamp) as event_datetime
    from {{ source('google_analytics', 'events_*') }}
    cross join unnest(event_params) as ep
    where event_name = 'screener_navigators_shown'
    group by
        event_date, event_timestamp, user_pseudo_id, user_id,
        event_bundle_sequence_id, batch_event_index
),

-- Explode per navigator; re-emit 'screener_navigator_shown'. navigator_ids is the
-- key (short); navigator_names positional display label. program_id/name are scalar
-- context shared by every navigator on the page.
navigators_shown as (
    select
        r.event_date,
        r.event_timestamp,
        r.event_date_parsed,
        'screener_navigator_shown' as event_name,
        r.user_pseudo_id,
        r.user_id,
        r.event_bundle_sequence_id,
        r.batch_event_index + off as batch_event_index,
        r.ga_session_id,
        r.screener_state,
        r.screener_uid,
        r.program_id,
        r.program_name,
        cast(null as string) as url,
        cast(null as string) as document_name,
        cast(null as string) as filter_type,
        cast(null as string) as tab_name,
        nid as navigator_id,
        json_extract_string_array(r.navigator_names_json)[safe_offset(off)] as navigator_name,
        cast(null as string) as contact_method,
        r.event_datetime
    from navigators_shown_raw r,
    unnest(json_extract_string_array(r.navigator_ids_json)) as nid with offset as off
)

select * from scalar_events
union all
select * from programs_shown
union all
select * from navigators_shown
