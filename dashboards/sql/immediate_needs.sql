WITH totals AS (SELECT count(*) as total_count FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]])
SELECT
    benefit as "Need Category",
    SUM(count) as "# of Screeners",
    SUM(count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_immediate_needs
CROSS JOIN totals t
WHERE 1=1 [[AND {{partner}}]]
GROUP BY benefit
ORDER BY SUM(count) DESC
