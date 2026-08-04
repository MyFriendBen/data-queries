{{
  config(
    materialized='table'
  )
}}

-- Impact-calculator errors, broken out by type (Story 2: number of errors thrown,
-- and which). Daily grain, one row per (date, error type). The friendly label is
-- mapped here from the machine error_type the FE sends, matching how
-- mart_screener_form_errors maps error_field_path to a display name. error_message
-- (present on the generic 'error' case) is the human failure text the FE captured;
-- it's carried through for drill-down, not aggregated.

with errors as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        coalesce(error_type, '(unspecified)') as error_type,
        case error_type
            when 'address_not_supported' then 'Address not supported'
            when 'invalid_response' then 'Invalid response from calculator'
            else 'Other error'
        end as error_label
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name = 'heat_pump_calculator_error'
)

select
    event_date,
    event_date_parsed,
    screener_state,
    error_type,
    error_label,

    count(*) as total_errors,
    count(distinct screener_uid) as users,

    current_timestamp() as updated_at

from errors
group by event_date, event_date_parsed, screener_state, error_type, error_label
order by event_date desc, total_errors desc
