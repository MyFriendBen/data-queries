SELECT
    DATE_TRUNC(event_date_parsed, MONTH) AS month,
    COUNT(DISTINCT user_pseudo_id) AS active_users
FROM `analytics_internal`.`int_ga4_page_views`
WHERE state_code = '${state_code}'
GROUP BY month
ORDER BY month
