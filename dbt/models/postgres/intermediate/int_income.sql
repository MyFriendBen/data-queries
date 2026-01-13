{{ config(
    materialized='view',
    description='Intermediate model for income data with enriched screener information - joins with data view for consistency'
) }}

SELECT
    si.id,
    si.screen_id,
    si.type,
    si.amount,
    si.frequency,
    d.id as screener_id,
    d.submission_date,
    d.white_label_id
FROM {{ ref('stg_income') }} si
INNER JOIN public.data d ON si.screen_id = d.id
