WITH totals AS (SELECT count(*) as total_count FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]),
filter_keys AS (SELECT DISTINCT partner, county FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]])
SELECT
    n.benefit as "Need Category",
    SUM(n.count) as "# of Screeners",
    SUM(n.count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_immediate_needs n
INNER JOIN filter_keys fk ON n.partner IS NOT DISTINCT FROM fk.partner AND n.county IS NOT DISTINCT FROM fk.county
CROSS JOIN totals t
GROUP BY n.benefit
ORDER BY SUM(n.count) DESC, n.benefit ASC
