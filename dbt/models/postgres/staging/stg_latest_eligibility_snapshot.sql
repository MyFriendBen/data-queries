{{
  config(
    materialized='view',
    description='Latest eligibility snapshot per screen'
  )
}}

WITH snapshots_count AS (
    SELECT
        screen_id,
        count(DISTINCT id) AS snapshots
    FROM {{ source('django_apps', 'screener_eligibilitysnapshot') }}
    GROUP BY screen_id
)

SELECT
    sc.screen_id,
    (
        SELECT id
        FROM {{ source('django_apps', 'screener_eligibilitysnapshot') }} AS sel
        WHERE sel.screen_id = sc.screen_id
        ORDER BY sel.submission_date DESC
        LIMIT 1
    ) AS latest_snapshot_id,
    sc.snapshots
FROM snapshots_count AS sc
