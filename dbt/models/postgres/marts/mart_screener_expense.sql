{{
  config(
    materialized='table',
    description='Materialized mart for expenses data',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

select
    d.id as screener_id
    ,d.submission_date::date as submission_date
    ,d.white_label_id
    ,se.*
from {{ ref('stg_expenses') }} se
inner join {{ ref('int_complete_screener_data') }} d ON se.screen_id = d.id