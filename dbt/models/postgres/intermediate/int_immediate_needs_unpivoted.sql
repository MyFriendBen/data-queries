{{ config(
    materialized='view',
    description='Intermediate model that unpivots immediate needs counts into benefit-level rows'
) }}

SELECT
    t.benefit,
    t.count,
    inb.white_label_id,
    inb.partner
FROM {{ ref('int_immediate_needs') }} AS inb
CROSS JOIN LATERAL unnest(
    ARRAY[
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
    ],
    ARRAY[
        inb.needs_baby_supplies,
        inb.needs_child_dev_help,
        inb.needs_food,
        inb.needs_funeral_help,
        inb.needs_housing_help,
        inb.needs_mental_health_help,
        inb.needs_family_planning_help,
        inb.needs_dental_care,
        inb.needs_job_resources,
        inb.needs_legal_services,
        inb.needs_college_savings,
        inb.needs_veteran_services
    ]
) AS t (benefit, count)
