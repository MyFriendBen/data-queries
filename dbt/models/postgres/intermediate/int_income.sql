{{ config(
    materialized='view',
    description='Intermediate model for income data with enriched screener information - joins with int_complete_screener_data for consistency'
) }}

SELECT
    d.id as screener_id,
    d.submission_date,
    d.white_label_id,
    si.*
FROM {{ ref('stg_income') }} si
INNER JOIN {{ ref('int_complete_screener_data') }} d ON si.screen_id = d.id
