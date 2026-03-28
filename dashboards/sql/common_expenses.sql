WITH filtered_screeners AS (
    SELECT id FROM analytics.mart_screener_data
    WHERE 1=1 [[AND {{partner}}]]
),
total AS (
    SELECT count(*) AS total_screeners FROM filtered_screeners
),
monthly_expenses AS (
    SELECT
        e.type AS expense_type,
        e.screener_id,
        CASE e.frequency
            WHEN 'monthly' THEN e.amount
            WHEN 'weekly' THEN e.amount * 4.35
            WHEN 'biweekly' THEN e.amount * 2.175
            WHEN 'semimonthly' THEN e.amount * 2
            WHEN 'yearly' THEN e.amount / 12.0
            ELSE e.amount
        END AS monthly_amount
    FROM analytics.mart_screener_expense e
    INNER JOIN filtered_screeners f ON e.screener_id = f.id
    WHERE e.amount > 0
),
expense_data AS (
    SELECT
        expense_type,
        count(DISTINCT screener_id) AS screener_count,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_amount) AS median_amount
    FROM monthly_expenses
    GROUP BY expense_type
)
SELECT
    CASE expense_type
        WHEN 'rent' THEN 'Rent'
        WHEN 'mortgage' THEN 'Mortgage'
        WHEN 'childCare' THEN 'Child Care'
        WHEN 'childSupport' THEN 'Child Support'
        WHEN 'dependentCare' THEN 'Dependent Care'
        WHEN 'medical' THEN 'Medical'
        WHEN 'heating' THEN 'Heating'
        WHEN 'telephone' THEN 'Telephone'
        ELSE expense_type
    END AS "Type",
    screener_count::float / NULLIF(t.total_screeners, 0) AS "% of Screeners",
    median_amount AS "Median Amount"
FROM expense_data, total t
ORDER BY screener_count DESC
