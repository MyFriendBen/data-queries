WITH totals AS (
    SELECT count(*) AS total_count
    FROM analytics.mart_screener_data
    WHERE 1 = 1[[AND {{submission_date}}]][[AND {{partner}}]][[AND {{county}}]][[AND {{utm_campaign}}]][[AND {{utm_medium}}]][[AND {{utm_source}}]]
),

filter_keys AS (
    SELECT DISTINCT
        partner,
        county,
        utm_campaign,
        utm_medium,
        utm_source
    FROM analytics.mart_screener_data
    WHERE 1 = 1[[AND {{submission_date}}]][[AND {{partner}}]][[AND {{county}}]][[AND {{utm_campaign}}]][[AND {{utm_medium}}]][[AND {{utm_source}}]]
)

SELECT
    qb.benefit AS "Benefit Name",
    sum(qb.count) AS "# of Screeners",
    sum(qb.count)::FLOAT / nullif(max(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_qualified_benefits qb
INNER JOIN filter_keys fk
    ON
        qb.partner IS NOT DISTINCT FROM fk.partner
        AND qb.county IS NOT DISTINCT FROM fk.county
        AND qb.utm_campaign IS NOT DISTINCT FROM fk.utm_campaign
        AND qb.utm_medium IS NOT DISTINCT FROM fk.utm_medium
        AND qb.utm_source IS NOT DISTINCT FROM fk.utm_source
CROSS JOIN totals t
GROUP BY qb.benefit
ORDER BY sum(qb.count) DESC, qb.benefit ASC
