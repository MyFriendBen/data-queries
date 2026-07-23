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
-- Grain: one row per (date, state) with two distinct-page counts:
--   member_pages_viewed  = distinct (screener_uid, member_index) that fired the
--                          member-details step VIEW event
--   member_pages_added_income = distinct (screener_uid, member_index) that fired a
--                          screener_income_source action = 'add'
-- Both key on (screener_uid, member_index) so the numerator is a strict subset of
-- the denominator (a page must be viewed to add income on it) and the rate is <= 100%.
-- Attributed to the page's FIRST-seen day so a dashboard date filter cohorts cleanly.
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

income_add_pages as (
    select distinct
        screener_uid,
        member_index
    from {{ ref('stg_ga_screener_section_engagement') }}
    where event_name = 'screener_income_source'
        and action = 'add'
        and screener_uid is not null
        and member_index is not null
),

per_page as (
    select
        v.screener_uid,
        v.member_index,
        v.event_date_parsed,
        v.screener_state,
        (i.screener_uid is not null) as added_income
    from viewed_pages v
    left join income_add_pages i
        on v.screener_uid = i.screener_uid
        and v.member_index = i.member_index
)

select
    event_date_parsed,
    screener_state,

    count(*) as member_pages_viewed,
    countif(added_income) as member_pages_added_income,

    current_timestamp() as updated_at

from per_page
group by event_date_parsed, screener_state
order by event_date_parsed desc, screener_state
