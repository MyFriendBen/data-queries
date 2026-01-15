{{ config(
    materialized='table',
    description='Mart model reproducing data_householdmembers with row-level security',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

select
    screener_id,
    white_label_id,
    partner,
    submission_date,
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
from {{ ref('int_householdmembers') }}
order by white_label_id, screener_id, id
