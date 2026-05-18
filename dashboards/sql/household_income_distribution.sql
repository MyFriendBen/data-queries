WITH filtered AS (
    SELECT monthly_income * 12 AS annual_income
    FROM analytics.mart_screener_data
    WHERE monthly_income IS NOT NULL AND 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
),

total AS (
    SELECT COUNT(*) AS n FROM filtered
),

income_bins AS (
    SELECT
        CASE
            WHEN annual_income < 15000 THEN '$0-15K'
            WHEN annual_income < 30000 THEN '$15-30K'
            WHEN annual_income < 45000 THEN '$30-45K'
            WHEN annual_income < 60000 THEN '$45-60K'
            WHEN annual_income < 75000 THEN '$60-75K'
            WHEN annual_income < 100000 THEN '$75-100K'
            ELSE '$100K+'
        END AS income_range,
        CASE
            WHEN annual_income < 15000 THEN 1
            WHEN annual_income < 30000 THEN 2
            WHEN annual_income < 45000 THEN 3
            WHEN annual_income < 60000 THEN 4
            WHEN annual_income < 75000 THEN 5
            WHEN annual_income < 100000 THEN 6
            ELSE 7
        END AS sort_order
    FROM filtered
)

SELECT
    income_range AS "Income Range",
    COUNT(*)::FLOAT / NULLIF(MAX(t.n), 0) AS "% of Total"
FROM income_bins, total AS t
GROUP BY income_range, sort_order
ORDER BY sort_order
