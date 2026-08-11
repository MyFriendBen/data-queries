{{
  config(
    materialized='table',
    description='Contact info for completed screeners whose user consented to follow-up. One row per completed screen with a reachable, consenting user. PII: expose only in locked-down partner collections.',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

-- PRIVACY NOTE: This mart contains PII (names, emails, phone numbers).
-- It exists to support partner follow-up (e.g. CPAL application support,
-- MFB-1198). It is limited to users who opted in to contact (see
-- stg_user_contact) and is protected by white-label RLS like every other
-- mart. Metabase cards built on it must live in collections restricted to
-- the relevant partner's viewer group.

SELECT
    ss.id AS screen_id,
    ss.white_label_id,
    ss.submission_date AS submission_timestamp,
    ss.submission_date::date AS submission_date,
    ss.referrer_code,
    COALESCE(rc.partner, 'No Partner') AS partner,
    COALESCE(NULLIF(TRIM(ss.county), ''), 'Unspecified') AS county,
    ss.zipcode,
    uc.first_name,
    uc.last_name,
    uc.email,
    uc.cell AS phone,
    uc.language_code AS preferred_language,
    uc.tcpa_consent,
    uc.send_offers,
    uc.send_updates
FROM {{ source('django_apps', 'screener_screen') }} AS ss
INNER JOIN {{ ref('stg_user_contact') }} AS uc ON ss.user_id = uc.user_id
LEFT JOIN {{ ref('stg_referrer_codes') }} AS rc
    ON ss.referrer_code = rc.referrer_code AND ss.white_label_id = rc.white_label_id
WHERE
    ss.completed = TRUE
    AND ss.is_test = FALSE
    AND ss.is_test_data = FALSE
