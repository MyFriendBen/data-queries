WITH totals AS (
    SELECT count(*) as total_count FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]]
)
SELECT
    qb.benefit as "Benefit Name",
    SUM(qb.count) as "# of Screeners",
    SUM(qb.count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_qualified_benefits qb
CROSS JOIN totals t
WHERE 1=1 [[AND {{partner}}]]
GROUP BY qb.benefit
ORDER BY SUM(qb.count) DESC
