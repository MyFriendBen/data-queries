{{
  config(
    materialized='table'
  )
}}

-- Session-grain footer / site-chrome engagement, deduped across ALL days a session
-- touched an element. One row per (session_key, element). This grain lets the cards
-- compute an exact "% of sessions that clicked X" (COUNT(DISTINCT session_key) over
-- the window) without the multi-day double-count a daily-grain SUM would suffer.
--
-- Site chrome (logo/language/social/feedback) often fires without the
-- screener_state param, so screener_state here is the param when present, else
-- the white label parsed from the page URL (see the coalesce below) — enough to
-- power per-tenant chrome cards, not just the all-states global ones.
--
-- element_group buckets by user intent, one card each:
--   'nav'            — logo, About/Privacy/Terms, language switch (wayfinding)
--   'social'         — LinkedIn / Facebook / Instagram (outbound advocacy)
--   'feedback_share' — Report a Bug, Contact Us, Share (support / sharing)
-- element is the friendly label plotted within a card. event_date_parsed is the
-- session's last-active day (for window filtering).

with ui_events as (
    select
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        event_date_parsed,
        event_name,
        link_name,
        location,
        feedback_channel,
        social_network,
        -- Prefer the emitted state param; fall back to the URL-parsed white label
        -- for chrome events fired before the param is set (see staging).
        coalesce(screener_state, url_screener_state) as row_state
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name in (
        'screener_logo_click',
        'screener_language_changed',
        'screener_social_click',
        'screener_feedback_click',
        'screener_link_click'
    )
),

shares as (
    select
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        event_date_parsed,
        coalesce(screener_state, url_screener_state) as row_state
    from {{ ref('stg_ga_screener_shares') }}
    where share_location = 'footer'
        and share_action = 'open'
),

-- Classify each raw footer event into (element_group, element). Chrome link_clicks
-- carry the legal-link names; the in-step content links (Public Charge / Other State
-- Options) and internal edit-nav links are NOT footer chrome, so they're excluded.
classified as (
    select
        session_key,
        event_date_parsed,
        case
            when event_name = 'screener_social_click' then 'social'
            when event_name = 'screener_feedback_click' then 'feedback_share'
            else 'nav'
        end as element_group,
        case
            when event_name = 'screener_logo_click'
                then concat('Logo (', coalesce(location, 'unknown'), ')')
            when event_name = 'screener_language_changed' then 'Changed Language'
            when event_name = 'screener_social_click' then initcap(social_network)
            when event_name = 'screener_feedback_click' and feedback_channel = 'survey' then 'Report a Bug'
            when event_name = 'screener_feedback_click' and feedback_channel = 'email' then 'Contact Us'
            when link_name in ('About Us', 'Privacy Policy', 'Terms and Conditions') then link_name
            else null  -- in-step content / edit-nav link_clicks: not footer chrome
        end as element,
        row_state
    from ui_events

    union all

    select session_key, event_date_parsed, 'feedback_share' as element_group, 'Share' as element, row_state
    from shares
),

-- Resolve state at the SESSION level: a chrome click can happen before the white
-- label is known (null row_state), so take the session's best resolved state
-- across all its rows. Done here, before the per-element grouping, so an
-- element whose own row had no state still inherits the session's state.
with_session_state as (
    select
        session_key,
        event_date_parsed,
        element_group,
        element,
        max(row_state) over (partition by session_key) as screener_state
    from classified
)

select
    element_group,
    element,
    session_key,
    max(event_date_parsed) as event_date_parsed,
    max(screener_state) as screener_state,

    current_timestamp() as updated_at

from with_session_state
where element is not null
group by element_group, element, session_key
