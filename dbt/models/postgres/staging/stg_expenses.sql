{{
  config(
    materialized='view',
    description='Expenses data'
  )
}}

SELECT *
FROM {{ source('django_apps', 'screener_expense') }}
