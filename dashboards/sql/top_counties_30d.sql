WITH filtered AS (
    SELECT * FROM analytics.mart_screener_data
    WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]]
),

county_counts AS (
    SELECT
        county,
        count(*) AS screeners
    FROM filtered
    WHERE county IS NOT NULL AND county <> ''
    GROUP BY county
    ORDER BY screeners DESC
    LIMIT 10
),

total_screeners AS (
    SELECT count(*) AS total FROM filtered
)

SELECT
    "Top 10 Counties",
    "#",
    "%"
FROM (
    SELECT
        0 AS sort_order,
        county AS "Top 10 Counties",
        screeners AS "#",
        screeners::FLOAT / nullif(t.total, 0) AS "%"
    FROM county_counts, total_screeners AS t
    UNION ALL
    SELECT
        1 AS sort_order,
        'Total' AS "Top 10 Counties",
        t.total AS "#",
        CASE WHEN t.total = 0 THEN NULL ELSE 1::FLOAT END AS "%"
    FROM total_screeners AS t
) combined
ORDER BY sort_order, "#" DESC
