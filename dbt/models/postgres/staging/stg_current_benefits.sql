{{
  config(
    materialized='view',
    description='One row per screen × benefit: joins screener_current_benefits to programs_program to resolve the abbreviated program name'
  )
}}

SELECT
    cb.screen_id,
    cb.program_id,
    pp.name_abbreviated AS benefit_name
FROM {{ source('django_apps', 'screener_current_benefits') }} AS cb
INNER JOIN {{ source('django_apps', 'programs_program') }} AS pp
    ON cb.program_id = pp.id
