{{
  config(
    materialized='view',
    description='Monthly expenses calculated per screener'
  )
}}

select
    screen_id,
    sum(case
       when frequency = 'yearly' then amount / 12
       when frequency = 'monthly' then amount
       when frequency = 'weekly' then (amount * 52) / 12
       when frequency = 'hourly' then (amount * 40 * 52) / 12
       when frequency = 'biweekly' then (amount * 26) / 12
       when frequency = 'semimonthly' then (amount * 24) / 12
   end) as monthly_expenses
from {{ source('django_apps', 'screener_expense') }}
group by screen_id
