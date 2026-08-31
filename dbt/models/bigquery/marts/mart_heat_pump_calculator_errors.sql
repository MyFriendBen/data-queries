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
--
-- SEGMENTATION (Story 4): income band, region memberships and the Xcel flag come
-- from the household bridge and sit in the grain, so a dashboard filter rescopes
-- this model. Screenings with no bridge match land in 'Unknown' rather than
-- vanishing from the totals.

with attributes as (
    select
        screener_uid,
        income_band,
        income_band_sort,
        is_below_200_fpl,
        region_memberships,
        is_xcel_customer
    from {{ ref('stg_screener_household_attributes') }}
),

errors as (
    select
        e.event_date,
        e.event_date_parsed,
        e.screener_state,
        e.screener_uid,
        coalesce(a.income_band, 'Unknown') as income_band,
        coalesce(a.income_band_sort, 4) as income_band_sort,
        coalesce(a.is_below_200_fpl, false) as is_below_200_fpl,
        coalesce(a.region_memberships, ',Unknown,') as region_memberships,
        coalesce(a.is_xcel_customer, false) as is_xcel_customer,
        to_json_string(struct(e.user_pseudo_id, e.ga_session_id)) as session_key,
        coalesce(e.error_type, '(unspecified)') as error_type,
        case e.error_type
            when 'address_not_supported' then 'Address not supported'
            when 'invalid_response' then 'Invalid response from calculator'
            when 'validation' then 'Form validation'
            else 'Other error'
        end as error_label,
        -- only populated for validation errors
        e.field as error_field,
        e.error_reason
    from {{ ref('stg_ga_heat_pump_journey') }} e
    left join attributes a on e.screener_uid = a.screener_uid
    where e.event_name = 'heat_pump_calculator_error'
)

select
    event_date,
    event_date_parsed,
    -- derived from a grouped column, so it needs no group-by entry of its own
    date_trunc(event_date_parsed, week(monday)) as event_week,
    screener_state,
    error_type,
    error_label,
    error_field,
    error_reason,

    income_band,
    income_band_sort,
    is_below_200_fpl,
    region_memberships,
    is_xcel_customer,

    count(*) as total_errors,
    count(distinct screener_uid) as users,
    count(distinct session_key) as sessions,

    current_timestamp() as updated_at

from errors
group by event_date, event_date_parsed, screener_state, error_type, error_label, error_field, error_reason,
    income_band, income_band_sort, is_below_200_fpl, region_memberships, is_xcel_customer
order by event_date desc, total_errors desc
