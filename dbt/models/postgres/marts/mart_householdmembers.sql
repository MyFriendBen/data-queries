{{ config(
    materialized='table',
    description='Mart model reproducing data_householdmembers with row-level security',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

SELECT *
FROM {{ ref('int_householdmembers') }}
ORDER BY white_label_id, screener_id, id
