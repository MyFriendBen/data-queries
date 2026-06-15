WITH filtered_screens AS (
    SELECT id
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
)

SELECT
    max(cb.benefit_display_name) AS "Benefit Name",
    count(DISTINCT cb.screen_id) AS "# of Screeners",
    count(DISTINCT cb.screen_id)::FLOAT / nullif((
        SELECT count(*)
        FROM analytics.mart_screener_data
        WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
    ), 0) AS "% of Screeners"
FROM analytics.mart_current_benefits cb
INNER JOIN filtered_screens fs ON cb.screen_id = fs.id
GROUP BY cb.benefit_name
HAVING count(DISTINCT cb.screen_id) > 0
ORDER BY count(DISTINCT cb.screen_id) DESC, max(cb.benefit_display_name) ASC
