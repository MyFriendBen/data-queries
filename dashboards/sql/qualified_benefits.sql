WITH totals AS (
    SELECT count(*) as total_count FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]
),
filter_keys AS (
    SELECT DISTINCT partner, county FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]
)
SELECT
    qb.benefit as "Benefit Name",
    SUM(qb.count) as "# of Screeners",
    SUM(qb.count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_qualified_benefits qb
INNER JOIN filter_keys fk ON qb.partner IS NOT DISTINCT FROM fk.partner AND qb.county IS NOT DISTINCT FROM fk.county
CROSS JOIN totals t
GROUP BY qb.benefit
ORDER BY SUM(qb.count) DESC, qb.benefit ASC
