WITH filtered AS (
    SELECT * FROM analytics.mart_screener_data
    WHERE submission_date >= CURRENT_DATE - INTERVAL '30 days'
    [[AND {{partner}}]]
),
ranked AS (
    SELECT partner, count(*) AS screeners
    FROM filtered
    GROUP BY partner
    ORDER BY screeners DESC
    LIMIT 10
),
total_screeners AS (
    SELECT count(*) AS total FROM filtered
)
SELECT "Top 10 Partners", "#", "%" FROM (
    SELECT 0 AS sort_order, partner AS "Top 10 Partners", screeners AS "#",
           screeners::float / NULLIF(t.total, 0) AS "%"
    FROM ranked, total_screeners t
    UNION ALL
    SELECT 1, 'Total', sum(screeners),
           sum(screeners)::float / NULLIF(max(t.total), 0)
    FROM ranked, total_screeners t
) combined
ORDER BY sort_order, "#" DESC
