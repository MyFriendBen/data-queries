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
--
-- Output shape: three DISJOINT row types (see the union block below) — raw
-- per-(channel,action) save counts, a synthetic '__saved__' row for distinct
-- COMPLETED savers (save_action = 'send' only), and a synthetic '__popup_shown__'
-- row for popup impressions — so each
-- metric sums exactly once with no fan-out. Distinct metrics (screenings_with_save,
-- screenings_shown_popup) dedupe on screener_uid, which is valid here because both
-- save and popup events fire post-step-3 (uid exists).
-- There is no save_action:'error' event, so send-failure is not distinguished
-- from send-attempt in save_action values.

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

-- Per (channel, action): raw save COUNT only. total_saves is a plain count(*),
-- so it sums correctly across channel/action rows. screenings_with_save (a
-- DISTINCT-screening metric) is NOT computed here — a uid that saved via two
-- channels/actions would be counted once per combo, and the card's
-- SUM(screenings_with_save) would inflate the "Saved" funnel stage. It lives on
-- its own disjoint row below.
save_summary as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        save_channel,
        save_action,
        count(*) as total_saves
    from saves
    group by event_date, event_date_parsed, screener_state, save_channel, save_action
),

-- Distinct COMPLETED savers per (date, state) — the "Saved" funnel stage. Only
-- save_action = 'send' counts as a completed save; open/close/back are modal
-- interaction, not a completed save (they'd overstate the bottom funnel stage).
-- One row per grain, so SUM() counts each screening once regardless of how many
-- channels it sent through.
saves_distinct_summary as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        count(distinct screener_uid) as screenings_with_save
    from saves
    where save_action = 'send'
    group by event_date, event_date_parsed, screener_state
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

-- Three DISJOINT row types unioned at a common shape (mirrors the __form_start__
-- synthetic-row pattern). Each metric column is non-zero on exactly ONE row type,
-- so SUM() over any filter counts each exactly once — no fan-out:
--   1. channel/action rows  → total_saves (raw count, summable per channel)
--   2. '__saved__' rows      → screenings_with_save (distinct completed savers,
--        save_action='send', per date/state)
--   3. '__popup_shown__' rows → popup impressions/distinct (per date/state)
-- The card reads Saved from row type 2, Shown Popup from row type 3, and
-- saves-by-channel from row type 1 (which excludes the synthetic rows via its
-- save_channel IS NOT NULL filter).
select
    event_date,
    event_date_parsed,
    screener_state,
    save_channel,
    save_action,

    total_saves,
    0 as screenings_with_save,
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
    '__saved__' as save_action,

    0 as total_saves,
    screenings_with_save,
    0 as total_popup_impressions,
    0 as screenings_shown_popup,

    current_timestamp() as updated_at

from saves_distinct_summary

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
