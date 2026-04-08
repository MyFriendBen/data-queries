{{
  config(
    materialized='view',
    description='Referrer codes with partner display names, sourced directly from the Django Referrer model. Partner names are stored inline on each Referrer row.'
  )
}}

SELECT
  r.referrer_code,
  r.name AS partner,
  r.white_label_id
FROM {{ source('django_apps', 'programs_referrer') }} r
