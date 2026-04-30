WITH totals AS (
    SELECT count(*) AS total_count
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]
),

filter_keys AS (
    SELECT DISTINCT
        white_label_id,
        partner,
        county
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]
)

SELECT
    qb.benefit AS "Benefit Name",
    sum(qb.count) AS "# of Screeners",
    sum(qb.count)::FLOAT / nullif(max(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_qualified_benefits AS qb
INNER JOIN filter_keys AS fk
    ON
        qb.partner IS NOT DISTINCT FROM fk.partner
        AND qb.county IS NOT DISTINCT FROM fk.county
        AND qb.white_label_id = fk.white_label_id
CROSS JOIN totals AS t
GROUP BY qb.benefit
HAVING sum(qb.count) > 0
ORDER BY sum(qb.count) DESC, qb.benefit ASC
