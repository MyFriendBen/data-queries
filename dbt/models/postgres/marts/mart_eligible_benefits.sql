{{ config(
    materialized='table',
    description='Mart table of per-program eligibility counts by white_label_id and partner. Tracks programs users qualify for — distinct from mart_previous_benefits which tracks programs users report already having.',
    post_hook="{{ setup_white_label_rls(this.name) }}"
) }}

SELECT *
FROM {{ ref('int_eligible_benefits') }}
