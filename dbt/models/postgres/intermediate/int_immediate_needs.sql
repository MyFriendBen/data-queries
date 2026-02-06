{{ config(
    materialized='view',
    description='Intermediate model aggregating immediate needs counts by white_label_id and partner'
) }}

select
    white_label_id,
    partner,
    sum(case when needs_baby_supplies = true then 1 else 0 end) as needs_baby_supplies,
    sum(case when needs_child_dev_help = true then 1 else 0 end) as needs_child_dev_help,
    sum(case when needs_food = true then 1 else 0 end) as needs_food,
    sum(case when needs_funeral_help = true then 1 else 0 end) as needs_funeral_help,
    sum(case when needs_housing_help = true then 1 else 0 end) as needs_housing_help,
    sum(case when needs_mental_health_help = true then 1 else 0 end) as needs_mental_health_help,
    sum(case when needs_family_planning_help = true then 1 else 0 end) as needs_family_planning_help,
    sum(case when needs_dental_care = true then 1 else 0 end) as needs_dental_care,
    sum(case when needs_job_resources = true then 1 else 0 end) as needs_job_resources,
    sum(case when needs_legal_services = true then 1 else 0 end) as needs_legal_services,
    sum(case when needs_college_savings = true then 1 else 0 end) as needs_college_savings,
    sum(case when needs_veteran_services = true then 1 else 0 end) as needs_veteran_services
from {{ ref('int_complete_screener_data') }}
group by white_label_id, partner
