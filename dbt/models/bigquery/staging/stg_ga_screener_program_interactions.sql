{{
  config(
    materialized='view'
  )
}}

-- Screener program interaction events (app-emitted screener_* events)
-- Covers screener_apply_click, screener_program_more_info,
-- screener_program_visit_website, screener_program_phone_click,
-- screener_program_document_download, screener_required_program_click,
-- screener_filter_engaged, screener_results_tab_click,
-- screener_navigator_engaged, and results-page impressions via the GA4
-- view_item_list items[] array (unnested below — MFB-1419).
-- Group downstream by program_id, not program_name — program_name is the
-- English display label and can vary in spelling for the same program.
--
-- RESULTS-PAGE IMPRESSIONS ("shown" events) — via GA4 view_item_list (MFB-1419):
-- Every results-page "shown" list (programs, navigators, documents) is emitted as
-- a single GA4 ecommerce `view_item_list` event carrying a native `items` array,
-- differentiated by items[].item_list_name. This REPLACES the earlier per-item
-- burst (screener_program_shown, dropped ~60% by GA4's same-tick batch cap) AND
-- the stringified-JSON-array events (screener_programs_shown / _navigators_shown /
-- _program_documents_shown, truncated at GA4's 100-char param cap → unparseable).
-- The native items array is a repeated RECORD in the BigQuery export, so it is
-- immune to both failure modes: one event (no burst) and each field is its own
-- typed column (no 100-char array truncation). See MFB-1419 for the full diagnosis.
--
-- We UNNEST(items) and re-emit the SAME event_name each mart already consumes
-- (screener_program_shown / screener_navigator_shown /
-- screener_program_document_shown) so the marts are unchanged:
--   item_list_name = 'results_programs'   -> screener_program_shown
--   item_list_name = 'results_navigators' -> screener_navigator_shown  (program ctx via item_category)
--   item_list_name = 'results_documents'  -> screener_program_document_shown (program ctx via item_category)
--
-- NOT YET LIVE: as of MFB-1419 the FE does not emit view_item_list yet, so
-- impressions_shown returns 0 rows (the SELECTs below are correct but dormant).
-- Day-of-activation verification queries are in the MFB-1419 dbt section.

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

-- Results-page impressions via GA4 view_item_list (MFB-1419). ONE event per list
-- load carrying a native items[] RECORD array; we UNNEST it to one row per shown
-- item and re-emit the event_name each mart already consumes. item_list_name
-- routes each item to the right shown-type. Event-level screener_state/uid/session
-- are pulled up once; per-item fields come off the unnested struct.
--
-- Field mapping (confirm against real emission when MFB-1419 ships — see the
-- day-of verification queries in that ticket before relying on these rows):
--   item.item_id            -> program_id (programs) / navigator_id (navigators)
--   item.item_name          -> program_name / navigator_name / document_name
--   item.item_category      -> parent program_id for navigators/documents (page context)
--   item.item_list_name     -> which list ('results_programs' | 'results_navigators'
--                              | 'results_documents')
-- program_id/navigator_id land as strings in item_id; documents are keyed by name.
impressions_raw as (
    select
        event_date,
        event_timestamp,
        parse_date('%Y%m%d', event_date) as event_date_parsed,
        user_pseudo_id,
        user_id,
        event_bundle_sequence_id,
        batch_event_index,
        (select value.int_value    from unnest(event_params) where key = 'ga_session_id')  as ga_session_id,
        (select value.string_value from unnest(event_params) where key = 'screener_state')  as screener_state,
        (select value.string_value from unnest(event_params) where key = 'screener_uid')    as screener_uid,
        timestamp_micros(event_timestamp) as event_datetime,
        items
    from {{ source('google_analytics', 'events_*') }}
    where event_name = 'view_item_list'
),

impressions_shown as (
    select
        r.event_date,
        r.event_timestamp,
        r.event_date_parsed,
        case item.item_list_name
            when 'results_programs'   then 'screener_program_shown'
            when 'results_navigators' then 'screener_navigator_shown'
            when 'results_documents'  then 'screener_program_document_shown'
        end as event_name,
        r.user_pseudo_id,
        r.user_id,
        r.event_bundle_sequence_id,
        -- one item per row already; offset keeps rows within an event distinct on
        -- (bundle_seq, batch_event_index) for the batch-dedup contract downstream.
        r.batch_event_index + off as batch_event_index,
        r.ga_session_id,
        r.screener_state,
        r.screener_uid,
        -- programs: the item IS the program. navigators/documents: the parent
        -- program is carried in item_category (page context).
        case item.item_list_name
            when 'results_programs' then item.item_id
            else item.item_category
        end as program_id,
        case item.item_list_name
            when 'results_programs' then item.item_name
            else cast(null as string)
        end as program_name,
        cast(null as string) as url,
        case when item.item_list_name = 'results_documents' then item.item_name end as document_name,
        cast(null as string) as filter_type,
        cast(null as string) as tab_name,
        case when item.item_list_name = 'results_navigators' then item.item_id end as navigator_id,
        case when item.item_list_name = 'results_navigators' then item.item_name end as navigator_name,
        cast(null as string) as contact_method,
        r.event_datetime
    from impressions_raw r,
    unnest(r.items) as item with offset as off
    where item.item_list_name in ('results_programs', 'results_navigators', 'results_documents')
)

select * from scalar_events
union all
select * from impressions_shown
