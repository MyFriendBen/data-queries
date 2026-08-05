{{
  config(
    materialized='table'
  )
}}

-- Results-page revisits per SCREENING — how many times each screening loaded its
-- results page. Powers the "how many screenings viewed results once vs. multiple
-- times" distribution on the Results tab.
--
-- Grain: one row per screener_uid (a screening). results_load_count is the
-- LIFETIME number of screener_results_loaded events for that uid — a revisit
-- count is inherently a per-screening lifetime property, not a daily one.
--
-- event_date_parsed is the FIRST results-load date (when the screening first saw
-- results), so a dashboard date filter reads as "screenings first seen in this
-- window" — the natural cohort for a revisit distribution. is_cesn / state carried
-- for scope filtering, consistent with the other results marts.
--
-- screener_uid is guaranteed present here: results events fire post step 3, after
-- the screening uuid exists. Rows without a uid (shouldn't occur) are dropped so
-- they can't collapse into a bogus single bucket.

with loads as (
    select
        screener_uid,
        event_date_parsed,
        event_timestamp,
        screener_state,
        is_cesn
    from {{ ref('stg_ga_screener_results_outcomes') }}
    where event_name = 'screener_results_loaded'
        and screener_uid is not null
)

select
    screener_uid,
    count(*) as results_load_count,
    min(event_date_parsed) as event_date_parsed,
    -- Attribute the screening to the earliest event whose state is a known
    -- lowercase code — a screening's events can carry the legacy display-name
    -- format (e.g. "Colorado") that the dashboard state IN-list doesn't
    -- recognize. Derived the same way as mart_screener_screening_funnel so the
    -- two agree on which screenings pass the state filter.
    array_agg(
        if(screener_state in ('co','nc','tx','wa','il','ma','cesn'), screener_state, null)
        ignore nulls order by event_timestamp limit 1
    )[safe_offset(0)] as screener_state,
    max(is_cesn) as is_cesn,

    current_timestamp() as updated_at

from loads
group by screener_uid
