{{
  config(
    materialized='table',
    description='Materialized mart for screener analytics - optimized for dashboard performance'
  )
}}

-- Reference the complete intermediate screener data model
-- This materializes all the complex logic as a table for fast dashboard queries
SELECT *
FROM {{ ref('int_complete_screener_data') }}
