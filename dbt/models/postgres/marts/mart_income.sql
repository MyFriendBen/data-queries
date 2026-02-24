{{ config(
    materialized='table',
    description='Mart model for income data with row-level security by white_label_id'
    
) }}

SELECT
    *
FROM {{ ref('int_income') }}
ORDER BY white_label_id, screener_id, id
