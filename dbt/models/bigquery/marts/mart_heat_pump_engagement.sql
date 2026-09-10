{{
  config(
    materialized='table'
  )
}}

-- Heat-pump journey engagement: per interaction, the clicks and the section views
-- that are its denominator, so a click-through rate is computable. Daily grain,
-- one row per (date, interaction). Powers Story 1 (what users click on the HVAC
-- page) and Story 3 (contractor lookups + PDF).
--
-- PDF PAGES: the contractor-tips PDF is broken out per page, because the AC asks
-- specifically for "clicks and users to pages 2 and 3". Page 1 fires when the PDF
-- opens, so it doubles as the PDF's own denominator — the page-2 count over the
-- page-1 count is the share of readers who turned past the first page.
--
-- Each interaction maps to the section whose view is its denominator (the
-- heat_pump_section_view event). The card can then show clicks, users, and
-- clicked / saw-the-section as a rate.
--
-- SEGMENTATION (Story 4): income band, region memberships and the Xcel flag are
-- joined from the household bridge and carried in the grain, so a dashboard
-- filter re-scopes both the clicks and their section-view denominator. Rows for
-- screenings with no bridge match fall into 'Unknown' rather than disappearing.
--
-- Three grains are carried so both "users" and "sessions" rates are possible:
--   total_clicks  — raw event count
--   users         — distinct screener_uid (a screening; present on the post-
--                   screening results page where this journey lives)
--   sessions      — distinct GA session key (user_pseudo_id, ga_session_id)
-- with the matching section_view counts (section_views / view_users /
-- view_sessions) joined on section.

with attributes as (
    select
        screener_uid,
        income_band,
        income_band_sort,
        is_below_200_fpl,
        region_memberships,
        is_xcel_customer
    from {{ ref('stg_screener_household_attributes') }}
),

clicks as (
    select
        e.event_date,
        e.event_date_parsed,
        date_trunc(e.event_date_parsed, week(monday)) as event_week,
        e.screener_state,
        e.screener_uid,
        coalesce(a.income_band, 'Unknown') as income_band,
        coalesce(a.income_band_sort, 4) as income_band_sort,
        coalesce(a.is_below_200_fpl, false) as is_below_200_fpl,
        coalesce(a.region_memberships, ',Unknown,') as region_memberships,
        coalesce(a.is_xcel_customer, false) as is_xcel_customer,
        to_json_string(struct(e.user_pseudo_id, e.ga_session_id)) as session_key,
        case
            when e.event_name = 'heat_pump_journey_learn_more_click' then 'Learn more (Why get a heat pump?)'
            when e.event_name = 'heat_pump_rebate_link_click' then 'Learn how to apply (rebates)'
            when e.event_name = 'heat_pump_rewiring_america_click' then 'Rewiring America (calculator source)'
            when e.event_name = 'heat_pump_cta_click' and e.cta = 'calculate_impact' then 'Calculate impact (CTA)'
            when e.event_name = 'heat_pump_cta_click' and e.cta = 'connect_now' then 'Connect now (CTA)'
            when e.event_name = 'heat_pump_cta_click' then 'CTA (unspecified)'
            when e.event_name = 'heat_pump_connect_now_find_installer' then 'Power Ahead Colorado contractor search'
            when e.event_name = 'heat_pump_connect_now_expand_search' then 'Love Electric contractor search'
            -- per-page so "pages 2 and 3" is directly answerable
            when e.event_name = 'heat_pump_pdf_page' and e.pdf_page_number is not null
                then concat('Contractor tips PDF — page ', cast(e.pdf_page_number as string))
            when e.event_name = 'heat_pump_pdf_page' then 'Contractor tips PDF — page (unknown)'
            when e.event_name = 'heat_pump_pdf_print' then 'Contractor tips PDF — print'
            when e.event_name = 'heat_pump_pdf_fullscreen' then 'Contractor tips PDF — fullscreen'
        end as interaction,
        -- sort key so the card can order PDF pages naturally rather than
        -- alphabetically ("page 10" before "page 2")
        case
            when e.event_name = 'heat_pump_pdf_page' then coalesce(e.pdf_page_number, 999)
            else 0
        end as interaction_sort,
        -- the section whose view is this interaction's denominator
        case
            when e.event_name = 'heat_pump_journey_learn_more_click' then 'why_heat_pump'
            when e.event_name = 'heat_pump_rebate_link_click' then 'rebates'
            when e.event_name = 'heat_pump_rewiring_america_click' then 'calculator'
            when e.event_name = 'heat_pump_cta_click' and e.cta = 'calculate_impact' then 'bills_impact'
            -- the Connect now CTA lives on the journey card, so its denominator is
            -- the card view; the contractor searches live on the ConnectNow page.
            when e.event_name = 'heat_pump_cta_click' and e.cta = 'connect_now' then 'find_contractor_card'
            when e.event_name = 'heat_pump_connect_now_find_installer' then 'connect_now_page'
            when e.event_name = 'heat_pump_connect_now_expand_search' then 'connect_now_page'
            when e.event_name in ('heat_pump_pdf_page', 'heat_pump_pdf_print', 'heat_pump_pdf_fullscreen')
                then 'contractor_pdf'
        end as section
    from {{ ref('stg_ga_heat_pump_journey') }} e
    left join attributes a on e.screener_uid = a.screener_uid
    where e.event_name in (
        'heat_pump_journey_learn_more_click',
        'heat_pump_rebate_link_click',
        'heat_pump_rewiring_america_click',
        'heat_pump_cta_click',
        'heat_pump_connect_now_find_installer',
        'heat_pump_connect_now_expand_search',
        'heat_pump_pdf_page',
        'heat_pump_pdf_print',
        'heat_pump_pdf_fullscreen'
    )
),

