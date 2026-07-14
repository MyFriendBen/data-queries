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

select
    coalesce(s.event_date, p.event_date) as event_date,
    coalesce(s.event_date_parsed, p.event_date_parsed) as event_date_parsed,
    coalesce(s.screener_state, p.screener_state) as screener_state,
    s.save_channel,
    s.save_action,

    coalesce(s.total_saves, 0) as total_saves,
    coalesce(s.screenings_with_save, 0) as screenings_with_save,
    coalesce(p.total_popup_impressions, 0) as total_popup_impressions,
    coalesce(p.screenings_shown_popup, 0) as screenings_shown_popup,

    current_timestamp() as updated_at

from save_summary s
full outer join popup_summary p
    on s.event_date = p.event_date
    and s.screener_state = p.screener_state
order by event_date desc, screener_state
