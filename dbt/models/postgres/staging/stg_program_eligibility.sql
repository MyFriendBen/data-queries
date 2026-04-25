{{
  config(
    materialized='view',
    description='Program eligibility aggregated by snapshot - one row per eligibility_snapshot_id x name_abbreviated. Dynamic: new programs are included automatically without dbt changes.'
  )
}}

SELECT
    eligibility_snapshot_id,
    name_abbreviated,
    value_type,
    sum(estimated_value) AS annual_value
FROM {{ source('django_apps', 'screener_programeligibilitysnapshot') }}
WHERE eligible = TRUE
GROUP BY eligibility_snapshot_id, name_abbreviated, value_type
