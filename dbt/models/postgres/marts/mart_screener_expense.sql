{{
  config(
    materialized='table',
    description='Materialized mart for expenses data',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

SELECT
    se.*,
    d.id AS screener_id,
    d.submission_date::date AS submission_date,
    d.white_label_id
FROM {{ ref('stg_expenses') }} AS se
INNER JOIN {{ ref('int_complete_screener_data') }} AS d ON se.screen_id = d.id
