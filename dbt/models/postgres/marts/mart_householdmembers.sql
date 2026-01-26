{{ config(
    materialized='table',
    description='Mart model reproducing data_householdmembers with row-level security',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

select *
from {{ ref('int_householdmembers') }}
order by white_label_id, screener_id, id
