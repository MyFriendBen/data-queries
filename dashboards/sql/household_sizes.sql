WITH filtered AS (
    SELECT household_size
    FROM analytics.mart_screener_data
    WHERE 1=1 [[AND {{partner}}]]
),
total AS (
    SELECT count(*) AS n FROM filtered
)
SELECT
    CASE
        WHEN household_size >= 8 THEN '8+'
        ELSE household_size::text
    END AS "Household Size",
    count(*)::float / NULLIF(max(t.n), 0) AS "% of Total"
FROM filtered, total t
GROUP BY
    CASE WHEN household_size >= 8 THEN '8+' ELSE household_size::text END,
    CASE WHEN household_size >= 8 THEN 8 ELSE household_size END
ORDER BY
    CASE WHEN household_size >= 8 THEN 8 ELSE household_size END
