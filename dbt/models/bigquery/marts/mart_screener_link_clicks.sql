{{
  config(
    materialized='table'
  )
}}

-- In-step content links + internal edit-navigation links, from screener_link_click.
-- Two groups the cards split on:
--   'in_step'  — external/redirect content links inside a specific step's body
--                (e.g. Public Charge on disclaimer). Answers "which content links
--                get clicked, and from which step".
--   'edit_nav' — internal go-back-to-edit links ("Additional Resources — Edit Step"
--                from the results Needs section, url = /{state}/{uid}/...). Edit
--                BEHAVIOR, not content; surfaced as its own stat.
--
-- Scope note: this mart deliberately covers ONLY screener_link_click, and only its
-- content/edit-nav links. Site-chrome clicks (logo, language switch, and the footer
-- About/Privacy/Terms legal links — which also fire as screener_link_click) are
-- served by mart_screener_footer_engagement instead, so they are EXCLUDED here to
-- avoid a dead duplicate branch. link_label is the display name; screener_step_name
-- is the step the link was clicked on. Daily grain by state.

with clicks as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        link_name,
        screener_step_name
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name = 'screener_link_click'
        -- footer legal links are site chrome (see mart_screener_footer_engagement)
        and coalesce(link_name, '') not in ('About Us', 'Privacy Policy', 'Terms and Conditions')
),

classified as (
    select
        *,
        case
            -- internal go-back-to-edit links (edit behavior, not content)
            when link_name = 'Additional Resources — Edit Step' then 'edit_nav'
            else 'in_step'
        end as link_group,
        coalesce(link_name, '(unnamed)') as link_label
    from clicks
)

select
    event_date,
    event_date_parsed,
    screener_state,
    link_group,
    link_label,
    screener_step_name,
    -- friendly step label (shared ladder macro) for the in-step links card
    {{ screener_step_label('screener_step_name') }} as screener_step_label,

    count(*) as total_clicks,
    count(distinct screener_uid) as screenings,

    current_timestamp() as updated_at

from classified
group by event_date, event_date_parsed, screener_state, link_group, link_label, screener_step_name
order by event_date desc, screener_state, total_clicks desc
