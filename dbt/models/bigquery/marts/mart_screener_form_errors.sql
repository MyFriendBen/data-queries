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
--   error_problem     : the FE-emitted rule LABEL, passed through verbatim. The FE
--                       (collectFieldErrors + RULE_LABELS in errorLabels.ts) owns the
--                       code->label mapping and sends the label, so dbt does not
--                       re-derive it. Missing/malformed reasons fall back to
--                       '(no detail captured)'; the FE's own unknown-code fallback is
--                       already the literal 'Invalid'.
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
        coalesce(nullif(trim(form_error_message), ''), '(unspecified)') as form_error_message
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_error'
        and screener_step_name is not null
),

-- One screener_form_error lists EVERY field that failed that submit, comma-joined
-- ("field1: code1, field2: code2"). Explode to one row per "field: code" pair so
-- each failing field is counted and labeled independently (parsing only the first
-- pair would drop fields 2+ and mislabel field 1, whose reason would swallow the
-- trailing ", field2: code2"). Each pair contributes 1 to the field count.
pairs as (
    select
        e.* except (form_error_message),
        e.form_error_message,
        trim(pair) as pair
    from errors e,
    unnest(
        if(e.form_error_message = '(unspecified)',
           ['(unspecified)'],
           split(e.form_error_message, ', '))
    ) as pair
),

humanized as (
    select
        * except (pair),
        -- field path before the first ': ', numeric array indices removed
        case when pair = '(unspecified)' then null
            else regexp_replace(split(pair, ': ')[safe_offset(0)], r'\.[0-9]+', '')
        end as error_field_path,
        -- reason after the first ': '. The FE (collectFieldErrors + RULE_LABELS)
        -- already maps each rule code to a friendly, PII-safe LABEL before emitting
        -- (e.g. "income: Invalid amount"), so this is a display-ready string — we
        -- pass it through rather than re-deriving from a code. A pair with no ': ',
        -- or an empty reason after it ("field: "), is a malformed fragment (FE
        -- message-delimiter/truncation bug — see FE gaps ticket); null it so it
        -- rolls into the '(no detail captured)' fallback instead of a blank/garbage
        -- reason.
        case when pair = '(unspecified)' then null
            when instr(pair, ': ') = 0 then null
            else nullif(trim(substr(pair, instr(pair, ': ') + 2)), '')
        end as error_reason_raw
    from pairs
)

select
    event_date,
    event_date_parsed,
    screener_state,
    is_cesn,

    -- Human-readable step label (shared screener_step_label macro — single source
    -- of truth across the Form Journey marts).
    {{ screener_step_label('screener_step_name') }} as screener_step_label,

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

    -- Problem phrase. The FE owns the rule-code -> friendly-label mapping (its
    -- RULE_LABELS in errorLabels.ts) and emits the LABEL directly in
    -- form_error_message, so dbt passes it through verbatim rather than maintaining
    -- a parallel code->label map that would drift from the FE. Missing/fragment
    -- reasons (null error_reason_raw) surface as '(no detail captured)'. The FE's
    -- own unknown-code fallback is already the literal 'Invalid'.
    coalesce(error_reason_raw, '(no detail captured)') as error_problem,

    -- one exploded row per (attempt x failed field), so count(*) is the field-level
    -- error total for this (step, field, problem) — no longer over-attributed to
    -- field #1 as when the whole message was parsed as one row.
    count(*) as total_errors,
    count(distinct screener_uid) as screenings_with_error,

    current_timestamp() as updated_at

from humanized
group by
    event_date, event_date_parsed, screener_state, is_cesn, screener_step_name,
    error_field_label, error_problem
order by event_date desc, screener_state, total_errors desc
