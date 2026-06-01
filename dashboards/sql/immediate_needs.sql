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
    n.benefit AS "Need Category",
    sum(n.count) AS "# of Screeners",
    sum(n.count)::FLOAT / nullif(max(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_immediate_needs n
INNER JOIN filter_keys fk
    ON
        n.partner IS NOT DISTINCT FROM fk.partner
        AND n.county IS NOT DISTINCT FROM fk.county
        AND n.utm_campaign IS NOT DISTINCT FROM fk.utm_campaign
        AND n.utm_medium IS NOT DISTINCT FROM fk.utm_medium
        AND n.utm_source IS NOT DISTINCT FROM fk.utm_source
CROSS JOIN totals t
GROUP BY n.benefit
ORDER BY sum(n.count) DESC, n.benefit ASC
