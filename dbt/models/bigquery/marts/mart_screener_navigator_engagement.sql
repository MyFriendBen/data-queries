{{
  config(
    materialized='table'
  )
}}

-- Screener navigator engagement - daily grain by state, program, navigator, and
-- contact method.
-- Powers the Results dashboard tab: for each "Get Help Applying" navigator, how
-- many screenings were SHOWN it vs engaged it via website / email / phone (a
-- grouped-bar funnel like Additional Resource Engagement).
-- Two event sources share the grain via contact_method:
--   screener_navigator_engaged (a click) — contact_method is 'website'|'email'|'phone';
--     the navigator link's own event, not the generic program website/phone events.
--   screener_navigator_shown (impression) — the shown denominator, carried as a
--     synthetic contact_method = '__shown__' row so SUM/pivot never mixes it with
--     real contact clicks.
-- Grouped by program_id + navigator_id (the stable keys); navigator_name is the
-- per-navigator display label, program_name is resolved from program_id.

with navigator_events as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        program_id,
        navigator_id,
        navigator_name,
        -- real contact_method for engaged clicks; a distinct sentinel for impressions
        case when event_name = 'screener_navigator_shown' then '__shown__'
             else contact_method end as contact_method
    from {{ ref('stg_ga_screener_program_interactions') }}
    where event_name in ('screener_navigator_engaged', 'screener_navigator_shown')
        -- program_id + navigator_id are the stable keys; guard the grain
        and program_id is not null
        and navigator_id is not null
),

aggregated as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        program_id,
        navigator_id,
        max(navigator_name) as navigator_name,
        contact_method,
        count(*) as total_engagements,
        count(distinct screener_uid) as screenings_with_engagement
    from navigator_events
    group by event_date, event_date_parsed, screener_state, program_id, navigator_id, contact_method
)

select
    a.event_date,
    a.event_date_parsed,
    a.screener_state,
    a.program_id,
    a.navigator_id,
    -- fall back to the id if a name was never captured for this program
    coalesce(pn.program_name, a.program_id) as program_name,
    a.navigator_name,
    a.contact_method,
    a.total_engagements,
    a.screenings_with_engagement,
    current_timestamp() as updated_at

from aggregated a
left join {{ ref('int_screener_program_names') }} pn
    on a.program_id = pn.program_id
order by a.event_date desc, a.screener_state, a.total_engagements desc