clicks_summary as (
    select
        event_date, event_date_parsed, event_week, screener_state,
        interaction, interaction_sort, section,
        income_band, income_band_sort, is_below_200_fpl,
        region_memberships, is_xcel_customer,
        count(*) as total_clicks,
        count(distinct screener_uid) as users,
        -- `users` is distinct WITHIN THE DAY, so summing it across a date range
        -- counts a screening once per day it was active. The sketch merges across
        -- days into a real distinct count; cards read this, not sum(users).
        hll_count.init(screener_uid) as users_hll,
        count(distinct session_key) as sessions
    from clicks
    group by event_date, event_date_parsed, event_week, screener_state,
        interaction, interaction_sort, section,
        income_band, income_band_sort, is_below_200_fpl,
        region_memberships, is_xcel_customer
),

-- section_view is the denominator: one per section render.
section_views as (
    select
        e.event_date,
        e.event_date_parsed,
        date_trunc(e.event_date_parsed, week(monday)) as event_week,
        e.screener_state,
        e.section,
        coalesce(a.income_band, 'Unknown') as income_band,
        coalesce(a.income_band_sort, 4) as income_band_sort,
        coalesce(a.is_below_200_fpl, false) as is_below_200_fpl,
        coalesce(a.region_memberships, ',Unknown,') as region_memberships,
        coalesce(a.is_xcel_customer, false) as is_xcel_customer,
        count(*) as section_views,
        count(distinct e.screener_uid) as view_users,
        hll_count.init(e.screener_uid) as view_users_hll,
        count(distinct to_json_string(struct(e.user_pseudo_id, e.ga_session_id))) as view_sessions
    from {{ ref('stg_ga_heat_pump_journey') }} e
    left join attributes a on e.screener_uid = a.screener_uid
    where e.event_name = 'heat_pump_section_view'
    group by e.event_date, e.event_date_parsed, event_week, e.screener_state, e.section,
        income_band, income_band_sort, is_below_200_fpl, region_memberships, is_xcel_customer
),

-- Every interaction ever seen for a section. Needed because a day on which a
-- section was VIEWED but nothing was clicked otherwise produces no row at all:
-- joining views onto clicks means the CTR card, which sums the denominator per
-- interaction, only ever sums it over days that already had a click. A section
-- seen by 100 users/day for six click-free days and then 10 views / 3 clicks on
-- day seven reported 30% instead of ~0.5%.
interaction_catalog as (
    select distinct section, interaction, interaction_sort
    from clicks
    where section is not null and interaction is not null
),

-- One row per (day, segment, interaction) whose section was viewed, clicked or
-- not. This is the denominator side of the full outer join below.
view_spine as (
    select
        v.event_date, v.event_date_parsed, v.event_week, v.screener_state,
        i.interaction, i.interaction_sort, v.section,
        v.income_band, v.income_band_sort, v.is_below_200_fpl,
        v.region_memberships, v.is_xcel_customer,
        v.section_views, v.view_users, v.view_users_hll, v.view_sessions
    from section_views v
    join interaction_catalog i on i.section = v.section
)

select
    coalesce(c.event_date, s.event_date) as event_date,
    coalesce(c.event_date_parsed, s.event_date_parsed) as event_date_parsed,
    coalesce(c.event_week, s.event_week) as event_week,
    coalesce(c.screener_state, s.screener_state) as screener_state,
    coalesce(c.interaction, s.interaction) as interaction,
    coalesce(c.interaction_sort, s.interaction_sort) as interaction_sort,
    coalesce(c.section, s.section) as section,

    coalesce(c.income_band, s.income_band) as income_band,
    coalesce(c.income_band_sort, s.income_band_sort) as income_band_sort,
    coalesce(c.is_below_200_fpl, s.is_below_200_fpl) as is_below_200_fpl,
    coalesce(c.region_memberships, s.region_memberships) as region_memberships,
    coalesce(c.is_xcel_customer, s.is_xcel_customer) as is_xcel_customer,

    -- Zero, not null: a viewed-but-unclicked row is a real 0 clicks.
    coalesce(c.total_clicks, 0) as total_clicks,
    coalesce(c.users, 0) as users,
    c.users_hll,
    coalesce(c.sessions, 0) as sessions,

    s.section_views,
    s.view_users,
    s.view_users_hll,
    s.view_sessions,

    -- click-through rates (percent). NULLIF avoids divide-by-zero; null when the
    -- section had no recorded views that day.
    round(coalesce(c.total_clicks, 0) * 100.0 / nullif(s.section_views, 0), 1) as click_rate_pct,
    round(coalesce(c.users, 0) * 100.0 / nullif(s.view_users, 0), 1) as user_click_rate_pct,
    round(coalesce(c.sessions, 0) * 100.0 / nullif(s.view_sessions, 0), 1) as session_click_rate_pct,

    current_timestamp() as updated_at

-- FULL OUTER, not left-from-clicks: the left join dropped every view-only day
-- from the denominator (see interaction_catalog above), and a plain views-driven
-- left join would drop clicks recorded on a day with no section_view row.
from clicks_summary c
full outer join view_spine s
    on c.event_date = s.event_date
    and ifnull(c.screener_state, '∅') = ifnull(s.screener_state, '∅')
    and c.section = s.section
    and c.interaction = s.interaction
    -- denominator must be scoped to the same segment as the numerator, or a
    -- filtered card would divide segment clicks by everyone's views
    and c.income_band = s.income_band
    and c.region_memberships = s.region_memberships
    and c.is_xcel_customer = s.is_xcel_customer
order by event_date desc, total_clicks desc
