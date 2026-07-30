WITH filtered_screens AS (
    SELECT id
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
)

SELECT
    max(qb.benefit_display_name) AS "Benefit Name",
    count(DISTINCT qb.screen_id) AS "# of Screeners",
    count(DISTINCT qb.screen_id)::FLOAT / nullif((
        SELECT count(*)
        FROM analytics.mart_screener_data
        WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
    ), 0) AS "% of Screeners"
FROM analytics.mart_qualified_benefits qb
INNER JOIN filtered_screens fs ON qb.screen_id = fs.id
GROUP BY qb.benefit_name
HAVING count(DISTINCT qb.screen_id) > 0
ORDER BY count(DISTINCT qb.screen_id) DESC, max(qb.benefit_display_name) ASC
