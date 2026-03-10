{{
  config(
    materialized='view',
    description='Household age demographics and percentages'
  )
}}

SELECT
    screen_id,
    coalesce(sum(CASE WHEN age <= 17 THEN 1 ELSE 0 END), 0) AS "<18 (#)",
    coalesce(sum(CASE WHEN (age > 17 AND age <= 24) THEN 1 ELSE 0 END), 0) AS "18-24 (#)",
    coalesce(sum(CASE WHEN (age > 24 AND age <= 34) THEN 1 ELSE 0 END), 0) AS "25-34 (#)",
    coalesce(sum(CASE WHEN (age > 34 AND age <= 49) THEN 1 ELSE 0 END), 0) AS "35-49 (#)",
    coalesce(sum(CASE WHEN (age > 49 AND age <= 64) THEN 1 ELSE 0 END), 0) AS "50-64 (#)",
    coalesce(sum(CASE WHEN (age > 64 AND age <= 84) THEN 1 ELSE 0 END), 0) AS "65-84 (#)",
    coalesce(sum(CASE WHEN age > 84 THEN 1 ELSE 0 END), 0) AS ">84 (#)",
    coalesce(round(cast((sum(CASE WHEN age <= 17 THEN 1 ELSE 0 END) / cast(count(*) AS float)) AS numeric), 2), 0)
        AS "<18 (%)",
    coalesce(
        round(
            cast((sum(CASE WHEN (age > 17 AND age <= 24) THEN 1 ELSE 0 END) / cast(count(*) AS float)) AS numeric), 2
        ),
        0
    ) AS "18-24 (%)",
    coalesce(
        round(
            cast((sum(CASE WHEN (age > 24 AND age <= 34) THEN 1 ELSE 0 END) / cast(count(*) AS float)) AS numeric), 2
        ),
        0
    ) AS "25-34 (%)",
    coalesce(
        round(
            cast((sum(CASE WHEN (age > 34 AND age <= 49) THEN 1 ELSE 0 END) / cast(count(*) AS float)) AS numeric), 2
        ),
        0
    ) AS "35-49 (%)",
    coalesce(
        round(
            cast((sum(CASE WHEN (age > 49 AND age <= 64) THEN 1 ELSE 0 END) / cast(count(*) AS float)) AS numeric), 2
        ),
        0
    ) AS "50-64 (%)",
    coalesce(
        round(
            cast((sum(CASE WHEN (age > 64 AND age <= 84) THEN 1 ELSE 0 END) / cast(count(*) AS float)) AS numeric), 2
        ),
        0
    ) AS "65-84 (%)",
    coalesce(round(cast((sum(CASE WHEN age > 84 THEN 1 ELSE 0 END) / cast(count(*) AS float)) AS numeric), 2), 0)
        AS ">84 (%)"
FROM {{ source('django_apps', 'screener_householdmember') }}
GROUP BY screen_id
