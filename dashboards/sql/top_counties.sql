WITH filtered AS (
    SELECT * FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
),

county_counts AS (
    SELECT
        county,
        count(*) AS screeners
    FROM filtered
    WHERE county IS NOT NULL AND county <> ''
    GROUP BY county
    ORDER BY screeners DESC
),

total_screeners AS (
    SELECT count(*) AS total FROM filtered
)

SELECT
    "County",
    "# of Screeners",
    "% of Screeners"
FROM (
    SELECT
        0 AS sort_order,
        county AS "County",
        screeners AS "# of Screeners",
        screeners::FLOAT / nullif(t.total, 0) AS "% of Screeners"
    FROM county_counts, total_screeners t
    UNION ALL
    SELECT
        1 AS sort_order,
        'Total' AS "County",
        t.total AS "# of Screeners",
        CASE WHEN t.total = 0 THEN NULL ELSE 1::FLOAT END AS "% of Screeners"
    FROM total_screeners t
) combined
ORDER BY sort_order ASC, "# of Screeners" DESC
