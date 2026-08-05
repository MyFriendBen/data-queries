{{
  config(
    materialized='table'
  )
}}

-- Impact-calculator engagement funnel (Story 2: how intuitive is the calculator).
-- Daily grain, one row per (date, stage), ordered by funnel_rank so the card reads
-- top to bottom in the order a user moves through the calculator:
--   household_type -> address -> heating_fuel -> water_heating -> project_type
--   -> clicked_calculate (button pressed) -> calculate_impact (passed validation)
--   -> results_shown -> edit_after_results
-- plus an errors stage (off-funnel, count of error events). The
-- clicked_calculate -> calculate_impact drop is submissions that failed validation.
--
-- Each field stage counts heat_pump_calculator_field rows for that field; submit,
-- result, edit, and error come from their own events. Every stage carries both
-- total_clicks (raw event count) and users (distinct screener_uid, the screening
-- grain); the funnel card draws users, and total_clicks is kept for the clicks
-- view. uid is present here — the calculator is on the post-screening results
-- page. PRIVACY: heat_pump_calculator_field with
-- field='address' records only THAT an address was entered, never its value.

with field_events as (
    select
        event_date, event_date_parsed, screener_state, screener_uid,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        field as stage
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name = 'heat_pump_calculator_field'
        and field in ('household_type', 'address', 'heating_fuel', 'water_heating', 'project_type')
),

other_stages as (
    select
        event_date, event_date_parsed, screener_state, screener_uid,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        case event_name
            when 'heat_pump_calculator_submit_attempt' then 'clicked_calculate'
            when 'heat_pump_calculator_submit' then 'calculate_impact'
            when 'heat_pump_calculator_result' then 'results_shown'
            when 'heat_pump_calculator_edit' then 'edit_after_results'
            when 'heat_pump_calculator_error' then 'errors'
        end as stage
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name in (
        'heat_pump_calculator_submit_attempt',
        'heat_pump_calculator_submit',
        'heat_pump_calculator_result',
        'heat_pump_calculator_edit',
        'heat_pump_calculator_error'
    )
),

all_stages as (
    select * from field_events
    union all
    select * from other_stages
)

select
    event_date,
    event_date_parsed,
    screener_state,
    stage,
    -- funnel_rank drives card ordering; errors sits at the end (off-funnel).
    -- clicked_calculate (button pressed) vs calculate_impact (passed validation):
    -- the gap between them is the validation-failure drop-off.
    case stage
        when 'household_type' then 1
        when 'address' then 2
        when 'heating_fuel' then 3
        when 'water_heating' then 4
        when 'project_type' then 5
        when 'clicked_calculate' then 6
        when 'calculate_impact' then 7
        when 'results_shown' then 8
        when 'edit_after_results' then 9
        when 'errors' then 10
    end as funnel_rank,

    count(*) as total_clicks,
    count(distinct screener_uid) as users,
    count(distinct session_key) as sessions,

    current_timestamp() as updated_at

from all_stages
group by event_date, event_date_parsed, screener_state, stage, funnel_rank
order by event_date desc, funnel_rank
