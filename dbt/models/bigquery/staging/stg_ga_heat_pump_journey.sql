{{
  config(
    materialized='view'
  )
}}

-- CESN heat-pump / HVAC-journey events. One row per raw event, params flattened.
-- Downstream marts filter by event_name:
--   heat_pump_journey_learn_more_click — "Learn more" from "Why get a heat pump?"
--   rebate_link_click                  — "Learn how to apply" (rebate_type, rebate_category)
--   heat_pump_cta_click                — internal CTA (cta: calculate_impact | connect_now)
--   heat_pump_calculator_field         — a calculator field was engaged (field:
--                                        household_type | address | heating_fuel |
--                                        water_heating | project_type). PRIVACY: the
--                                        address value is never sent, only that it was entered.
--   heat_pump_calculator_submit        — "Calculate impact" pressed (household_type,
--                                        heating_fuel, water_heating, project_type)
--   heat_pump_calculator_edit          — household info edited after viewing results
--   heat_pump_calculator_error         — calculator error (error_type:
--                                        address_not_supported | error | invalid_response)
--   heat_pump_calculator_result        — results rendered; annual deltas (negative
--                                        bill_delta = savings, negative emissions_delta =
--                                        reduction) at median / p20 / p80, plus project_type
--   heat_pump_connect_now_find_installer — Power Ahead Colorado contractor search
--   heat_pump_connect_now_expand_search  — Love Electric contractor search
--   heat_pump_pdf_page                 — contractor-tips PDF page reached (page_number)
--   heat_pump_pdf_print                — contractor-tips PDF print
-- screener_state / screener_uid arrive as params. These events are CESN-only, so a
-- non-null screener_uid is the per-user join key for path / correlation marts.

select
    event_date,
    event_timestamp,
    parse_date('%Y%m%d', event_date) as event_date_parsed,
    event_name,

    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index,

    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,

    -- event-specific params
    max(case when ep.key = 'cta' then ep.value.string_value end) as cta,
    max(case when ep.key = 'field' then ep.value.string_value end) as field,
    max(case when ep.key = 'error_type' then ep.value.string_value end) as error_type,
    max(case when ep.key = 'household_type' then ep.value.string_value end) as household_type,
    max(case when ep.key = 'heating_fuel' then ep.value.string_value end) as heating_fuel,
    max(case when ep.key = 'water_heating' then ep.value.string_value end) as water_heating,
    max(case when ep.key = 'project_type' then ep.value.string_value end) as project_type,
    max(case when ep.key = 'rebate_type' then ep.value.string_value end) as rebate_type,
    max(case when ep.key = 'rebate_category' then ep.value.string_value end) as rebate_category,

    -- computed calculator outputs (annual, dollars / emissions). Sent as doubles;
    -- fall back to a string cast in case GA4 coerces a whole number to int/string.
    max(case when ep.key = 'annual_bill_delta_median'
        then coalesce(ep.value.double_value, safe_cast(ep.value.string_value as float64))
    end) as annual_bill_delta_median,
    max(case when ep.key = 'annual_bill_delta_p20'
        then coalesce(ep.value.double_value, safe_cast(ep.value.string_value as float64))
    end) as annual_bill_delta_p20,
    max(case when ep.key = 'annual_bill_delta_p80'
        then coalesce(ep.value.double_value, safe_cast(ep.value.string_value as float64))
    end) as annual_bill_delta_p80,
    max(case when ep.key = 'annual_emissions_delta_median'
        then coalesce(ep.value.double_value, safe_cast(ep.value.string_value as float64))
    end) as annual_emissions_delta_median,
    max(case when ep.key = 'annual_emissions_delta_p20'
        then coalesce(ep.value.double_value, safe_cast(ep.value.string_value as float64))
    end) as annual_emissions_delta_p20,
    max(case when ep.key = 'annual_emissions_delta_p80'
        then coalesce(ep.value.double_value, safe_cast(ep.value.string_value as float64))
    end) as annual_emissions_delta_p80,

    max(case when ep.key = 'page_number'
        then coalesce(ep.value.int_value, safe_cast(ep.value.string_value as int64))
    end) as pdf_page_number

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

-- Bound the wildcard scan: these events don't exist before the heat-pump
-- instrumentation shipped. Mirrors screener_analytics_epoch_suffix elsewhere.
where _table_suffix >= '{{ var("screener_analytics_epoch_suffix") }}'
    and event_name in (
        'heat_pump_journey_learn_more_click',
        'rebate_link_click',
        'heat_pump_cta_click',
        'heat_pump_calculator_field',
        'heat_pump_calculator_submit',
        'heat_pump_calculator_edit',
        'heat_pump_calculator_error',
        'heat_pump_calculator_result',
        'heat_pump_connect_now_find_installer',
        'heat_pump_connect_now_expand_search',
        'heat_pump_pdf_page',
        'heat_pump_pdf_print'
    )

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
