{{
  config(
    materialized='table'
  )
}}

-- Referrer lookup: which partner referrer each screener and each GA session
-- belongs to, so referrer dashboards can scope the GA4 event marts.
--
-- One row per key:
--   key_type = 'screener' -> key is a screener_uid    (joins screening-grain marts)
--   key_type = 'session'  -> key is a session_key     (joins session-grain marts),
--                            to_json_string(struct(user_pseudo_id, ga_session_id)),
--                            the same key mart_screener_step_facts and
--                            mart_screener_footer_engagement use.
--
-- The app sends screener_referrer on every event, but GTM forwards it on
-- screener_form_step only. A screener's referrer can't change (the app locks it
-- from the entry URL), so one tagged step is enough:
--   * a screener takes the referrer of its earliest tagged step;
--   * a session takes the referrer tagged in it, or else the referrer of any
--     screener it touched, which covers later visits that resumed a referred
--     screener.
-- Sessions that never reach a form step carry no referrer and are absent here.
--
-- Forward-only: rows exist only for events after the GTM tag started forwarding.

with form_events as (
    select
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        screener_uid,
        nullif(trim(screener_referrer), '') as screener_referrer,
        event_timestamp
    from {{ ref('stg_ga_screener_form_funnel') }}
),

by_screener as (
    select
        screener_uid,
        array_agg(screener_referrer order by event_timestamp limit 1)[offset(0)] as screener_referrer
    from form_events
    where screener_uid is not null
        and screener_referrer is not null
    group by screener_uid
),

by_session as (
    select
        f.session_key,
        coalesce(
            array_agg(f.screener_referrer ignore nulls order by f.event_timestamp limit 1)[safe_offset(0)],
            array_agg(s.screener_referrer ignore nulls order by f.event_timestamp limit 1)[safe_offset(0)]
        ) as screener_referrer
    from form_events as f
    left join by_screener as s
        on f.screener_uid = s.screener_uid
    group by f.session_key
)

select
    'screener' as key_type,
    screener_uid as key,
    screener_referrer,
    current_timestamp() as updated_at
from by_screener

union all

select
    'session' as key_type,
    session_key as key,
    screener_referrer,
    current_timestamp() as updated_at
from by_session
where screener_referrer is not null
