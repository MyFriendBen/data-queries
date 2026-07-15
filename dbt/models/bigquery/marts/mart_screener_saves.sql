{{
  config(
    materialized='table'
  )
}}

-- Screener results-save funnel and share-popup impressions - daily grain by
-- state
-- Powers the Sharing & Outbound dashboard tab's save funnel, tracked
-- separately from mart_screener_shares since screener_results_save is a
-- distinct user flow (save-for-later) from screener_share (active sharing).
-- screener_share_popup_shown is an impression event (ref-guarded per mount) —
-- dedupe by screener_uid for "distinct screenings shown the share popup"
-- (see analytics-dbt-notes.md).
-- No save_action:'error' event exists yet, so send-failure is not
-- distinguished from send-attempt in save_action values.

with saves as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        save_channel,
        save_action
    from {{ ref('stg_ga_screener_shares') }}
    where event_name = 'screener_results_save'
),

popup_shown as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid
    from {{ ref('stg_ga_screener_shares') }}
    where event_name = 'screener_share_popup_shown'
),

save_summary as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        save_channel,
        save_action,
        count(*) as total_saves,
        count(distinct screener_uid) as screenings_with_save
    from saves
    group by event_date, event_date_parsed, screener_state, save_channel, save_action
),

popup_summary as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        count(*) as total_popup_impressions,
        count(distinct screener_uid) as screenings_shown_popup
    from popup_shown
    group by event_date, event_date_parsed, screener_state
)

-- Save rows and popup-impression rows live at DIFFERENT grains: saves are per
-- (date, state, channel, action); popup impressions are per (date, state). A
-- join would repeat the single popup value across every channel/action save row,
-- and the card's SUM(screenings_shown_popup) would then inflate by the number of
-- channel/action combos that day. Instead we UNION them as disjoint rows —
-- popup rows carry a synthetic save_action = '__popup_shown__' (null channel),
-- mirroring the __form_start__ synthetic-row pattern in mart_screener_form_funnel.
-- Each metric column is non-zero on only ONE row type, so SUM() over any filter
-- counts each exactly once. The card reads Shown Popup from the popup rows and
-- Saved from the save rows.
select
    event_date,
    event_date_parsed,
    screener_state,
    save_channel,
    save_action,

    total_saves,
    screenings_with_save,
    0 as total_popup_impressions,
    0 as screenings_shown_popup,

    current_timestamp() as updated_at

from save_summary

union all

select
    event_date,
    event_date_parsed,
    screener_state,
    cast(null as string) as save_channel,
    '__popup_shown__' as save_action,

    0 as total_saves,
    0 as screenings_with_save,
    total_popup_impressions,
    screenings_shown_popup,

    current_timestamp() as updated_at

from popup_summary
order by event_date desc, screener_state
