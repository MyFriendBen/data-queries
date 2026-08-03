{{
  config(
    materialized='table'
  )
}}

-- Combined CESN step ladder (slug, label, funnel_rank) from the
-- screener_cesn_combined_ladder macro — the steps common to both the homeowner
-- and renter paths (the two path-exclusive energy steps are omitted). The CESN
-- Form Step Reached card LEFT JOINs this to order and label the rungs (Metabase
-- SQL can't call dbt macros).

select screener_step_name, screener_step_label, funnel_rank
from ({{ screener_cesn_combined_ladder() }})
