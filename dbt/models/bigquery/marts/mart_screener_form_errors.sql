{{
  config(
    materialized='table'
  )
}}

-- Screener form errors detail - daily grain by state, step, field, and problem.
-- Powers the "which validations trip people up" card on the Form Journey tab.
-- The form-funnel mart (mart_screener_form_funnel) carries error COUNTS at the
-- (date, state, step) grain; this mart adds the field + problem dimensions so the
-- specific failing field and reason are visible per step.
--
-- CONTRACT (FE #2163, per-field events): screener_form_error fires ONCE PER FAILED
-- FIELD, carrying two PII-safe params built on the FE from the field name + zod
-- issue code (never the entered value or localized message):
--   form_field_name  : canonical field path, numeric array indices already stripped
--                      on the FE (members.0.birthYear -> members.birthYear), so one
--                      logical field is one path (no explode/regex needed here).
--   form_error_reason: the friendly rule LABEL (collectFieldErrors + RULE_LABELS in
--                      errorLabels.ts), e.g. "Invalid amount" — display-ready.
-- So total_errors counts field-level error events and screenings_with_error is the
-- distinct screenings that hit this (step, field, problem) combo.
--
-- HUMANIZATION of the FIELD lives HERE (not in the card SQL) so it is defined once,
-- tested, and reusable: form_field_name is a code-y path, mapped below to a friendly
-- label. UNMAPPED paths fall back to the raw path so a NEW field never vanishes — it
-- just shows its raw name until a label is added here (one line). The PROBLEM label
-- is the FE's own (RULE_LABELS), passed through verbatim — dbt does not maintain a
-- parallel code->label map that would drift from the FE.
--
-- Carries the session-level is_cesn flag, like the sibling mart_screener_form_funnel
-- (errors_by_step reads that one). Both are screener_form_error surfaces, so they
-- MUST treat CESN + null-state rows identically: the global cards use the
-- all_screener_global_predicate (NOT is_cesn AND (state IN codes OR state IS NULL))
-- so pre-white-label errors are included and CESN excluded, consistently.

with humanized as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        is_cesn,
        screener_step_name,
        screener_uid,
        -- Canonical field path (indices already stripped on the FE). Guard the odd
        -- null/empty so it groups into one bucket rather than dropping.
        nullif(trim(form_field_name), '') as error_field_path,
        -- Friendly reason label, passed through verbatim; null/empty -> fallback.
        nullif(trim(form_error_reason), '') as error_reason_raw
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_error'
        and screener_step_name is not null
)

select
    event_date,
    event_date_parsed,
    screener_state,
    is_cesn,

    -- Human-readable step label (shared screener_step_label macro — single source
    -- of truth across the Form Journey marts).
    {{ screener_step_label('screener_step_name') }} as screener_step_label,

    -- Friendly field label; unmapped paths fall back to the raw path.
    case
        when error_field_path is null then '(unspecified)'
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

    -- Problem phrase. The FE owns the rule-code -> friendly-label mapping (its
    -- RULE_LABELS in errorLabels.ts) and emits the LABEL directly as
    -- form_error_reason, so dbt passes it through verbatim rather than maintaining
    -- a parallel code->label map that would drift from the FE. Missing reasons
    -- (null) surface as '(no detail captured)'. The FE's own unknown-code fallback
    -- is already the literal 'Invalid'.
    coalesce(error_reason_raw, '(no detail captured)') as error_problem,

    -- one row per field-level error event (the FE now fires one per failed field),
    -- so count(*) is the field-level error total for this (step, field, problem).
    count(*) as total_errors,
    count(distinct screener_uid) as screenings_with_error,

    current_timestamp() as updated_at

from humanized
group by
    event_date, event_date_parsed, screener_state, is_cesn, screener_step_name,
    error_field_label, error_problem
order by event_date desc, screener_state, total_errors desc
