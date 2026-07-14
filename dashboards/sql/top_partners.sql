WITH filtered AS (
    SELECT * FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
),

ranked AS (
    SELECT
        partner,
        count(*) AS screeners
    FROM filtered
    GROUP BY partner
    ORDER BY screeners DESC
),

total_screeners AS (
    SELECT count(*) AS total FROM filtered
)

SELECT
    "Partner",
    "# of Screeners",
    "% of Screeners"
FROM (
    SELECT
        0 AS sort_order,
        partner AS "Partner",
        screeners AS "# of Screeners",
        screeners::FLOAT / nullif(t.total, 0) AS "% of Screeners"
    FROM ranked, total_screeners t
    UNION ALL
    SELECT
        1 AS sort_order,
        'Total' AS "Partner",
        t.total AS "# of Screeners",
        CASE WHEN t.total = 0 THEN NULL ELSE 1::FLOAT END AS "% of Screeners"
    FROM total_screeners t
) combined
ORDER BY sort_order ASC, "# of Screeners" DESC
