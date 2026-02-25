{{ config(
    materialized='view',
    description='Intermediate model aggregating immediate needs counts by white_label_id and partner'
) }}

SELECT
    white_label_id,
    partner,
    sum(CASE WHEN needs_baby_supplies = TRUE THEN 1 ELSE 0 END) AS needs_baby_supplies,
    sum(CASE WHEN needs_child_dev_help = TRUE THEN 1 ELSE 0 END) AS needs_child_dev_help,
    sum(CASE WHEN needs_food = TRUE THEN 1 ELSE 0 END) AS needs_food,
    sum(CASE WHEN needs_funeral_help = TRUE THEN 1 ELSE 0 END) AS needs_funeral_help,
    sum(CASE WHEN needs_housing_help = TRUE THEN 1 ELSE 0 END) AS needs_housing_help,
    sum(CASE WHEN needs_mental_health_help = TRUE THEN 1 ELSE 0 END) AS needs_mental_health_help,
    sum(CASE WHEN needs_family_planning_help = TRUE THEN 1 ELSE 0 END) AS needs_family_planning_help,
    sum(CASE WHEN needs_dental_care = TRUE THEN 1 ELSE 0 END) AS needs_dental_care,
    sum(CASE WHEN needs_job_resources = TRUE THEN 1 ELSE 0 END) AS needs_job_resources,
    sum(CASE WHEN needs_legal_services = TRUE THEN 1 ELSE 0 END) AS needs_legal_services,
    sum(CASE WHEN needs_college_savings = TRUE THEN 1 ELSE 0 END) AS needs_college_savings,
    sum(CASE WHEN needs_veteran_services = TRUE THEN 1 ELSE 0 END) AS needs_veteran_services
FROM {{ ref('int_complete_screener_data') }}
GROUP BY white_label_id, partner
