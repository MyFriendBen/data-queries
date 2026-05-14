WITH filtered AS (
    SELECT hm.age
    FROM analytics.mart_householdmembers AS hm
    WHERE hm.relationship = 'headOfHousehold'
      AND EXISTS (
        SELECT 1
        FROM analytics.mart_screener_data AS s
        WHERE s.partner IS NOT DISTINCT FROM hm.partner
          AND s.county IS NOT DISTINCT FROM hm.county
          AND 1 = 1
          [[AND {{submission_date}}]]
          [[AND {{partner}}]]
          [[AND {{county}}]]
      )
),
total AS (
    SELECT count(*) AS n FROM filtered WHERE age IS NOT NULL
),
age_bins AS (
    SELECT
        CASE
            WHEN age BETWEEN 0 AND 18 THEN '0-18'
            WHEN age BETWEEN 19 AND 24 THEN '19-24'
            WHEN age BETWEEN 25 AND 44 THEN '25-44'
            WHEN age BETWEEN 45 AND 64 THEN '45-64'
            WHEN age >= 65 THEN '65+'
        END AS age_group,
        CASE
            WHEN age BETWEEN 0 AND 18 THEN 1
            WHEN age BETWEEN 19 AND 24 THEN 2
            WHEN age BETWEEN 25 AND 44 THEN 3
            WHEN age BETWEEN 45 AND 64 THEN 4
            WHEN age >= 65 THEN 5
        END AS sort_order
    FROM filtered
    WHERE age IS NOT NULL
)
SELECT age_group AS "Age Group",
       count(*)::float / NULLIF(max(t.n), 0) AS "% of Total"
FROM age_bins, total AS t
GROUP BY age_group, sort_order
ORDER BY sort_order
