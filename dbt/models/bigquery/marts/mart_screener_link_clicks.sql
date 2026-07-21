{{
  config(
    materialized='table'
  )
}}

-- Link / navigation clicks, classified into three groups the cards split on:
--   'chrome'   — site chrome present on every page: logo (header/footer), header
--                language switch, and the footer legal/about links. Answers "which
--                persistent nav do people use".
--   'in_step'  — external/redirect content links inside a specific step's body
--                (Public Charge on disclaimer, Other State Options on zip-code).
--                Answers "which content links get clicked, and from which step".
--   'edit_nav' — internal go-back-to-edit links (e.g. "Additional Resources — Edit
--                Step" from the results Needs section, url = /{state}/{uid}/...).
--                These are edit BEHAVIOR, not content; kept out of the in_step card
--                and surfaced as their own stat.
--
-- link_click carries footer legal links, in-step content links, AND internal
-- edit-navigation links, distinguished only by link_name — so the classification is
-- a link_name CASE. logo_click / language_changed are their own events, always chrome.
--
-- link_label is the display name; screener_step_name is meaningful only for
-- in_step rows (chrome links inherit whatever step happened to be showing, so the
-- cards ignore step for chrome). Daily grain by state.

with clicks as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        event_name,
        link_name,
        location,
        language_name,
        screener_step_name
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name in ('screener_link_click', 'screener_logo_click', 'screener_language_changed')
),

classified as (
    select
        *,
        case
            when event_name = 'screener_logo_click' then 'chrome'
            when event_name = 'screener_language_changed' then 'chrome'
            -- footer legal/about links are chrome
            when link_name in ('About Us', 'Privacy Policy', 'Terms and Conditions') then 'chrome'
            -- internal go-back-to-edit links (edit behavior, not content)
            when link_name = 'Additional Resources — Edit Step' then 'edit_nav'
            else 'in_step'
        end as link_group,
        case
            when event_name = 'screener_logo_click' then concat('Logo (', coalesce(location, 'unknown'), ')')
            when event_name = 'screener_language_changed' then concat('Language: ', coalesce(language_name, 'unknown'))
            else coalesce(link_name, '(unnamed)')
        end as link_label
    from clicks
)

select
    event_date,
    event_date_parsed,
    screener_state,
    link_group,
    link_label,
    -- only meaningful for in_step; null it for chrome so the chrome card doesn't
    -- show a spurious step
    if(link_group = 'in_step', screener_step_name, null) as screener_step_name,
    -- friendly step label (shared ladder macro) for the in-step links card; null
    -- for chrome rows
    if(link_group = 'in_step', {{ screener_step_label('screener_step_name') }}, null) as screener_step_label,

    count(*) as total_clicks,
    count(distinct screener_uid) as screenings,

    current_timestamp() as updated_at

from classified
group by event_date, event_date_parsed, screener_state, link_group, link_label, screener_step_name, screener_step_label
order by event_date desc, screener_state, total_clicks desc
