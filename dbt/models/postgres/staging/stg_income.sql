{{ config(
    materialized='view',
    description='Staging model for income stream records with raw data from Django'
) }}

SELECT
    si.id,
    si.screen_id,
    si.type,
    si.amount,
    si.frequency
FROM {{ source('django_apps', 'screener_incomestream') }} si
