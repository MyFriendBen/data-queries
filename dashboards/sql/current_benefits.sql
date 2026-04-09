WITH totals AS (SELECT count(*) as total_count FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]),
filter_keys AS (SELECT DISTINCT partner, county FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]])
SELECT
    pb.benefit as "Benefit Name",
    SUM(pb.count) as "# of Screeners",
    SUM(pb.count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_previous_benefits pb
INNER JOIN filter_keys fk ON pb.partner IS NOT DISTINCT FROM fk.partner AND pb.county IS NOT DISTINCT FROM fk.county
CROSS JOIN totals t
GROUP BY pb.benefit
HAVING SUM(pb.count) > 0
ORDER BY SUM(pb.count) DESC, pb.benefit ASC
