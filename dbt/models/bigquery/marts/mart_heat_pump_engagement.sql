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
        screener_state,
        screener_uid,
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        case
            when event_name = 'heat_pump_journey_learn_more_click' then 'Learn more (Why get a heat pump?)'
            when event_name = 'heat_pump_rebate_link_click' then 'Learn how to apply (rebates)'
            when event_name = 'heat_pump_cta_click' and cta = 'calculate_impact' then 'Calculate impact (CTA)'
            when event_name = 'heat_pump_cta_click' and cta = 'connect_now' then 'Connect now (CTA)'
            when event_name = 'heat_pump_cta_click' then 'CTA (unspecified)'
            when event_name = 'heat_pump_connect_now_find_installer' then 'Power Ahead Colorado contractor search'
            when event_name = 'heat_pump_connect_now_expand_search' then 'Love Electric contractor search'
            when event_name = 'heat_pump_pdf_page' then 'Contractor tips PDF — page reached'
            when event_name = 'heat_pump_pdf_print' then 'Contractor tips PDF — print'
        end as interaction,
        -- the section whose view is this interaction's denominator
        case
            when event_name = 'heat_pump_journey_learn_more_click' then 'why_heat_pump'
            when event_name = 'heat_pump_rebate_link_click' then 'rebates'
            when event_name = 'heat_pump_cta_click' and cta = 'calculate_impact' then 'bills_impact'
            -- the Connect now CTA lives on the journey card, so its denominator is
            -- the card view; the contractor searches live on the ConnectNow page.
            when event_name = 'heat_pump_cta_click' and cta = 'connect_now' then 'find_contractor_card'
            when event_name = 'heat_pump_connect_now_find_installer' then 'connect_now_page'
            when event_name = 'heat_pump_connect_now_expand_search' then 'connect_now_page'
            when event_name = 'heat_pump_pdf_page' then 'contractor_pdf'
            when event_name = 'heat_pump_pdf_print' then 'contractor_pdf'
        end as section
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name in (
        'heat_pump_journey_learn_more_click',
        'heat_pump_rebate_link_click',
        'heat_pump_cta_click',
        'heat_pump_connect_now_find_installer',
        'heat_pump_connect_now_expand_search',
        'heat_pump_pdf_page',
        'heat_pump_pdf_print'
    )
),

clicks_summary as (
    select
        event_date, event_date_parsed, screener_state, interaction, section,
        count(*) as total_clicks,
        count(distinct screener_uid) as users,
        count(distinct session_key) as sessions
    from clicks
    group by event_date, event_date_parsed, screener_state, interaction, section
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
    c.screener_state,
    c.interaction,
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
