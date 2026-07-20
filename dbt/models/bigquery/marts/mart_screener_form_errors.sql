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
-- HUMANIZATION lives HERE (not in the dashboard card SQL) so it is defined once,
-- tested, and reusable: the raw message reads as code and array indices explode
-- one logical field into many rows. Two derived columns are produced —
--   error_field_label : the field path with numeric array indices stripped
--                       (incomeStreams.0.income -> incomeStreams.income) then
--                       mapped to a friendly label. UNMAPPED paths fall back to
--                       the stripped path so a NEW field never vanishes — it just
--                       shows its raw name until a label is added here (one line).
--   error_problem     : the zod rule normalized to a short phrase (Required /
--                       Invalid format / Too long / Too short); anything else ->
--                       'Invalid'. The rule set is small and closed.
-- Grouping on these consolidates counts across array indices. The raw
-- form_error_message is dropped from the grain (kept nowhere) since the label
-- pair fully replaces it for reporting; add it back only if a debugging card
-- needs the exact string.
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
),

humanized as (
    select
        *,
        -- field path before the first ': ', numeric array indices removed
        case when form_error_message = '(unspecified)' then null
            else regexp_replace(split(form_error_message, ': ')[safe_offset(0)], r'\.[0-9]+', '')
        end as error_field_path,
        -- reason after the first ': ', lowercased for matching
        case when form_error_message = '(unspecified)' then null
            else lower(trim(substr(form_error_message, instr(form_error_message, ': ') + 2)))
        end as error_reason_raw
    from errors
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

    -- Friendly field label; unmapped paths fall back to the raw stripped path.
    case
        when form_error_message = '(unspecified)' then '(unspecified)'
        when error_field_path = 'householdSize' then 'Household size'
        when error_field_path = 'zipcode' then 'Zip code'
        when error_field_path = 'county' then 'County'
        when error_field_path = 'incomeStreams.income' then 'Income amount'
        when error_field_path = 'incomeStreams.incomeFrequency' then 'Income frequency'
        when error_field_path like 'incomeStreams.%' then 'Income'
        when error_field_path = 'healthInsurance' then 'Health insurance'
        when error_field_path = 'members.birthMonth' then 'Member birth month'
        when error_field_path = 'members.birthYear' then 'Member birth year'
        when error_field_path = 'members.relationship' then 'Member relationship'
        when error_field_path like 'members.%' then 'Household member'
        when error_field_path = 'contactInfo.firstName' then 'First name'
        when error_field_path = 'contactInfo.lastName' then 'Last name'
        when error_field_path = 'contactInfo.email' then 'Email'
        when error_field_path = 'contactInfo.cell' then 'Phone number'
        when error_field_path = 'contactInfo.tcpa' then 'Consent to contact'
        when error_field_path like 'contactInfo.%' then 'Contact info'
        when error_field_path = 'referralSource' then 'Referral source'
        when error_field_path = 'otherReferrer' then 'Other referral source'
        when error_field_path like 'studentEligibility%' then 'Student eligibility'
        else coalesce(error_field_path, '(unspecified)')
    end as error_field_label,

    -- Normalized problem phrase; anything unrecognized -> 'Invalid'.
    case
        when form_error_message = '(unspecified)' then '(no detail captured)'
        when error_reason_raw like 'required%' then 'Required'
        when error_reason_raw like '%invalid format%' or error_reason_raw like '%invalid%' then 'Invalid format'
        when error_reason_raw like '%too long%' then 'Too long'
        when error_reason_raw like '%too short%' then 'Too short'
        else 'Invalid'
    end as error_problem,

    count(*) as total_errors,
    count(distinct screener_uid) as screenings_with_error,
    sum(form_error_count) as total_error_fields,

    current_timestamp() as updated_at

from humanized
group by
    event_date, event_date_parsed, screener_state, is_cesn, screener_step_name,
    error_field_label, error_problem
order by event_date desc, screener_state, total_errors desc
