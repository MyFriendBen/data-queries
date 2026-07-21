{{
  config(
    materialized='table'
  )
}}

-- Household-member and income-source section engagement - daily grain by state,
-- section, and action. Powers the "how do people edit their household / income"
-- cards on the Form Journey tab.
--
-- `section` is 'Household Members' or 'Income Sources' (from event_name). `action`
-- is add / edit / delete. total_actions counts events; screenings is the distinct
-- screenings that took the action (uid grain — these fire post step 3).

with engagement as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        case event_name
            when 'screener_household_member' then 'Household Members'
            when 'screener_income_source' then 'Income Sources'
            else event_name
        end as section,
        coalesce(action, '(unknown)') as action
    from {{ ref('stg_ga_screener_section_engagement') }}
)

select
    event_date,
    event_date_parsed,
    screener_state,
    section,
    action,

    count(*) as total_actions,
    count(distinct screener_uid) as screenings,

    current_timestamp() as updated_at

from engagement
group by event_date, event_date_parsed, screener_state, section, action
order by event_date desc, screener_state, section, total_actions desc
