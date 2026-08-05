{{
  config(
    materialized='table'
  )
}}

-- Impact-calculator errors, broken out by type (Story 2: number of errors thrown,
-- and which). Daily grain, one row per (date, error type, validation field). The
-- friendly label is mapped here from the machine error_type the FE sends, matching
-- how mart_screener_form_errors maps a code to a display name.
--   API failures: address_not_supported | invalid_response | error
--   validation:   a failed submit; error_field is the first failed field and
--                 error_reason its rule label (PII-safe — rule only, never a value),
--                 so the designer can see WHICH field trips people up.

with errors as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        coalesce(error_type, '(unspecified)') as error_type,
        case error_type
            when 'address_not_supported' then 'Address not supported'
            when 'invalid_response' then 'Invalid response from calculator'
            when 'validation' then 'Form validation'
            else 'Other error'
        end as error_label,
        -- only populated for validation errors
        field as error_field,
        error_reason
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name = 'heat_pump_calculator_error'
)

select
    event_date,
    event_date_parsed,
    screener_state,
    error_type,
    error_label,
    error_field,
    error_reason,

    count(*) as total_errors,
    count(distinct screener_uid) as users,
    count(distinct session_key) as sessions,

    current_timestamp() as updated_at

from errors
group by event_date, event_date_parsed, screener_state, error_type, error_label, error_field, error_reason
order by event_date desc, total_errors desc
