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

-- Pre-aggregate each source to the (date, state) grain BEFORE joining. Joining
-- the raw per-event CTEs directly fans out (cartesian product per grain group).
-- The COUNT(DISTINCT uid) and AVG/approx_quantiles happen to survive uniform
-- fan-out mathematically, but it builds a large intermediate product per day/
-- state and is a trap (any future SUM() here would be inflated — see the bug
-- fixed in mart_screener_form_funnel). Aggregating first makes every side one
-- row per grain. Same pattern as mart_screener_saves.
results_loaded_summary as (
    select
        event_date, event_date_parsed, screener_state,
        count(distinct screener_uid) as screenings_results_loaded,
        round(avg(program_count), 2) as avg_program_count,
        round(approx_quantiles(program_count, 100 ignore nulls)[offset(50)], 2) as median_program_count,
        round(avg(total_estimated_value), 2) as avg_total_estimated_value,
        round(approx_quantiles(total_estimated_value, 100 ignore nulls)[offset(50)], 2) as median_total_estimated_value
    from results_loaded
    group by event_date, event_date_parsed, screener_state
),

none_eligible_summary as (
    select event_date, screener_state, count(distinct screener_uid) as screenings_none_eligible
    from none_eligible group by event_date, screener_state
),

results_errors_summary as (
    select event_date, screener_state, count(distinct screener_uid) as screenings_results_error
    from results_errors group by event_date, screener_state
),

error_recoveries_summary as (
    select event_date, screener_state, count(distinct screener_uid) as screenings_error_recovered
    from error_recoveries group by event_date, screener_state
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

    coalesce(rl.screenings_results_loaded, 0) as screenings_results_loaded,
    coalesce(ne.screenings_none_eligible, 0) as screenings_none_eligible,
    coalesce(re.screenings_results_error, 0) as screenings_results_error,
    coalesce(er.screenings_error_recovered, 0) as screenings_error_recovered,

    rl.avg_program_count,
    rl.median_program_count,
    rl.avg_total_estimated_value,
    rl.median_total_estimated_value,

    current_timestamp() as updated_at

-- NULL-safe state join (see mart_screener_form_funnel for the full rationale):
-- results events can also carry a null screener_state, and a plain equality join
-- would strand those rows (NULL = NULL is UNKNOWN). IFNULL both sides.
from date_state_grain g
left join results_loaded_summary rl
    on g.event_date = rl.event_date
    and ifnull(g.screener_state, '∅') = ifnull(rl.screener_state, '∅')
left join none_eligible_summary ne
    on g.event_date = ne.event_date
    and ifnull(g.screener_state, '∅') = ifnull(ne.screener_state, '∅')
left join results_errors_summary re
    on g.event_date = re.event_date
    and ifnull(g.screener_state, '∅') = ifnull(re.screener_state, '∅')
left join error_recoveries_summary er
    on g.event_date = er.event_date
    and ifnull(g.screener_state, '∅') = ifnull(er.screener_state, '∅')
order by g.event_date desc, g.screener_state
