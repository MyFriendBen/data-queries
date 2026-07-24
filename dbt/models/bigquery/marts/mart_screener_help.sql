{{
  config(
    materialized='table'
  )
}}

-- Screener help interactions - daily grain by state.
-- Three help signals share one mart via a `metric` discriminator:
--   1. help_click  — inline "?" tooltip opens, keyed by help_topic + step
--                    (the per-step confusion metric). dimension = help_topic,
--                    with screener_step_label for the step drill-down.
--   2. get_help_click — results-page "More Help / 211" CTA, keyed by location.
--                    dimension = location; screener_step_label is null.
--   3. more_help_resource_click — "Visit Website" links on the more-help page's
--                    "Other Resources Near You" list. dimension = resource label
--                    (or "Resource #<ordinal>"); screener_step_label is null.
-- Deduped by screener_uid for distinct-screening counts. help_click can fire
-- pre-uid on early steps, so uid may be null there — total_clicks is the robust
-- volume measure; distinct_screenings is a floor.

with help_click as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        'help_click' as metric,
        coalesce(help_topic, '(unspecified)') as dimension,
        screener_step_name
    from {{ ref('stg_ga_screener_help') }}
    where event_name = 'screener_help_click'
),

get_help_click as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        'get_help_click' as metric,
        coalesce(location, '(unspecified)') as dimension,
        cast(null as string) as screener_step_name
    from {{ ref('stg_ga_screener_help') }}
    where event_name = 'screener_get_help_click'
),

-- More-help page "Visit Website" resource clicks (FE #2163). KEYED ON url: the FE
-- does not send resource_name for CO (the more_help_options white-label config has
-- no label set), and resource_index is page-position (not stable across variants),
-- so url is the only stable per-resource identifier. dimension precedence:
--   1. resource_name (if the config ever sets a label — future-proof)
--   2. a friendly name mapped from the url below (dbt owns the url->label map,
--      same pattern as the program / error field-label mappings)
--   3. the raw url as last resort (so a new resource never vanishes; add a line
--      to the map when it appears).
more_help_resource_click as (
    select
        event_date,
        event_date_parsed,
        screener_state,
        screener_uid,
        'more_help_resource_click' as metric,
        coalesce(
            resource_name,
            case
                when url like '%211colorado.org%' then '2-1-1 Colorado'
                when url like '%coloradocrisisservices.org%' then 'Colorado Crisis Services'
                when url like '%hungerfreecolorado.org%' then 'Hunger Free Colorado'
                -- add url->label lines here as new more-help resources appear; an
                -- unmapped url falls through to the raw url below (visible on the card,
                -- so it's noticeable — but not auto-flagged; this tree has no dbt tests).
                else nullif(url, '')
            end,
            'Resource #' || cast(resource_index as string),
            '(unspecified)'
        ) as dimension,
        cast(null as string) as screener_step_name
    from {{ ref('stg_ga_screener_help') }}
    where event_name = 'screener_more_help_resource_click'
),

combined as (
    select * from help_click
    union all
    select * from get_help_click
    union all
    select * from more_help_resource_click
)

select
    event_date,
    event_date_parsed,
    screener_state,
    metric,
    dimension,

    -- Human-readable step label for the help_click drill-down (null for the 211
    -- CTA, which isn't step-scoped — a null slug returns null from the macro).
    -- Shared screener_step_label macro (single source of truth).
    {{ screener_step_label('screener_step_name') }} as screener_step_label,

    count(*) as total_clicks,
    count(distinct screener_uid) as distinct_screenings,

    current_timestamp() as updated_at

from combined
group by event_date, event_date_parsed, screener_state, metric, dimension, screener_step_label
order by event_date desc, screener_state, metric, total_clicks desc
