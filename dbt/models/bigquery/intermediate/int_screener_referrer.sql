{{
  config(
    materialized='table'
  )
}}

-- Referrer lookup: which partner referrer each screener and each GA session
-- belongs to. The screener event marts join it (join_screener_referrer macro)
-- to carry a screener_referrer column, which referrer dashboards filter on.
-- A table, not the layer's default view: ~17 marts join it per run, and as a
-- view each join would re-read the raw GA export.
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
--   * a session takes the referrer tagged in it or of any screener it touched,
--     which covers later visits that resumed a referred screener. A session
--     that touched screeners from two different referrers is left out, so none
--     of its activity is credited to either partner.
-- Sessions that never reach a form step carry no referrer and are absent here,
-- as are sessions with a null user_pseudo_id or ga_session_id (their key can't
-- tell one visit from another).
--
-- Forward-only: rows exist only for events after the GTM tag started forwarding.

with form_events as (
    select
        to_json_string(struct(user_pseudo_id, ga_session_id)) as session_key,
        user_pseudo_id is not null and ga_session_id is not null as has_session,
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

session_candidates as (
    select session_key, screener_referrer
    from form_events
    where has_session
        and screener_referrer is not null

    union distinct

    select f.session_key, s.screener_referrer
    from form_events as f
    inner join by_screener as s
        on f.screener_uid = s.screener_uid
    where f.has_session
),

by_session as (
    select
        session_key,
        any_value(screener_referrer) as screener_referrer
    from session_candidates
    group by session_key
    -- Qualified: bare, BigQuery resolves it to the any_value alias above.
    having count(distinct session_candidates.screener_referrer) = 1
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
