WITH filtered AS (
    SELECT * FROM analytics.mart_screener_data
    WHERE submission_date >= CURRENT_DATE - INTERVAL '30 days'
    [[AND {{partner}}]]
),
county_counts AS (
    SELECT county, count(*) AS screeners
    FROM filtered
    WHERE county IS NOT NULL AND county <> ''
    GROUP BY county
    ORDER BY screeners DESC
    LIMIT 10
),
total_screeners AS (
    SELECT count(*) AS total FROM filtered
)
SELECT "Top 10 Counties", "#", "%" FROM (
    SELECT 0 AS sort_order, county AS "Top 10 Counties", screeners AS "#",
           screeners::float / NULLIF(t.total, 0) AS "%"
    FROM county_counts, total_screeners t
    UNION ALL
    SELECT 1, 'Total', sum(screeners),
           sum(screeners)::float / NULLIF(max(t.total), 0)
    FROM county_counts, total_screeners t
) combined
ORDER BY sort_order, "#" DESC
