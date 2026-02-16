{{ config(
    materialized='table',
    description='Mart model for income data with row-level security by white_label_id',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

SELECT
    *
FROM {{ ref('int_income') }}
ORDER BY white_label_id, screener_id, id
