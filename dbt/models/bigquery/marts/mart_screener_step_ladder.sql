{{
  config(
    materialized='table'
  )
}}

-- Published canonical step ladder (slug, label, funnel_rank) from the
-- screener_step_ladder macro. Exists so the Metabase-side step-funnel card can
-- LEFT JOIN the ranked rungs (it can't call dbt macros). Ranked rows (funnel_rank
-- not null) are the funnel ladder in order; the card filters to those.

select screener_step_name, screener_step_label, funnel_rank
from ({{ screener_step_ladder() }})
