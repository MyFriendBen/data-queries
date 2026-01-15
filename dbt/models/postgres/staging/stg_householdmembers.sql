{{ config(
    materialized='view',
    description='Staging model for screener household members'
) }}

select
    sh.id,
    sh.age,
    sh.student,
    sh.student_full_time,
    sh.pregnant,
    sh.unemployed,
    sh.worked_in_last_18_mos,
    sh.visually_impaired,
    sh.disabled,
    sh.veteran,
    sh.medicaid,
    sh.disability_medicaid,
    sh.has_income,
    sh.has_expenses,
    sh.screen_id,
    sh.relationship,
    sh.long_term_disability,
    sh.birth_year_month,
    sh.frontend_id,
    sh.is_care_worker
from {{ source('django_apps', 'screener_householdmember') }} sh
