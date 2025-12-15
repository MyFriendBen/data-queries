{{
  config(
    materialized='view',
    description='Latest eligibility snapshot per screen'
  )
}}

with snapshots_count as (
    select
        screen_id,
        count(distinct id) as snapshots
    from {{ source('django_apps', 'screener_eligibilitysnapshot') }}
    group by screen_id
)

select
    sc.screen_id,
    (select id
        from {{ source('django_apps', 'screener_eligibilitysnapshot') }} sel
        where sel.screen_id = sc.screen_id
        order by sel.submission_date desc
        limit 1) as latest_snapshot_id,
    sc.snapshots
from snapshots_count sc