{{ config(
    materialized='view',
    description='Intermediate model for household members enriched with screener data'
) }}

select
    d.id as screener_id,
    d.white_label_id,
    d.partner,
    d.submission_date,
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
from {{ ref('stg_householdmembers') }} sh
inner join {{ ref('int_complete_screener_data') }} d
    on sh.screen_id = d.id
