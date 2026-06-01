WITH totals AS (
    SELECT count(*) AS total_count
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
),

filter_keys AS (
    SELECT DISTINCT
        coalesce(partner, '__NULL__') AS partner,
        coalesce(county, '__NULL__') AS county,
        coalesce(utm_campaign, '__NULL__') AS utm_campaign,
        coalesce(utm_medium, '__NULL__') AS utm_medium,
        coalesce(utm_source, '__NULL__') AS utm_source
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
)

SELECT
    qb.benefit AS "Benefit Name",
    sum(qb.count) AS "# of Screeners",
    sum(qb.count)::FLOAT / nullif(max(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_qualified_benefits qb
INNER JOIN filter_keys fk
    ON
        coalesce(qb.partner, '__NULL__') = fk.partner
        AND coalesce(qb.county, '__NULL__') = fk.county
        AND coalesce(qb.utm_campaign, '__NULL__') = fk.utm_campaign
        AND coalesce(qb.utm_medium, '__NULL__') = fk.utm_medium
        AND coalesce(qb.utm_source, '__NULL__') = fk.utm_source
CROSS JOIN totals t
GROUP BY qb.benefit
ORDER BY sum(qb.count) DESC, qb.benefit ASC
