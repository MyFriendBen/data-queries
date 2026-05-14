WITH totals AS (
    SELECT count(*) AS total_count
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]
)
SELECT
    pb.benefit AS "Benefit Name",
    SUM(pb.count) AS "# of Screeners",
    SUM(pb.count)::float / NULLIF(MAX(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_previous_benefits AS pb
CROSS JOIN totals AS t
WHERE EXISTS (
    SELECT 1
    FROM analytics.mart_screener_data AS s
    WHERE s.partner IS NOT DISTINCT FROM pb.partner
      AND s.county IS NOT DISTINCT FROM pb.county
      AND 1 = 1
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
)
GROUP BY pb.benefit
HAVING SUM(pb.count) > 0
ORDER BY SUM(pb.count) DESC, pb.benefit ASC
