{{
  config(
    materialized='table',
    description='Materialized mart for expense'
  )
}}


SELECT *
FROM {{ ref('stg_expenses') }}