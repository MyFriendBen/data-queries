{{
  config(
    materialized='table'
  )
}}

-- Sign-up consent opt-in — of the screenings that completed sign-up, how many
-- opted into SMS and email contact. Daily grain by state. One screener_uid can
-- complete sign-up once, so signups is distinct screenings; sms_opt_in /
-- email_opt_in are distinct screenings that consented to each channel.

with signups as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        -- FE emits these as the STRINGS 'true'/'false' (verified against raw GA:
        -- string_value populated, int_value empty), so a string compare is correct.
        sms_consent = 'true' as sms_opt_in,
        email_consent = 'true' as email_opt_in
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name = 'screener_signup_completed'
        and screener_uid is not null
)

select
    event_date,
    event_date_parsed,
    screener_state,

    count(distinct screener_uid) as signups,
    count(distinct if(sms_opt_in, screener_uid, null)) as sms_opt_ins,
    count(distinct if(email_opt_in, screener_uid, null)) as email_opt_ins,

    current_timestamp() as updated_at

from signups
group by event_date, event_date_parsed, screener_state
order by event_date desc, screener_state
