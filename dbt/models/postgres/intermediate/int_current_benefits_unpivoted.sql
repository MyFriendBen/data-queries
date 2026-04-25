{{ config(
    materialized='view',
    description='Pass-through view — int_current_benefits is now already narrow (one row per benefit). Kept for backward compatibility so mart_current_benefits needs no changes.'
) }}

SELECT *
FROM {{ ref('int_current_benefits') }}
