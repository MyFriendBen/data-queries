{{
  config(
    materialized='table'
  )
}}

-- NPS + feedback engagement. Daily grain by state + score. One row per
-- (date, state, score) for the score DISTRIBUTION card; the reason/feedback
-- counts ride at the same grain (they're small and let a card show response
-- follow-through). nps_category buckets the 0-10 score the standard way
-- (Detractor 0-6 / Passive 7-8 / Promoter 9-10) for an optional rollup.

with nps as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        event_name,
        nps_score
    from {{ ref('stg_ga_screener_ui_events') }}
    where event_name in (
        'screener_nps_score_submitted',
        'screener_nps_reason_submitted',
        'screener_nps_reason_skipped',
        'screener_feedback_click'
    )
)

select
    event_date,
    event_date_parsed,
    screener_state,
    nps_score,

    case
        when nps_score is null then null
        when nps_score <= 6 then 'Detractor'
        when nps_score <= 8 then 'Passive'
        else 'Promoter'
    end as nps_category,

    countif(event_name = 'screener_nps_score_submitted') as scores_submitted,
    countif(event_name = 'screener_nps_reason_submitted') as reasons_submitted,
    countif(event_name = 'screener_nps_reason_skipped') as reasons_skipped,
    countif(event_name = 'screener_feedback_click') as feedback_clicks,

    current_timestamp() as updated_at

from nps
group by event_date, event_date_parsed, screener_state, nps_score, nps_category
order by event_date desc, screener_state, nps_score
