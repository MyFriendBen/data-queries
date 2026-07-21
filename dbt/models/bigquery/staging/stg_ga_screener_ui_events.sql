{{
  config(
    materialized='view'
  )
}}

-- Miscellaneous screener UI events not covered by the funnel / program / share /
-- resource staging models. One row per raw event, params flattened. Downstream
-- marts filter by event_name:
--   screener_confirmation_edit  — a confirmation-page section was edited (section)
--   screener_signup_completed   — sign-up submitted (sms_consent, email_consent)
--   screener_filter_engaged     — results filter used (filter_type; only
--                                 'citizenship' today — the chosen option is never
--                                 sent, it's PII)
--   screener_nps_score_submitted / _reason_submitted / _reason_skipped — NPS
--   screener_feedback_click     — feedback CTA (channel: survey | email)
--   screener_link_click         — a content/footer link (link_name, step)
--   screener_logo_click         — logo (location: header | footer)
--   screener_language_changed   — header language switch (as a boolean "a switch
--                                 happened" signal; the by-language distribution is
--                                 modeled separately from stg_ga_screener_step_interactions)
--   screener_social_click       — footer social icon (social_network: linkedin |
--                                 facebook | instagram)
-- screener_state / screener_uid arrive as params.

select
    event_date,
    event_timestamp,
    parse_date('%Y%m%d', event_date) as event_date_parsed,
    event_name,

    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index,

    max(case when ep.key = 'ga_session_id' then ep.value.int_value end) as ga_session_id,
    max(case when ep.key = 'screener_state' then ep.value.string_value end) as screener_state,
    max(case when ep.key = 'screener_uid' then ep.value.string_value end) as screener_uid,
    max(case when ep.key = 'screener_step_name' then ep.value.string_value end) as screener_step_name,

    -- event-specific params
    max(case when ep.key = 'section' then ep.value.string_value end) as section,
    max(case when ep.key = 'filter_type' then ep.value.string_value end) as filter_type,
    max(case when ep.key = 'sms_consent' then ep.value.string_value end) as sms_consent,
    max(case when ep.key = 'email_consent' then ep.value.string_value end) as email_consent,
    max(case when ep.key = 'score'
        then coalesce(ep.value.int_value, safe_cast(ep.value.string_value as int64))
    end) as nps_score,
    max(case when ep.key = 'channel' then ep.value.string_value end) as feedback_channel,
    max(case when ep.key = 'link_name' then ep.value.string_value end) as link_name,
    max(case when ep.key = 'location' then ep.value.string_value end) as location,
    max(case when ep.key = 'network' then ep.value.string_value end) as social_network

from {{ source('google_analytics', 'events_*') }}
cross join unnest(event_params) as ep

where event_name in (
    'screener_confirmation_edit',
    'screener_signup_completed',
    'screener_filter_engaged',
    'screener_nps_score_submitted',
    'screener_nps_reason_submitted',
    'screener_nps_reason_skipped',
    'screener_feedback_click',
    'screener_link_click',
    'screener_logo_click',
    'screener_language_changed',
    'screener_social_click'
)

group by
    event_date,
    event_timestamp,
    event_name,
    user_pseudo_id,
    user_id,
    event_bundle_sequence_id,
    batch_event_index
