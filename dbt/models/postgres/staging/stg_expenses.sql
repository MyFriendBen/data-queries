{{
  config(
    materialized='view',
    description='Expenses data'
  )
}}

select *
from {{ source('django_apps', 'screener_expense') }}