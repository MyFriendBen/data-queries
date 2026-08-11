{{
  config(
    materialized='view',
    description='User contact info from the Django User model, limited to users who consented to follow-up contact. Anonymized users (email/cell nulled) are excluded.'
  )
}}

SELECT
    u.id AS user_id,
    u.first_name,
    u.last_name,
    u.email,
    u.cell,
    u.language_code,
    u.tcpa_consent,
    u.send_offers,
    u.send_updates
FROM {{ source('django_apps', 'authentication_user') }} AS u
WHERE
    -- Only users with at least one way to reach them
    (u.email IS NOT NULL OR u.cell IS NOT NULL)
    -- Only users who opted in to follow-up contact. tcpa_consent covers the
    -- "contact me about my results" checkbox; send_offers/send_updates cover
    -- the newsletter/offers opt-ins.
    AND (
        COALESCE(u.tcpa_consent, FALSE)
        OR u.send_offers
        OR u.send_updates
    )
