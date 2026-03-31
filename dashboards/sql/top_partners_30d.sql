WITH filtered AS (
    SELECT * FROM analytics.mart_screener_data
    WHERE 1 = 1[[AND {{submission_date}}]][[AND {{partner}}]]
),

ranked AS (
    SELECT
        partner,
        count(*) AS screeners
    FROM filtered
    GROUP BY partner
    ORDER BY screeners DESC
    LIMIT 10
),

total_screeners AS (
    SELECT count(*) AS total FROM filtered
)

SELECT
    "Top 10 Partners",
    "#",
    "%"
FROM (
    SELECT
        0 AS sort_order,
        partner AS "Top 10 Partners",
        screeners AS "#",
        screeners::FLOAT / nullif(t.total, 0) AS "%"
    FROM ranked, total_screeners AS t
    UNION ALL
    SELECT
        1 AS sort_order,
        'Total' AS "Top 10 Partners",
        t.total AS "#",
        CASE WHEN t.total = 0 THEN NULL ELSE 1::FLOAT END AS "%"
    FROM total_screeners AS t
) AS combined
ORDER BY sort_order ASC, "#" DESC
