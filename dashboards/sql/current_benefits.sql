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
    cb.benefit_display_name AS "Benefit Name",
    count(DISTINCT cb.screen_id) AS "# of Screeners",
    count(DISTINCT cb.screen_id)::FLOAT / nullif(max(t.total_count), 0) AS "% of Screeners"
FROM analytics.mart_current_benefits cb
INNER JOIN filter_keys fk
    ON
        cb.partner IS NOT DISTINCT FROM fk.partner
        AND cb.county IS NOT DISTINCT FROM fk.county
        AND cb.utm_campaign IS NOT DISTINCT FROM fk.utm_campaign
        AND cb.utm_medium IS NOT DISTINCT FROM fk.utm_medium
        AND cb.utm_source IS NOT DISTINCT FROM fk.utm_source
CROSS JOIN totals t
GROUP BY cb.benefit_display_name
HAVING count(DISTINCT cb.screen_id) > 0
ORDER BY count(DISTINCT cb.screen_id) DESC, cb.benefit_display_name ASC
