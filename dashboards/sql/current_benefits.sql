WITH totals AS (SELECT count(*) as total_count FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]])
SELECT
    benefit as "Benefit Name",
    SUM(count) as "# of Screeners",
    SUM(count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_previous_benefits
CROSS JOIN totals t
WHERE 1=1 [[AND {{partner}}]]
GROUP BY benefit
HAVING SUM(count) > 0
ORDER BY SUM(count) DESC
