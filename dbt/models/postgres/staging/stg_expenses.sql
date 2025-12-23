{{
  config(
    materialized='view',
    description='Expenses data'
  )
}}

select
    d.id as screener_id
    ,d.submission_date::date as submission_date
    ,d.white_label_id
    ,se.*
from {{ source('django_apps', 'screener_expense') }} se
left join {{ ref('stg_screens') }} d ON se.screen_id = d.id
where se.screen_id in(d.id)