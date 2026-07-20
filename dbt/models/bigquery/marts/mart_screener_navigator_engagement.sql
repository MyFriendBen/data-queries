{{
  config(
    materialized='table'
  )
}}

-- Screener navigator engagement - daily grain by state, program, navigator, and
-- contact method.
-- Powers the Results dashboard tab: which "Get Help Applying" navigators users
-- engage, on which program, via website / email / phone.
-- screener_navigator_engaged fires INSTEAD of the generic program
-- website/phone events for navigator links (so it isn't double-counted in
-- mart_screener_program_interactions) and adds the previously-untracked email.
-- Grouped by program_id + navigator_id (the stable keys); one arbitrary
-- program_name / navigator_name carried through per key as the display label.

with navigator_engaged as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        program_id,
        program_name,
        navigator_id,
        navigator_name,
        contact_method
    from {{ ref('stg_ga_screener_program_interactions') }}
    where event_name = 'screener_navigator_engaged'
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

from navigator_engaged
group by event_date, event_date_parsed, screener_state, program_id, navigator_id, contact_method
order by event_date desc, screener_state, total_engagements desc
