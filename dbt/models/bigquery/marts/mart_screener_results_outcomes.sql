{{
  config(
    materialized='table'
  )
}}

-- Screener results outcomes - daily grain by state
-- Powers the Results dashboard tab's outcome summary: results loaded vs.
-- none-eligible vs. error, and the distribution of programs found / estimated
-- value among screenings that loaded results.
-- program_count is treated as "eligible programs found" per
-- analytics-dbt-notes.md (open question on eligible vs. total incl. ineligible
-- pending confirmation with partners).

with results_loaded as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        program_count,
        total_estimated_value
    from {{ ref('stg_ga_screener_results_outcomes') }}
    where event_name = 'screener_results_loaded'
),

none_eligible as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid
    from {{ ref('stg_ga_screener_results_outcomes') }}
    where event_name = 'screener_results_none_eligible'
),

results_errors as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid
    from {{ ref('stg_ga_screener_results_outcomes') }}
    where event_name = 'screener_results_error'
),

error_recoveries as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid
    from {{ ref('stg_ga_screener_results_outcomes') }}
    where event_name = 'screener_results_error_recovery'
),

date_state_grain as (
    select event_date, event_date_parsed, screener_state from results_loaded
    union distinct
    select event_date, event_date_parsed, screener_state from none_eligible
    union distinct
    select event_date, event_date_parsed, screener_state from results_errors
    union distinct
    select event_date, event_date_parsed, screener_state from error_recoveries
)

select
    g.event_date,
    g.event_date_parsed,
    g.screener_state,

    count(distinct rl.screener_uid) as screenings_results_loaded,
    count(distinct ne.screener_uid) as screenings_none_eligible,
    count(distinct re.screener_uid) as screenings_results_error,
    count(distinct er.screener_uid) as screenings_error_recovered,

    round(avg(rl.program_count), 2) as avg_program_count,
    round(
        approx_quantiles(rl.program_count, 100 ignore nulls)[offset(50)],
        2
    ) as median_program_count,

    round(avg(rl.total_estimated_value), 2) as avg_total_estimated_value,
    round(
        approx_quantiles(rl.total_estimated_value, 100 ignore nulls)[offset(50)],
        2
    ) as median_total_estimated_value,

    current_timestamp() as updated_at

from date_state_grain g
left join results_loaded rl
    on g.event_date = rl.event_date
    and g.screener_state = rl.screener_state
left join none_eligible ne
    on g.event_date = ne.event_date
    and g.screener_state = ne.screener_state
left join results_errors re
    on g.event_date = re.event_date
    and g.screener_state = re.screener_state
left join error_recoveries er
    on g.event_date = er.event_date
    and g.screener_state = er.screener_state
group by g.event_date, g.event_date_parsed, g.screener_state
order by g.event_date desc, g.screener_state
