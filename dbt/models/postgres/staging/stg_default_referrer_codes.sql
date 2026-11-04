{{
  config(
    materialized='view',
    description='Referrer codes on the _default white label. Used as a fallback when a screen on a state white label has no referrer row of its own (multi-state referrers such as propel).'
  )
}}

SELECT
    r.referrer_code,
    r.partner
FROM {{ ref('stg_referrer_codes') }} r
INNER JOIN {{ source('django_apps', 'screener_whitelabel') }} wl
    ON r.white_label_id = wl.id
WHERE wl.code = '_default'
