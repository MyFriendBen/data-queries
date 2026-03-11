-- # Create the Income Stream table
CREATE MATERIALIZED VIEW
data_income AS

SELECT
    si.*,
    d.id AS screener_id,
    d.submission_date,
    d.white_label_id
FROM screener_incomestream AS si
LEFT JOIN data AS d ON si.screen_id = d.id
WHERE si.screen_id IN (d.id)
