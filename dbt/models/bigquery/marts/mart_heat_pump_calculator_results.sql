{{
  config(
    materialized='table'
  )
}}

-- Impact-calculator computed outputs (Story 7: how the calculator data affects
-- likelihood of pursuing a project). Daily grain, from heat_pump_calculator_result.
-- The FE sends annual deltas already summarized across the estimate range: a median
-- and a p20/p80 band for the bill delta, and a median emissions delta. SIGN: a
-- negative bill_delta is a saving, a negative emissions_delta is a reduction — the
-- cards flip the sign for display so "savings" reads positive.
--
-- We aggregate the per-screening medians to a daily distribution (avg + median of
-- the medians) so a trend line reads sensibly day over day. project_type is carried
-- so a card can break savings out by project. One result event per screening, so
-- distinct screener_uid = screenings that saw results.

with results as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        project_type,
        annual_bill_delta_median,
        annual_bill_delta_p20,
        annual_bill_delta_p80,
        annual_emissions_delta_median,
        annual_emissions_delta_p20,
        annual_emissions_delta_p80
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name = 'heat_pump_calculator_result'
)

select
    event_date,
    event_date_parsed,
    screener_state,
    coalesce(project_type, '(unspecified)') as project_type,

    count(distinct screener_uid) as screenings_with_results,

    round(avg(annual_bill_delta_median), 2) as avg_annual_bill_delta,
    round(approx_quantiles(annual_bill_delta_median, 100 ignore nulls)[offset(50)], 2) as median_annual_bill_delta,
    round(avg(annual_bill_delta_p20), 2) as avg_annual_bill_delta_p20,
    round(avg(annual_bill_delta_p80), 2) as avg_annual_bill_delta_p80,

    round(avg(annual_emissions_delta_median), 2) as avg_annual_emissions_delta,
    round(approx_quantiles(annual_emissions_delta_median, 100 ignore nulls)[offset(50)], 2) as median_annual_emissions_delta,
    round(avg(annual_emissions_delta_p20), 2) as avg_annual_emissions_delta_p20,
    round(avg(annual_emissions_delta_p80), 2) as avg_annual_emissions_delta_p80,

    current_timestamp() as updated_at

from results
group by event_date, event_date_parsed, screener_state, project_type
order by event_date desc, project_type
