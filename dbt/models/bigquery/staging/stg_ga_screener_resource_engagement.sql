{{
  config(
    materialized='view'
  )
}}

-- Screener results-page resource + tab engagement (app-emitted events)
-- Covers:
--   screener_results_tab_click              — which results tab was opened
--                                              (long_term_benefits vs additional_resources)
--   screener_additional_resource_more_info  — a resource card was expanded
--                                              ("More Info"); first step of the
--                                              resource engagement funnel
--   screener_additional_resource_click      — a resource contact link was clicked;
--                                              contact_method distinguishes website
--                                              vs phone (both now tracked)
--   view_item_list (results_resources)     — additional-resource impressions: one
--                                              event per results-tab load with a
--                                              native items[] array. The "shown"
--                                              denominator for a resource
--                                              shown->clicked rate. Unnested below,
--                                              one row per resource with event_name
--                                              'screener_resource_shown'.
-- screener_state / screener_uid arrive directly as event params. resource_name is
-- the real resource label (e.g. "Hunger Free Colorado").

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

        -- Session info
        max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,

        -- Screener identifiers (sent directly as params)
        max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
        max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,

        -- Tab click detail (screener_results_tab_click)
        max(case when ep.key = 'tab_name' then ep.value.string_value end) as tab_name,

        -- Resource detail (screener_additional_resource_more_info / _click)
        max(case when ep.key = 'resource_name' then ep.value.string_value end) as resource_name,
        max(case when ep.key = 'url' then ep.value.string_value end) as url,
        -- contact_method: 'website' | 'phone' on screener_additional_resource_click
        max(case when ep.key = 'contact_method' then ep.value.string_value end) as contact_method,

        -- Event timestamp
        timestamp_micros(event_timestamp) as event_datetime

    from {{ source('google_analytics', 'events_*') }}
    cross join unnest(event_params) as ep

    where event_name in (
        'screener_results_tab_click',
        'screener_additional_resource_more_info',
        'screener_additional_resource_click'
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

-- Additional-resource impressions from the GA4 view_item_list results_resources
-- list: one event per results-tab load carrying a native items[] RECORD array,
-- unnested to one row per resource and re-emitted as 'screener_resource_shown' so
-- the mart reads it as a normal per-resource event. Resources are keyed by name
-- (no id); item_name is both key and label.
resources_shown as (
    select
        r.event_date,
        r.event_timestamp,
        parse_date('%Y%m%d', r.event_date) as event_date_parsed,
        'screener_resource_shown' as event_name,
        r.user_pseudo_id,
        r.user_id,
        r.event_bundle_sequence_id,
        r.batch_event_index + off as batch_event_index,
        (select value.int_value    from unnest(r.event_params) where key = 'ga_session_id')  as ga_session_id,
        (select value.string_value from unnest(r.event_params) where key = 'screener_state')  as screener_state,
        (select value.string_value from unnest(r.event_params) where key = 'screener_uid')    as screener_uid,
        cast(null as string) as tab_name,
        item.item_name as resource_name,
        cast(null as string) as url,
        cast(null as string) as contact_method,
        timestamp_micros(r.event_timestamp) as event_datetime
    from {{ source('google_analytics', 'events_*') }} r,
    unnest(r.items) as item with offset as off
    where r.event_name = 'view_item_list'
        and item.item_list_name = 'results_resources'
),

combined as (
    select * from scalar_events
    union all
    select * from resources_shown
)

select
    *,
    -- Session-level CESN flag so the global cards can exclude CESN (nothing on the
    -- global dashboard should count CESN). These events carry screener_state, so the
    -- cesn signal is the state itself; windowed by session for null-state robustness.
    -- Mirrors the derivation in stg_ga_screener_results_outcomes / _form_funnel.
    logical_or(lower(screener_state) = 'cesn')
        over (partition by user_pseudo_id, ga_session_id) as is_cesn
from combined
