{{
  config(
    materialized='table'
  )
}}

-- Impact-calculator results, ONE ROW PER SCREENING that saw results (Story 7).
--
-- Grain note: this model used to pre-aggregate to a daily median per project_type,
-- which made three things impossible — a true median across project types (you
-- cannot average medians back together), a split by whether the user went on to a
-- contractor search, and bucketing users by the size of their estimate. Cards are
-- native SQL over BigQuery and can aggregate perfectly well themselves, and one row
-- per screening is cheap at CESN volume, so the aggregation moved up into the cards.
--
-- SIGN: the FE sends a delta where negative = improvement. This model flips it once,
-- here, into positive "savings" / "reduction" columns so no downstream card has to
-- remember to multiply by -1. A negative saving (the project costs more) stays
-- negative and is meaningful.
--
-- UNITS: the FE sends emissions in lb CO2e (see remCalculateImpactTypes.ts). Debra
-- asked for metric tons plus the forest-acre equivalency the product already shows.
-- Both conversions use the same EPA constants the product uses, mirrored from
-- benefits-calculator src/utils/epaEquivalencies.ts — keep them in sync if EPA
-- republishes:
--   2204.62 lb per metric ton
--   1 metric ton CO2 sequestered per acre of average U.S. forest per year
--
-- SEGMENTATION (Story 4): income band, region memberships and the Xcel flag are
-- joined from the household bridge. One row per screening already, so these are
-- plain columns rather than extra grain.
--
-- COHORT: reached_contractor_search comes from mart_heat_pump_user_journey and is
-- what Story 7 actually asks for ("of users who click on the Power Ahead Colorado or
-- Love Electric contractor search, what are trends for..."). Carried as a flag so a
-- card can show the cohort, everyone, or both side by side.

{% set lbs_per_metric_ton = 2204.62 %}

with results as (
    select
        event_date,
        event_date_parsed,
        -- Monday-anchored week; Debra reports weekly with WoW/MoM comparison.
        date_trunc(event_date_parsed, week(monday)) as event_week,
        screener_state,
        screener_uid,
        coalesce(project_type, '(unspecified)') as project_type,
        coalesce(household_type, '(unspecified)') as household_type,
        coalesce(heating_fuel, '(unspecified)') as heating_fuel,
        coalesce(water_heating, '(unspecified)') as water_heating,

        -- flip delta -> savings/reduction (positive = better off)
        -1 * annual_bill_delta_median as annual_bill_savings,
        -- p20/p80 swap on the sign flip: the p20 delta is the p80 saving
        -1 * annual_bill_delta_p80 as annual_bill_savings_low,
        -1 * annual_bill_delta_p20 as annual_bill_savings_high,

        -1 * annual_emissions_delta_median as annual_emissions_reduction_lbs,
        -1 * annual_emissions_delta_p80 as annual_emissions_reduction_lbs_low,
        -1 * annual_emissions_delta_p20 as annual_emissions_reduction_lbs_high,

        -- a screening can re-run the calculator; keep the latest result per uid
        row_number() over (
            partition by screener_uid
            order by event_timestamp desc
        ) as recency_rank
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name = 'heat_pump_calculator_result'
),

latest as (
    select * from results where recency_rank = 1
)

select
    l.event_date,
    l.event_date_parsed,
    l.event_week,
    l.screener_state,
    l.screener_uid,

    l.project_type,
    l.household_type,
    l.heating_fuel,
    l.water_heating,

    l.annual_bill_savings,
    l.annual_bill_savings_low,
    l.annual_bill_savings_high,

    l.annual_emissions_reduction_lbs,
    l.annual_emissions_reduction_lbs_low,
    l.annual_emissions_reduction_lbs_high,

    -- metric tons CO2e (Debra's requested unit)
    round(l.annual_emissions_reduction_lbs / {{ lbs_per_metric_ton }}, 3)
        as annual_emissions_reduction_tons,
    -- EPA equivalency shown on the results page: acres of U.S. forest in one year.
    -- 1 metric ton CO2 per acre-year, so this equals the tonnage.
    round(l.annual_emissions_reduction_lbs / {{ lbs_per_metric_ton }}, 3)
        as annual_emissions_forest_acres,

    -- Story 7 cohort: did this screening go on to a contractor search?
    coalesce(j.reached_contractor_search, false) as reached_contractor_search,

    -- Story 4 segmentation
    coalesce(a.income_band, 'Unknown') as income_band,
    coalesce(a.income_band_sort, 4) as income_band_sort,
    coalesce(a.is_below_200_fpl, false) as is_below_200_fpl,
    coalesce(a.region_memberships, ',Unknown,') as region_memberships,
    coalesce(a.is_xcel_customer, false) as is_xcel_customer,

    current_timestamp() as updated_at

from latest l
left join {{ ref('mart_heat_pump_user_journey') }} j
    on l.screener_uid = j.screener_uid
left join {{ ref('stg_screener_household_attributes') }} a
    on l.screener_uid = a.screener_uid
