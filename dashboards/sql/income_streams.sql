WITH filtered_screeners AS (
    SELECT id FROM analytics.mart_screener_data
    WHERE 1=1 [[AND {{partner}}]]
),
total AS (
    SELECT count(*) AS total_screeners FROM filtered_screeners
),
monthly_income AS (
    SELECT
        i.type AS income_type,
        i.screener_id,
        CASE i.frequency
            WHEN 'monthly' THEN i.amount
            WHEN 'weekly' THEN i.amount * 4.35
            WHEN 'biweekly' THEN i.amount * 2.175
            WHEN 'semimonthly' THEN i.amount * 2
            WHEN 'yearly' THEN i.amount / 12.0
            WHEN 'hourly' THEN i.amount * COALESCE(i.hours_worked, 0) * 4.35
            ELSE i.amount
        END AS monthly_amount
    FROM analytics.mart_income i
    INNER JOIN filtered_screeners f ON i.screener_id = f.id
    WHERE i.amount > 0
),
income_data AS (
    SELECT
        income_type,
        count(DISTINCT screener_id) AS screener_count,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_amount) AS median_amount
    FROM monthly_income
    GROUP BY income_type
)
SELECT
    CASE income_type
        WHEN 'wages' THEN 'Wages'
        WHEN 'selfEmployment' THEN 'Self Employment'
        WHEN 'sSDisability' THEN 'SS Disability'
        WHEN 'sSRetirement' THEN 'SS Retirement'
        WHEN 'SSI' THEN 'SSI'
        WHEN 'sSDependent' THEN 'SS Dependent'
        WHEN 'sSSurvivor' THEN 'SS Survivor'
        WHEN 'unemployment' THEN 'Unemployment'
        WHEN 'pension' THEN 'Pension'
        WHEN 'investmentIncome' THEN 'Investment Income'
        WHEN 'rental' THEN 'Rental'
        WHEN 'alimony' THEN 'Alimony'
        WHEN 'childSupport' THEN 'Child Support'
        WHEN 'DIVABenefits' THEN 'VA Disability'
        WHEN 'workersComp' THEN 'Workers Comp'
        WHEN 'giftedIncome' THEN 'Gifted Income'
        WHEN 'boarder' THEN 'Boarder'
        WHEN 'cOWorks' THEN 'CO Works'
        ELSE income_type
    END AS "Type",
    screener_count::float / NULLIF(t.total_screeners, 0) AS "% of Screeners",
    median_amount AS "Median Amount"
FROM income_data, total t
ORDER BY screener_count DESC
