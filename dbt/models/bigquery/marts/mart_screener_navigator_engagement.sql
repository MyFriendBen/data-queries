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
--   screener_navigator_engaged (a click) — contact_method is 'website'|'email'|'phone'.
--     Fires INSTEAD of the generic program website/phone events for navigator links
--     (so it isn't double-counted in mart_screener_program_interactions).
--   screener_navigator_shown (FE #2163 impression) — the shown denominator; carried
--     as a synthetic contact_method = '__shown__' row (exploded per navigator in
--     staging). Distinct so SUM/pivot never mixes it with real contact clicks.
-- Grouped by program_id + navigator_id (the stable keys); one arbitrary
-- program_name / navigator_name carried through per key as the display label.

with navigator_events as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        program_id,
        program_name,
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
)

select
    event_date,
    event_date_parsed,
    screener_state,
    program_id,
    navigator_id,

    -- Arbitrary display labels per id (see note above on spelling drift)
    max(program_name) as program_name,
    max(navigator_name) as navigator_name,

    contact_method,

    count(*) as total_engagements,
    count(distinct screener_uid) as screenings_with_engagement,

    current_timestamp() as updated_at

from navigator_events
group by event_date, event_date_parsed, screener_state, program_id, navigator_id, contact_method
order by event_date desc, screener_state, total_engagements desc
