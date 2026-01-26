{{ config(
    materialized='view',
    description='Staging model for screener household members'
) }}

select
    id,
    age,
    student,
    student_full_time,
    pregnant,
    unemployed,
    worked_in_last_18_mos,
    visually_impaired,
    disabled,
    veteran,
    medicaid,
    disability_medicaid,
    has_income,
    has_expenses,
    screen_id,
    relationship,
    long_term_disability,
    birth_year_month,
    frontend_id,
    is_care_worker
from {{ source('django_apps', 'screener_householdmember') }} 
