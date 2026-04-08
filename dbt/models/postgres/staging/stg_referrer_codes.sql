{{
  config(
    materialized='view',
    description='This model maps referrer codes to partner names. Sources from the Django Referrer model instead of a manually maintained seed file.'
  )
}}

SELECT
  r.referrer_code,
  r.name AS partner,
  r.white_label_id
FROM {{ source('django_apps', 'programs_referrer') }} r
