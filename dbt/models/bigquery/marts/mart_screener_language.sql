{{
  config(
    materialized='table'
  )
}}

-- Screener language changes — daily grain by state and language.
-- Powers the Overview tab's language-distribution bar: which languages users
-- switch to via the language selector (screener_language_changed.language_name).
-- Note: this captures explicit language CHANGES, not the initial/default
-- language of a session (see analytics-dbt-notes.md) — so it reflects users who
-- actively switched, which is the engagement signal we want here.

select
    event_date,
    event_date_parsed,
    screener_state,
    language_name,

    count(*) as total_changes,
    count(distinct screener_uid) as distinct_screenings,

    current_timestamp() as updated_at

from {{ ref('stg_ga_screener_step_interactions') }}
where event_name = 'screener_language_changed'
    and language_name is not null
group by event_date, event_date_parsed, screener_state, language_name
order by event_date desc, screener_state, total_changes desc
