{{
  config(
    materialized='table'
  )
}}

-- Results-page filter engagement — distinct screenings that used a results filter.
-- Only the citizenship filter exists today, and the chosen OPTION is never sent
-- (it's PII); this is purely a "did they engage the filter" signal. Daily grain by
-- state + filter_type so it generalizes if more filter types are added later.

with engaged as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        coalesce(filter_type, '(unknown)') as filter_type
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name = 'screener_filter_engaged'
        and screener_uid is not null
)

select
    event_date,
    event_date_parsed,
    screener_state,
    filter_type,

    count(distinct screener_uid) as screenings_engaged,
    count(*) as total_engagements,

    current_timestamp() as updated_at

from engaged
group by event_date, event_date_parsed, screener_state, filter_type
order by event_date desc, screener_state
