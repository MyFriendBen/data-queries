{{
  config(
    materialized='table'
  )
}}

-- Screener form errors detail - daily grain by state, step, and error message.
-- Powers the "which validations trip people up" card on the Form Journey tab.
-- The form-funnel mart (mart_screener_form_funnel) carries error COUNTS at the
-- (date, state, step) grain; this mart adds the form_error_message dimension so
-- the specific failing field:rule pairs are visible per step.
--
-- form_error_message is a PII-safe "field: rule" list (e.g. "zipcode: Required")
-- built on the FE from the field name + zod issue code — never the entered value
-- or localized message. One screener_form_error event fires per failed submit
-- attempt and its form_error_message lists every field that failed that attempt,
-- so total_errors here counts attempts, and screenings_with_error is the distinct
-- screenings that hit this step+message combo.
--
-- Carries the session-level is_cesn flag, like the sibling mart_screener_form_funnel
-- (errors_by_step reads that one). Both are screener_form_error surfaces, so they
-- MUST treat CESN + null-state rows identically: the global cards use the
-- all_screener_global_predicate (NOT is_cesn AND (state IN codes OR state IS NULL))
-- so pre-white-label errors are included and CESN excluded, consistently.

with errors as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        is_cesn,
        screener_step_name,
        screener_uid,
        -- Guard against the odd null/empty message so it groups into one bucket
        -- rather than silently dropping (a message should always be present now).
        coalesce(nullif(trim(form_error_message), ''), '(unspecified)') as form_error_message,
        form_error_count
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_error'
        and screener_step_name is not null
)

select
    event_date,
    event_date_parsed,
    screener_state,
    is_cesn,

    -- Human-readable step label, mirroring mart_screener_form_funnel's mapping so
    -- cards read consistently across the Form Journey tab.
    case screener_step_name
        when 'language' then 'Language'
        when 'disclaimer' then 'Disclaimer'
        when 'select-state' then 'Select State'
        when 'zip-code' then 'Zip Code'
        when 'household-size' then 'Household Size'
        when 'household-basics' then 'Household Basics'
        when 'household-members' then 'Household Members'
        when 'member-details' then 'Member Details'
        when 'expenses' then 'Expenses'
        when 'assets' then 'Assets'
        when 'current-benefits' then 'Current Benefits'
        when 'additional-resources' then 'Additional Resources'
        when 'referral-source' then 'Referral Source'
        when 'sign-up' then 'Sign Up'
        when 'confirm-information' then 'Confirm Information'
        else screener_step_name
    end as screener_step_label,

    form_error_message,

    count(*) as total_errors,
    count(distinct screener_uid) as screenings_with_error,
    sum(form_error_count) as total_error_fields,

    current_timestamp() as updated_at

from errors
group by event_date, event_date_parsed, screener_state, is_cesn, screener_step_name, form_error_message
order by event_date desc, screener_state, total_errors desc
