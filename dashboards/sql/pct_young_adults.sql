WITH filter_keys AS (
    SELECT id
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
)

SELECT
    count(*) FILTER (WHERE hm.age BETWEEN 19 AND 24)::FLOAT
    / nullif(count(*), 0) AS pct
FROM analytics.mart_householdmembers hm
INNER JOIN filter_keys fk ON hm.screener_id = fk.id
WHERE hm.age IS NOT NULL
