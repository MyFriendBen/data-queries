{{
  config(
    materialized='table',
    description='Materialized mart for screener analytics - optimized for dashboard performance',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

-- Reference the complete intermediate screener data model
-- This materializes all the complex logic as a table for fast dashboard queries
SELECT *
FROM {{ ref('int_complete_screener_data') }}
