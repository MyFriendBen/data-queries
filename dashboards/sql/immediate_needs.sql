WITH totals AS (
    SELECT count(*) AS total_count FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
)

SELECT
    n.benefit AS "Need Category",
    sum(n.count) AS "# of Screeners",
    sum(n.count)::FLOAT / nullif(max(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_immediate_needs n
CROSS JOIN totals t
WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
GROUP BY n.benefit
ORDER BY sum(n.count) DESC, n.benefit ASC
