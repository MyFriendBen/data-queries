{{
  config(
    materialized='table'
  )
}}

-- CESN two-path step ladder (cesn_path, slug, label, funnel_rank) from the
-- screener_cesn_step_ladder macro. The Metabase homeowner/renter funnel cards
-- LEFT JOIN this per path to order and label the rungs (Metabase SQL can't call
-- dbt macros). One row per (step, path) the step appears on.

select cesn_path, screener_step_name, screener_step_label, funnel_rank
from ({{ screener_cesn_step_ladder() }})
