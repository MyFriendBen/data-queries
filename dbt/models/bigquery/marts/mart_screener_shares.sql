{{
  config(
    materialized='table'
  )
}}

-- Screener share funnel - daily grain by state, share location, channel, and
-- action
-- Powers the Sharing & Outbound dashboard tab's share funnel.
-- screener_share_popup_shown is an impression event (ref-guarded per mount, so
-- it does not re-fire on re-render) and is reported separately from
-- screener_share since it carries no channel/action breakdown.

with shares as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        share_location,
        share_channel,
        share_provider,
        share_action
    from {{ ref('stg_ga_screener_shares') }}
    where event_name = 'screener_share'
)

select
    event_date,
    event_date_parsed,
    screener_state,
    share_location,
    share_channel,
    share_provider,
    share_action,

    count(*) as total_shares,
    count(distinct screener_uid) as screenings_with_share,

    current_timestamp() as updated_at

from shares
group by
    event_date,
    event_date_parsed,
    screener_state,
    share_location,
    share_channel,
    share_provider,
    share_action
order by event_date desc, screener_state, total_shares desc
