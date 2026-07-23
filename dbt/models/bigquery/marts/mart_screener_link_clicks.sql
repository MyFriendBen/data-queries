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
-- CLASSIFICATION now keys off link_location (FE #2163 gap #3), not link_name.
-- Site-chrome footer clicks (logo, language, About/Privacy/Terms legal links) also
-- fire as screener_link_click; they carry link_location = 'footer' and are served by
-- mart_screener_footer_engagement, so we EXCLUDE 'footer' here. Crucially this fixes
-- the old name-based exclusion, which wrongly dropped Privacy/Terms clicked INLINE on
-- the Disclaimer step (same link name, different location) — those carry
-- link_location = 'disclaimer_inline' and are now correctly retained as in-step
-- Disclaimer engagement. edit_nav links carry link_location = 'results_needs'.
-- Rows with a null link_location (pre-#2163 events, before the param shipped) fall
-- back to the legacy name-based footer exclusion so historical data isn't mislabeled.
-- link_label is the display name; screener_step_name is the step. Daily grain by state.

with clicks as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        link_name,
        link_location,
        screener_step_name
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name = 'screener_link_click'
        -- Exclude footer/chrome. New events: by location. Legacy events (null
        -- location): fall back to the old name-based exclusion.
        and coalesce(link_location, '') != 'footer'
        and not (
            link_location is null
            and coalesce(link_name, '') in ('About Us', 'Privacy Policy', 'Terms and Conditions')
        )
),

classified as (
    select
        *,
        case
            -- internal go-back-to-edit links (edit behavior, not content)
            when link_location = 'results_needs'
                or link_name = 'Additional Resources — Edit Step' then 'edit_nav'
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
    link_location,
    link_label,
    screener_step_name,
    -- friendly step label (shared ladder macro) for the in-step links card
    {{ screener_step_label('screener_step_name') }} as screener_step_label,

    count(*) as total_clicks,
    count(distinct screener_uid) as screenings,

    current_timestamp() as updated_at

from classified
group by event_date, event_date_parsed, screener_state, link_group, link_location, link_label, screener_step_name
order by event_date desc, screener_state, total_clicks desc
