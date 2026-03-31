WITH filtered AS (
    SELECT household_assets
    FROM analytics.mart_screener_data
    WHERE household_assets IS NOT NULL [[AND {{partner}}]] [[AND {{county}}]]
),
total AS (
    SELECT count(*) AS n FROM filtered
),
asset_bins AS (
    SELECT
        CASE
            WHEN household_assets < 1000 THEN '$0-1K'
            WHEN household_assets < 2000 THEN '$1-2K'
            WHEN household_assets < 5000 THEN '$2-5K'
            WHEN household_assets < 10000 THEN '$5-10K'
            WHEN household_assets < 50000 THEN '$10-50K'
            ELSE '$50K+'
        END AS asset_range,
        CASE
            WHEN household_assets < 1000 THEN 1
            WHEN household_assets < 2000 THEN 2
            WHEN household_assets < 5000 THEN 3
            WHEN household_assets < 10000 THEN 4
            WHEN household_assets < 50000 THEN 5
            ELSE 6
        END AS sort_order
    FROM filtered
)
SELECT asset_range AS "Asset Range",
       count(*)::float / NULLIF(max(t.n), 0) AS "% of Total"
FROM asset_bins, total t
GROUP BY asset_range, sort_order
ORDER BY sort_order
