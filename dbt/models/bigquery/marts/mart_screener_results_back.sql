{{
  config(
    materialized='table'
  )
}}

-- Results-page "Back to Screener" clicks — distinct screenings that clicked the
-- results-page button to go back and edit the screener (FE #2163 gap #8).
-- DISTINCT from screener_form_back (the in-form step-back button) — this is only
-- the results-page exit-to-edit. Daily grain by state; the card turns it into a
-- "% of results viewers who went back" scalar.
-- screener_uid is present (fires post-results, uid exists); guard just in case.

with backs as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name = 'screener_results_back_to_screener'
        and screener_uid is not null
)

select
    event_date,
    event_date_parsed,
    screener_state,

    count(distinct screener_uid) as screenings_went_back,
    count(*) as total_clicks,

    current_timestamp() as updated_at

from backs
group by event_date, event_date_parsed, screener_state
order by event_date desc, screener_state
