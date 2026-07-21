{{
  config(
    materialized='table'
  )
}}

-- Confirmation-page edits by section — which review-page sections people go back
-- to change before submitting (a friction/uncertainty signal at the end of the
-- flow). Daily grain by state + section. `section` is a QuestionName key from the
-- FE (e.g. householdData); mapped to a friendly label here. total_edits counts
-- edit clicks; screenings is distinct screenings that edited the section.

with edits as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        section
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name = 'screener_confirmation_edit'
        and section is not null
)

select
    event_date,
    event_date_parsed,
    screener_state,

    case section
        when 'zipcode' then 'Zip Code'
        when 'householdSize' then 'Household Size'
        when 'householdData' then 'Household & Member Details'
        when 'hasExpenses' then 'Expenses'
        when 'householdAssets' then 'Assets'
        when 'hasBenefits' then 'Current Benefits'
        when 'acuteHHConditions' then 'Additional Resources'
        when 'referralSource' then 'Referral Source'
        when 'signUpInfo' then 'Sign Up'
        else section
    end as section_label,

    count(*) as total_edits,
    count(distinct screener_uid) as screenings,

    current_timestamp() as updated_at

from edits
group by event_date, event_date_parsed, screener_state, section_label
order by event_date desc, screener_state, total_edits desc
