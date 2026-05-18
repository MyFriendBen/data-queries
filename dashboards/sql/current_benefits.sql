WITH totals AS (
    SELECT count(*) AS total_count FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
),

filter_keys AS (
    SELECT DISTINCT
        partner,
        county,
        utm_campaign,
        utm_medium,
        utm_source
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
)

SELECT
    pb.benefit AS "Benefit Name",
    sum(pb.count) AS "# of Screeners",
    sum(pb.count)::FLOAT / nullif(max(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_previous_benefits pb
INNER JOIN filter_keys fk
    ON
        pb.partner IS NOT DISTINCT FROM fk.partner
        AND pb.county IS NOT DISTINCT FROM fk.county
        AND pb.utm_campaign IS NOT DISTINCT FROM fk.utm_campaign
        AND pb.utm_medium IS NOT DISTINCT FROM fk.utm_medium
        AND pb.utm_source IS NOT DISTINCT FROM fk.utm_source
CROSS JOIN totals t
GROUP BY pb.benefit
HAVING sum(pb.count) > 0
ORDER BY sum(pb.count) DESC, pb.benefit ASC
