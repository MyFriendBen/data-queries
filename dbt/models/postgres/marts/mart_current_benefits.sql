{{ config(
    materialized='table',
    description='Mart model for dashboards with current benefits counts by white_label_id and partner',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

SELECT *
FROM {{ ref('int_current_benefits_unpivoted') }}
