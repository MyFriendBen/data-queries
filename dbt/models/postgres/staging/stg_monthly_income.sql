{{
  config(
    materialized='view',
    description='Monthly income calculated per screener'
  )
}}

SELECT
    screen_id,
    sum(CASE
        WHEN frequency = 'yearly' THEN amount / 12
        WHEN frequency = 'monthly' THEN amount
        WHEN frequency = 'weekly' THEN (amount * 52) / 12
        WHEN frequency = 'hourly' THEN (amount * 40 * 52) / 12
        WHEN frequency = 'biweekly' THEN (amount * 26) / 12
        WHEN frequency = 'semimonthly' THEN (amount * 24) / 12
    END) AS monthly_income
FROM {{ source('django_apps', 'screener_incomestream') }}
GROUP BY screen_id
