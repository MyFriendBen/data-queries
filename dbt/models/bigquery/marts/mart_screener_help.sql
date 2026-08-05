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
        -- resource_name is a stable translation key; map it to a display label (same
        -- pattern as the form-error field-path map). An unmapped key falls through to
        -- the key, then the url, then the position. Add lines as new keys appear.
        coalesce(
            case resource_name
                when 'moreHelp.resource_name1' then '2-1-1 Colorado'
                when 'moreHelp.resource_name2' then 'Colorado Family Resource Centers'
                when 'moreHelp.coloradoHumanServicesOffices.resourceName' then 'Colorado County Human Services'
                when 'moreHelp.nc_resource_name1' then 'NC 2-1-1'
                else null
            end,
            resource_name,
            nullif(url, ''),
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

    -- Raw step slug (the stable join key for a per-step rate) AND the humanized
    -- label. The help-rate card joins on screener_step_name to the screening-keyed
    -- step-views mart; screener_step_label is the display value. Null for the 211
    -- CTA / more-help clicks, which aren't step-scoped.
    screener_step_name,
    {{ screener_step_label('screener_step_name') }} as screener_step_label,

    count(*) as total_clicks,
    count(distinct screener_uid) as distinct_screenings,

    current_timestamp() as updated_at

from combined
group by event_date, event_date_parsed, screener_state, metric, dimension, screener_step_name
order by event_date desc, screener_state, metric, total_clicks desc
