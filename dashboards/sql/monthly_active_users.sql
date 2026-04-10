SELECT
    DATE_TRUNC(event_date_parsed, MONTH) AS month,
    COUNT(DISTINCT user_pseudo_id) AS active_users
FROM `${bq_internal_dataset}.int_ga4_page_views`
WHERE state_code IN (${state_codes})
GROUP BY month
ORDER BY month
