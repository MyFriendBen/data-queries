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
-- Three grains are carried so both "users" and "sessions" rates are possible:
--   total_clicks  — raw event count
--   users         — distinct screener_uid (a screening; present on the post-
--                   screening results page where this journey lives)
--   sessions      — distinct GA session key (user_pseudo_id, ga_session_id)
-- with the matching section_view counts (section_views / view_users /
-- view_sessions) joined on section.

with clicks as (
    select
        event_date,
        event_date_parsed,
        date_trunc(event_date_parsed, week(monday)) as event_week,
        screener_state,
        screener_uid,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        case
            when event_name = 'heat_pump_journey_learn_more_click' then 'Learn more (Why get a heat pump?)'
            when event_name = 'heat_pump_rebate_link_click' then 'Learn how to apply (rebates)'
            when event_name = 'heat_pump_rewiring_america_click' then 'Rewiring America (calculator source)'
            when event_name = 'heat_pump_cta_click' and cta = 'calculate_impact' then 'Calculate impact (CTA)'
            when event_name = 'heat_pump_cta_click' and cta = 'connect_now' then 'Connect now (CTA)'
            when event_name = 'heat_pump_cta_click' then 'CTA (unspecified)'
            when event_name = 'heat_pump_connect_now_find_installer' then 'Power Ahead Colorado contractor search'
            when event_name = 'heat_pump_connect_now_expand_search' then 'Love Electric contractor search'
            -- per-page so "pages 2 and 3" is directly answerable
            when event_name = 'heat_pump_pdf_page' and pdf_page_number is not null
                then concat('Contractor tips PDF — page ', cast(pdf_page_number as string))
            when event_name = 'heat_pump_pdf_page' then 'Contractor tips PDF — page (unknown)'
            when event_name = 'heat_pump_pdf_print' then 'Contractor tips PDF — print'
            when event_name = 'heat_pump_pdf_fullscreen' then 'Contractor tips PDF — fullscreen'
        end as interaction,
        -- sort key so the card can order PDF pages naturally rather than
        -- alphabetically ("page 10" before "page 2")
        case
            when event_name = 'heat_pump_pdf_page' then coalesce(pdf_page_number, 999)
            else 0
        end as interaction_sort,
        -- the section whose view is this interaction's denominator
        case
            when event_name = 'heat_pump_journey_learn_more_click' then 'why_heat_pump'
            when event_name = 'heat_pump_rebate_link_click' then 'rebates'
            when event_name = 'heat_pump_rewiring_america_click' then 'calculator'
            when event_name = 'heat_pump_cta_click' and cta = 'calculate_impact' then 'bills_impact'
            -- the Connect now CTA lives on the journey card, so its denominator is
            -- the card view; the contractor searches live on the ConnectNow page.
            when event_name = 'heat_pump_cta_click' and cta = 'connect_now' then 'find_contractor_card'
            when event_name = 'heat_pump_connect_now_find_installer' then 'connect_now_page'
            when event_name = 'heat_pump_connect_now_expand_search' then 'connect_now_page'
            when event_name in ('heat_pump_pdf_page', 'heat_pump_pdf_print', 'heat_pump_pdf_fullscreen')
                then 'contractor_pdf'
        end as section
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name in (
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
        count(*) as total_clicks,
        count(distinct screener_uid) as users,
        count(distinct session_key) as sessions
    from clicks
    group by event_date, event_date_parsed, event_week, screener_state,
        interaction, interaction_sort, section
),

-- section_view is the denominator: one per section render.
section_views as (
    select
        event_date,
        screener_state,
        section,
        count(*) as section_views,
        count(distinct screener_uid) as view_users,
        count(distinct to_json_string(struct(user_pseudo_id, ga_session_id))) as view_sessions
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name = 'heat_pump_section_view'
    group by event_date, screener_state, section
)

select
    c.event_date,
    c.event_date_parsed,
    c.event_week,
    c.screener_state,
    c.interaction,
    c.interaction_sort,
    c.section,

    c.total_clicks,
    c.users,
    c.sessions,

    v.section_views,
    v.view_users,
    v.view_sessions,

    -- click-through rates (percent). NULLIF avoids divide-by-zero; null when the
    -- section had no recorded views that day.
    round(c.total_clicks * 100.0 / nullif(v.section_views, 0), 1) as click_rate_pct,
    round(c.users * 100.0 / nullif(v.view_users, 0), 1) as user_click_rate_pct,
    round(c.sessions * 100.0 / nullif(v.view_sessions, 0), 1) as session_click_rate_pct,

    current_timestamp() as updated_at

from clicks_summary c
left join section_views v
    on c.event_date = v.event_date
    and ifnull(c.screener_state, '∅') = ifnull(v.screener_state, '∅')
    and c.section = v.section
order by c.event_date desc, c.total_clicks desc
