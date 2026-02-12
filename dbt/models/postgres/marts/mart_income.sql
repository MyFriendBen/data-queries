{{ config(
    materialized='table',
    description='Mart model for income data with row-level security by white_label_id',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

SELECT
    ii.*
FROM {{ ref('int_income') }} ii
ORDER BY ii.white_label_id, ii.screener_id, ii.id
