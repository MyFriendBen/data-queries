-- # This query will create an immediate_needs table #
-- This table is used as a source for Looker Studio dashboards

CREATE MATERIALIZED VIEW
data_immediate_needs AS

WITH base AS (
    SELECT
        white_label_id,
        partner,
        sum(CASE WHEN needs_baby_supplies = true THEN 1 ELSE 0 END) AS needs_baby_supplies,
        sum(CASE WHEN needs_child_dev_help = true THEN 1 ELSE 0 END) AS needs_child_dev_help,
        sum(CASE WHEN needs_food = true THEN 1 ELSE 0 END) AS needs_food,
        sum(CASE WHEN needs_funeral_help = true THEN 1 ELSE 0 END) AS needs_funeral_help,
        sum(CASE WHEN needs_housing_help = true THEN 1 ELSE 0 END) AS needs_housing_help,
        sum(CASE WHEN needs_mental_health_help = true THEN 1 ELSE 0 END) AS needs_mental_health_help,
        sum(CASE WHEN needs_family_planning_help = true THEN 1 ELSE 0 END) AS needs_family_planning_help,
        sum(CASE WHEN needs_dental_care = true THEN 1 ELSE 0 END) AS needs_dental_care,
        sum(CASE WHEN needs_job_resources = true THEN 1 ELSE 0 END) AS needs_job_resources,
        sum(CASE WHEN needs_legal_services = true THEN 1 ELSE 0 END) AS needs_legal_services,
        sum(CASE WHEN needs_college_savings = true THEN 1 ELSE 0 END) AS needs_college_savings,
        sum(CASE WHEN needs_veteran_services = true THEN 1 ELSE 0 END) AS needs_veteran_services
    FROM data
    GROUP BY white_label_id, partner
)

SELECT
    white_label_id,
    partner,
    unnest(ARRAY[
        'Baby Supplies',
        'Child Development',
        'Food',
        'Funeral',
        'Housing',
        'Mental Health',
        'Family Planning',
        'Dental Care',
        'Job Resources',
        'Legal Services',
        'College Savings',
        'Veteran Services'
    ]) AS benefit,
    unnest(ARRAY[
        needs_baby_supplies,
        needs_child_dev_help,
        needs_food,
        needs_funeral_help,
        needs_housing_help,
        needs_mental_health_help,
        needs_family_planning_help,
        needs_dental_care,
        needs_job_resources,
        needs_legal_services,
        needs_college_savings,
        needs_veteran_services
    ]) AS count
FROM base;
