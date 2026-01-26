{{ config(
    materialized='view',
    description='Intermediate model that unpivots immediate needs counts into benefit-level rows'
) }}

select
    t.benefit as benefit,
    t.count as count,
    inb.white_label_id,
    inb.partner
from {{ ref('int_immediate_needs') }} inb
cross join lateral unnest(
    array[
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
    ],
    array[
        inb.needs_baby_supplies
        ,inb.needs_child_dev_help
        ,inb.needs_food
        ,inb.needs_funeral_help
        ,inb.needs_housing_help
        ,inb.needs_mental_health_help
        ,inb.needs_family_planning_help
        ,inb.needs_dental_care
        ,inb.needs_job_resources
        ,inb.needs_legal_services
        ,inb.needs_college_savings
        ,inb.needs_veteran_services
    ]
) as t(benefit, count)
