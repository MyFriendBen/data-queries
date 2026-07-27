{{
  config(
    materialized='table'
  )
}}

-- Per-member-page income entry (FE #2163 member_index). Answers "of the member-
-- detail pages people viewed, what share added an income source" — the meaningful
-- rate the old raw-count Income Source Actions card couldn't compute without a
-- member/page index.
--
-- Grain: one row per (date, state) with distinct-page counts:
--   member_pages_viewed       = distinct (screener_uid, member_index) that fired the
--                               member-details step VIEW event
--   member_pages_added_income = distinct pages with a screener_income_source add
--   member_pages_deleted_income = distinct pages with a screener_income_source delete
-- Every numerator keys on (screener_uid, member_index) as a subset of viewed_pages,
-- so each action's rate over member_pages_viewed is <= 100%. Attributed to the page's
-- FIRST-seen day so a dashboard date filter cohorts cleanly. (Income has only add +
-- delete actions — no edit, unlike household members.)
--
-- member_index is required on both sides — rows without it (pre-#2163) are dropped
-- so a null index can't collapse many pages into one bogus bucket.

with viewed_pages as (
    select
        screener_uid,
        member_index,
        min(event_date_parsed) as event_date_parsed,
        max(screener_state) as screener_state
    from {{ ref('stg_ga_screener_form_funnel') }}
    where event_name = 'screener_form_step'
        and step_action = 'view'
        and screener_step_name = 'member-details'
        and screener_uid is not null
        and member_index is not null
    group by screener_uid, member_index
),

income_action_pages as (
    select
        screener_uid,
        member_index,
        logical_or(action = 'add')    as added_income,
        logical_or(action = 'delete') as deleted_income
    from {{ ref('stg_ga_screener_section_engagement') }}
    where event_name = 'screener_income_source'
        and screener_uid is not null
        and member_index is not null
    group by screener_uid, member_index
),

per_page as (
    select
        v.screener_uid,
        v.member_index,
        v.event_date_parsed,
        v.screener_state,
        coalesce(i.added_income, false)   as added_income,
        coalesce(i.deleted_income, false) as deleted_income
    from viewed_pages v
    left join income_action_pages i
        on v.screener_uid = i.screener_uid
        and v.member_index = i.member_index
)

select
    event_date_parsed,
    screener_state,

    count(*) as member_pages_viewed,
    countif(added_income) as member_pages_added_income,
    countif(deleted_income) as member_pages_deleted_income,

    current_timestamp() as updated_at

from per_page
group by event_date_parsed, screener_state
order by event_date_parsed desc, screener_state
