{{
  config(
    materialized='table'
  )
}}

-- Google Analytics clicked links breakdown - daily grain by state and link domain
-- Powers the Clicked Links bar chart and table on the Google Analytics dashboard tab
-- Shows which external domains users click to from the screener results page

with session_state as (
    -- Get state_code per session from page views
    select
        event_date,
        user_pseudo_id,
        ga_session_id,
        max(state_code) as state_code
    from {{ ref('int_ga4_page_views') }}
    where ga_session_id is not null
    group by event_date, user_pseudo_id, ga_session_id
),

clicks_with_state as (
    select
        c.event_date,
        c.event_date_parsed,
        c.user_pseudo_id,
        c.ga_session_id,
        c.link_url,
        c.link_domain,
        c.is_outbound,
        coalesce(s.state_code, 'unknown') as state_code
    from {{ ref('stg_ga_link_clicks') }} c
    left join session_state s
        on c.event_date = s.event_date
        and c.user_pseudo_id = s.user_pseudo_id
        and c.ga_session_id = s.ga_session_id
    where c.ga_session_id is not null
)

select
    event_date,
    event_date_parsed,
    state_code,
    -- Derive domain from link_url if link_domain is not populated
    coalesce(
        link_domain,
        regexp_extract(link_url, r'[^/]+://([^/]+)')
    ) as link_domain,
    is_outbound,

    count(*) as total_clicks,
    count(distinct ga_session_id) as sessions_with_clicks,
    count(distinct user_pseudo_id) as users_with_clicks,

    current_timestamp() as updated_at

from clicks_with_state
group by event_date, event_date_parsed, state_code, link_domain, is_outbound
order by event_date desc, total_clicks desc
