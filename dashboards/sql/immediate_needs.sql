-- Immediate needs table: tie aggregated need rows to the same screener population as totals.
-- Uses EXISTS instead of DISTINCT + INNER JOIN so (partner, county) pairs with NULL county
-- still match Metabase filters and never drop rows when county is unset (MFB-998).
WITH totals AS (
    SELECT count(*) AS total_count
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]
)
SELECT
    n.benefit AS "Need Category",
    SUM(n.count) AS "# of Screeners",
    SUM(n.count)::float / NULLIF(MAX(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_immediate_needs AS n
CROSS JOIN totals AS t
WHERE EXISTS (
    SELECT 1
    FROM analytics.mart_screener_data AS s
    WHERE s.partner IS NOT DISTINCT FROM n.partner
      AND s.county IS NOT DISTINCT FROM n.county
      AND 1 = 1
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
)
GROUP BY n.benefit
ORDER BY SUM(n.count) DESC, n.benefit ASC
