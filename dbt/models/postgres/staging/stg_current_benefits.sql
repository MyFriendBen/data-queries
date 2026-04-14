{{
  config(
    materialized='view',
    description='One row per screen × benefit: thin representation of screener_current_benefits'
  )
}}

SELECT
    screen_id,
    program_id
FROM {{ source('django_apps', 'screener_current_benefits') }}
