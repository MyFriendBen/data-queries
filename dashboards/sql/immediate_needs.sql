WITH filtered_screens AS (
    SELECT
        needs_baby_supplies,
        needs_child_dev_help,
        needs_food,
        needs_funeral_help,
        needs_housing_help,
        needs_mental_health_help,
        needs_family_planning_help,
        needs_dental_care,
        needs_job_resources,
        needs_legal_services,
        needs_college_savings,
        needs_veteran_services
    FROM analytics.mart_screener_data
    WHERE 1 = 1
        [[AND {{submission_date}}]]
        [[AND {{partner}}]]
        [[AND {{county}}]]
        [[AND {{utm_campaign}}]]
        [[AND {{utm_medium}}]]
        [[AND {{utm_source}}]]
),

need_counts AS (
    SELECT
'Baby Supplies'     AS benefit,
count(*) FILTER (WHERE needs_baby_supplies)        AS n
FROM filtered_screens
UNION ALL
    SELECT
'Child Development' AS benefit,
count(*) FILTER (WHERE needs_child_dev_help)       AS n
FROM filtered_screens
UNION ALL
    SELECT
'Food'              AS benefit,
count(*) FILTER (WHERE needs_food)                  AS n
FROM filtered_screens
UNION ALL
    SELECT
'Funeral'           AS benefit,
count(*) FILTER (WHERE needs_funeral_help)          AS n
FROM filtered_screens
UNION ALL
    SELECT
'Housing'           AS benefit,
count(*) FILTER (WHERE needs_housing_help)          AS n
FROM filtered_screens
UNION ALL
    SELECT
'Mental Health'     AS benefit,
count(*) FILTER (WHERE needs_mental_health_help)    AS n
FROM filtered_screens
UNION ALL
    SELECT
'Family Planning'   AS benefit,
count(*) FILTER (WHERE needs_family_planning_help)  AS n
FROM filtered_screens
UNION ALL
    SELECT
'Dental Care'       AS benefit,
count(*) FILTER (WHERE needs_dental_care)           AS n
FROM filtered_screens
UNION ALL
    SELECT
'Job Resources'     AS benefit,
count(*) FILTER (WHERE needs_job_resources)         AS n
FROM filtered_screens
UNION ALL
    SELECT
'Legal Services'    AS benefit,
count(*) FILTER (WHERE needs_legal_services)        AS n
FROM filtered_screens
UNION ALL
    SELECT
'College Savings'   AS benefit,
count(*) FILTER (WHERE needs_college_savings)       AS n
FROM filtered_screens
UNION ALL
    SELECT
'Veteran Services'  AS benefit,
count(*) FILTER (WHERE needs_veteran_services)      AS n
FROM filtered_screens
)

SELECT
    nc.benefit AS "Need Category",
    nc.n AS "# of Screeners",
    nc.n::FLOAT / nullif((
        SELECT count(*)
        FROM analytics.mart_screener_data
        WHERE 1 = 1
            [[AND {{submission_date}}]]
            [[AND {{partner}}]]
            [[AND {{county}}]]
            [[AND {{utm_campaign}}]]
            [[AND {{utm_medium}}]]
            [[AND {{utm_source}}]]
    ), 0) AS "% of Screeners"
FROM need_counts nc
WHERE nc.n > 0
ORDER BY nc.n DESC, nc.benefit ASC
