WITH filtered AS (
    SELECT request_language_code
    FROM analytics.mart_screener_data
    WHERE 1 = 1[[AND {{submission_date}}]][[AND {{partner}}]][[AND {{county}}]][[AND {{utm_campaign}}]][[AND {{utm_medium}}]][[AND {{utm_source}}]]
),

total AS (
    SELECT count(*) AS n FROM filtered
)

SELECT
    request_language_code AS "Language",
    count(*)::FLOAT / nullif(max(t.n), 0) AS "% of Total"
FROM filtered, total t
GROUP BY request_language_code
ORDER BY count(*) DESC
