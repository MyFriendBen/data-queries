-- # This query will create an immediate_needs table #
-- This table is used as a source for Looker Studio dashboards

create materialized view
    data_immediate_needs as

with base as (
    select
        white_label_id
        ,partner
        ,sum(case when needs_baby_supplies = true then 1 else 0 end)                     as needs_baby_supplies
        ,sum(case when needs_child_dev_help = true then 1 else 0 end)                     as needs_child_dev_help
        ,sum(case when needs_food = true then 1 else 0 end)                     as needs_food
        ,sum(case when needs_funeral_help = true then 1 else 0 end)                     as needs_funeral_help
        ,sum(case when needs_housing_help = true then 1 else 0 end)                     as needs_housing_help
        ,sum(case when needs_mental_health_help = true then 1 else 0 end)                     as needs_mental_health_help
        ,sum(case when needs_family_planning_help = true then 1 else 0 end)                     as needs_family_planning_help
        ,sum(case when needs_dental_care = true then 1 else 0 end)                     as needs_dental_care
        ,sum(case when needs_job_resources = true then 1 else 0 end)                     as needs_job_resources
        ,sum(case when needs_legal_services = true then 1 else 0 end)                     as needs_legal_services
        ,sum(case when needs_college_savings = true then 1 else 0 end)                     as needs_college_savings
        ,sum(case when needs_veteran_services = true then 1 else 0 end)                     as needs_veteran_services
    from data
    group by white_label_id, partner
    )

select
    unnest(array [
        'Baby Supplies'
        ,'Child Development'
        ,'Food'
        ,'Funeral'
        ,'Housing'
        ,'Mental Health'
        ,'Family Planning'
        ,'Dental Care'
        ,'Job Resources'
        ,'Legal Services'
        ,'College Savings'
        ,'Veteran Services'
        ])  as Benefit
    ,unnest(array [
        needs_baby_supplies
        ,needs_child_dev_help
        ,needs_food
        ,needs_funeral_help
        ,needs_housing_help
        ,needs_mental_health_help
        ,needs_family_planning_help
        ,needs_dental_care
        ,needs_job_resources
        ,needs_legal_services
        ,needs_college_savings
        ,needs_veteran_services
        ]) as Count
    ,white_label_id
    ,partner
from base;
