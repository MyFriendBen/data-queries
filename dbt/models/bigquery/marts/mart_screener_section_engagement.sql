{{
  config(
    materialized='table'
  )
}}

-- Household-member and income-source section engagement, at SCREENING x section x
-- action grain (one row per screener_uid that took an action, deduped across all
-- days). This grain lets the cards COUNT(DISTINCT screener_uid) for a correct
-- across-window screening count — summing a per-day distinct count would
-- double-count a screening that acted on more than one calendar day. Same pattern
-- as mart_screener_step_facts.
--
-- `section` is 'Household Members' or 'Income Sources' (from event_name); `action`
-- is add / edit / delete (or '(unknown)'). total_actions is the raw event count
-- (additive by design — keep it a SUM in the card); event_date_parsed is the
-- screening's last day taking this action, for windowing.

with engagement as (
    select
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
    where screener_uid is not null
)

select
    screener_uid,
    section,
    action,
    max(screener_state) as screener_state,
    max(event_date_parsed) as event_date_parsed,
    count(*) as total_actions,

    current_timestamp() as updated_at

from engagement
group by screener_uid, section, action
order by section, action
