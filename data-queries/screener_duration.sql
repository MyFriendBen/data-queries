-- Average screener completion time in production.
-- Duration = screener_screen.submission_date - screener_screen.start_date
--   start_date      = browser clock when the screener app mounted (client-supplied)
--   submission_date = server clock when results were first calculated
-- Read-only: no temp tables, so it runs on the GRAY follower (hot standby rejects
-- any write, including CREATE TEMP TABLE).
--
-- Window: last 90 days. Change the INTERVAL in all four blocks to re-scope.

\pset pager off

\echo '=== 1. Sample composition (last 90 days) ==='
WITH d AS (
    SELECT EXTRACT(EPOCH FROM (s.submission_date - s.start_date)) AS secs
    FROM screener_screen AS s
    WHERE s.completed = TRUE
      AND s.is_test = FALSE
      AND COALESCE(s.is_test_data, FALSE) = FALSE
      AND s.start_date IS NOT NULL
      AND s.submission_date IS NOT NULL
      AND s.submission_date >= NOW() - INTERVAL '90 days'
)
SELECT
    COUNT(*)                                         AS completed_screens,
    COUNT(*) FILTER (WHERE secs < 0)                 AS negative_clock_skew,
    COUNT(*) FILTER (WHERE secs >= 0 AND secs < 30)  AS under_30s,
    COUNT(*) FILTER (WHERE secs > 7200)              AS over_2h_abandoned_tab,
    COUNT(*) FILTER (WHERE secs BETWEEN 30 AND 7200) AS in_scope
FROM d;

\echo ''
\echo '=== 2. Headline: duration in minutes (30s-2h window) ==='
WITH d AS (
    SELECT EXTRACT(EPOCH FROM (s.submission_date - s.start_date)) AS secs
    FROM screener_screen AS s
    WHERE s.completed = TRUE
      AND s.is_test = FALSE
      AND COALESCE(s.is_test_data, FALSE) = FALSE
      AND s.start_date IS NOT NULL
      AND s.submission_date IS NOT NULL
      AND s.submission_date >= NOW() - INTERVAL '90 days'
)
SELECT
    COUNT(*)                                                                     AS n,
    ROUND((AVG(secs) / 60)::numeric, 1)                                          AS mean_min,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY secs) / 60)::numeric, 1)  AS median_min,
    ROUND((PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY secs) / 60)::numeric, 1) AS p25_min,
    ROUND((PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY secs) / 60)::numeric, 1) AS p75_min,
    ROUND((PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY secs) / 60)::numeric, 1) AS p90_min
FROM d
WHERE secs BETWEEN 30 AND 7200;

\echo ''
\echo '=== 3. By white label (30s-2h window, >=25 screens) ==='
WITH d AS (
    SELECT
        COALESCE(NULLIF(w.code, ''), w.name, 'unknown')                 AS white_label,
        EXTRACT(EPOCH FROM (s.submission_date - s.start_date))          AS secs
    FROM screener_screen AS s
    INNER JOIN screener_whitelabel AS w ON w.id = s.white_label_id
    WHERE s.completed = TRUE
      AND s.is_test = FALSE
      AND COALESCE(s.is_test_data, FALSE) = FALSE
      AND s.start_date IS NOT NULL
      AND s.submission_date IS NOT NULL
      AND s.submission_date >= NOW() - INTERVAL '90 days'
)
SELECT
    white_label,
    COUNT(*)                                                                    AS n,
    ROUND((AVG(secs) / 60)::numeric, 1)                                         AS mean_min,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY secs) / 60)::numeric, 1) AS median_min
FROM d
WHERE secs BETWEEN 30 AND 7200
GROUP BY white_label
HAVING COUNT(*) >= 25
ORDER BY n DESC;

\echo ''
\echo '=== 4. By month (30s-2h window, last 12 months) ==='
WITH d AS (
    SELECT
        s.submission_date,
        EXTRACT(EPOCH FROM (s.submission_date - s.start_date)) AS secs
    FROM screener_screen AS s
    WHERE s.completed = TRUE
      AND s.is_test = FALSE
      AND COALESCE(s.is_test_data, FALSE) = FALSE
      AND s.start_date IS NOT NULL
      AND s.submission_date IS NOT NULL
      AND s.submission_date >= NOW() - INTERVAL '12 months'
)
SELECT
    DATE_TRUNC('month', submission_date)::date                                  AS month,
    COUNT(*)                                                                    AS n,
    ROUND((AVG(secs) / 60)::numeric, 1)                                         AS mean_min,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY secs) / 60)::numeric, 1) AS median_min
FROM d
WHERE secs BETWEEN 30 AND 7200
GROUP BY 1
ORDER BY 1;
