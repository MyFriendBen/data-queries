WITH totals AS (
    SELECT count(*) AS total_count FROM analytics.mart_screener_data
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
    n.benefit AS "Need Category",
    sum(n.count) AS "# of Screeners",
    sum(n.count)::FLOAT / nullif(max(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_immediate_needs n
INNER JOIN filter_keys fk
    ON
        coalesce(n.partner, '__NULL__') = fk.partner
        AND coalesce(n.county, '__NULL__') = fk.county
        AND coalesce(n.utm_campaign, '__NULL__') = fk.utm_campaign
        AND coalesce(n.utm_medium, '__NULL__') = fk.utm_medium
        AND coalesce(n.utm_source, '__NULL__') = fk.utm_source
CROSS JOIN totals t
GROUP BY n.benefit
ORDER BY sum(n.count) DESC, n.benefit ASC
