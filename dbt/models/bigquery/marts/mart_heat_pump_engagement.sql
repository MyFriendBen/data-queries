{{
  config(
    materialized='table'
  )
}}

-- Heat-pump journey engagement: clicks and distinct users per interaction, at a
-- daily grain. Powers the Story 1 (what users click on the HVAC page) and Story 3
-- (contractor lookups + PDF) cards on the CESN heat-pump tab.
--
-- One row per (date, interaction). interaction is a friendly, card-ready label
-- derived from event_name (and the cta param, which splits heat_pump_cta_click
-- into its two internal CTAs). users is distinct screener_uid: the heat-pump
-- journey lives on the post-screening results page, so screener_uid is present
-- (created at screener step 3, well before this journey), making it the right
-- per-user key here — unlike pre-uid in-step link clicks.

with events as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        event_name,
        cta
    from {{ ref('stg_ga_heat_pump_journey') }}
    where event_name in (
        'heat_pump_journey_learn_more_click',
        'rebate_link_click',
        'heat_pump_cta_click',
        'heat_pump_connect_now_find_installer',
        'heat_pump_connect_now_expand_search',
        'heat_pump_pdf_page',
        'heat_pump_pdf_print'
    )
),

labeled as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        case
            when event_name = 'heat_pump_journey_learn_more_click' then 'Learn more (Why get a heat pump?)'
            when event_name = 'rebate_link_click' then 'Learn how to apply (rebates)'
            when event_name = 'heat_pump_cta_click' and cta = 'calculate_impact' then 'Calculate impact (CTA)'
            when event_name = 'heat_pump_cta_click' and cta = 'connect_now' then 'Connect now (CTA)'
            when event_name = 'heat_pump_cta_click' then 'CTA (unspecified)'
            when event_name = 'heat_pump_connect_now_find_installer' then 'Power Ahead Colorado contractor search'
            when event_name = 'heat_pump_connect_now_expand_search' then 'Love Electric contractor search'
            when event_name = 'heat_pump_pdf_page' then 'Contractor tips PDF — page reached'
            when event_name = 'heat_pump_pdf_print' then 'Contractor tips PDF — print'
        end as interaction
    from events
)

select
    event_date,
    event_date_parsed,
    screener_state,
    interaction,

    count(*) as total_clicks,
    count(distinct screener_uid) as users,

    current_timestamp() as updated_at

from labeled
group by event_date, event_date_parsed, screener_state, interaction
order by event_date desc, total_clicks desc
