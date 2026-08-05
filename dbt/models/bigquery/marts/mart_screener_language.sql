{{
  config(
    materialized='table'
  )
}}

-- Screener language changes — daily grain by state and language.
-- Powers the Overview tab's language-distribution bar: which languages users
-- switch to via the language selector (screener_language_changed.language_name).
-- Note: this captures explicit language CHANGES, not the initial/default
-- language of a session — so it reflects users who actively switched, which is
-- the engagement signal we want here.

-- The header language selector is persistent, so switches fire throughout the
-- flow, not only pre-white-label. State is the emitted param when present, else
-- the white label parsed from the page URL — recovering the switches made while
-- on a /<wl>/... page. Null only for the rare switch on the bare landing page.
select
    event_date,
    event_date_parsed,
    coalesce(screener_state, url_screener_state) as screener_state,
    language_name,

    count(*) as total_changes,
    -- Session-deduped, NOT screener_uid: screener_language_changed fires from
    -- the global Header language selector, often before a screening uuid exists
    -- (uid is null pre-step-3). Deduping on screener_uid would undercount those,
    -- so dedupe on the session key instead.
    count(distinct to_json_string(struct(user_pseudo_id, ga_session_id))) as distinct_screenings,

    current_timestamp() as updated_at

from {{ ref('stg_ga_screener_step_interactions') }}
where event_name = 'screener_language_changed'
    and language_name is not null
group by event_date, event_date_parsed, coalesce(screener_state, url_screener_state), language_name
