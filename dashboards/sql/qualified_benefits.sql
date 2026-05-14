WITH totals AS (
    SELECT count(*) AS total_count
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]
)
SELECT
    qb.benefit AS "Benefit Name",
    SUM(qb.count) AS "# of Screeners",
    SUM(qb.count)::float / NULLIF(MAX(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_qualified_benefits AS qb
CROSS JOIN totals AS t
WHERE EXISTS (
    SELECT 1
    FROM analytics.mart_screener_data AS s
    WHERE s.partner IS NOT DISTINCT FROM qb.partner
      AND s.county IS NOT DISTINCT FROM qb.county
      AND 1 = 1
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
)
GROUP BY qb.benefit
ORDER BY SUM(qb.count) DESC, qb.benefit ASC
