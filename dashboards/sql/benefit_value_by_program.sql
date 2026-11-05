WITH filtered_screens AS (
    SELECT id
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
),

program_totals AS (
    SELECT
        max(qb.benefit_display_name) AS benefit_display_name,
        sum(qb.annual_value) AS total_value
    FROM analytics.mart_qualified_benefits AS qb
    INNER JOIN filtered_screens AS fs ON qb.screen_id = fs.id
    GROUP BY qb.benefit_name
)

-- Each program's total is divided by the total of all programs for the same filters (not an average), so the shares add up to 100%.
SELECT
    benefit_display_name AS "Benefit Name",
    total_value AS "Estimated Annual Value",
    total_value::FLOAT / nullif(sum(total_value) OVER (), 0) AS "% of Total Value"
FROM program_totals
ORDER BY total_value DESC, benefit_display_name ASC
