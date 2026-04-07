{{
  config(
    materialized='view',
    description='This model maps referrer codes to partner names. Sources from the Django Referrer model instead of a manually maintained seed file.'
  )
}}

SELECT
  r.referrer_code,
  r.name AS partner,
  wl.code AS white_label_code
FROM {{ source('django_apps', 'programs_referrer') }} r
LEFT JOIN {{ source('django_apps', 'screener_whitelabel') }} wl
  ON r.white_label_id = wl.id
