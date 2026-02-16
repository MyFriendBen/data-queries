{{ config(
    materialized='view',
    description='Staging model for income stream records with raw data from Django'
) }}

SELECT
    *
FROM {{ source('django_apps', 'screener_incomestream') }} si
