{{ config(
    materialized='view',
    description='Intermediate model for income data with enriched screener information - joins with int_complete_screener_data for consistency'
) }}

SELECT
    si.*,
    d.id AS screener_id,
    d.submission_date,
    d.white_label_id
FROM {{ ref('stg_income') }} AS si
INNER JOIN {{ ref('int_complete_screener_data') }} AS d ON si.screen_id = d.id
