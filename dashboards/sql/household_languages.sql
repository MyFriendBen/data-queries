WITH filtered AS (
    SELECT request_language_code
    FROM analytics.mart_screener_data
    WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]
),
total AS (
    SELECT count(*) AS n FROM filtered
)
SELECT
    request_language_code AS "Language",
    count(*)::float / NULLIF(max(t.n), 0) AS "% of Total"
FROM filtered, total t
GROUP BY request_language_code
ORDER BY count(*) DESC
