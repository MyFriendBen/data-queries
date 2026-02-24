-- # Create the Expenses table
CREATE MATERIALIZED VIEW
data_expenses AS

SELECT
    se.*,
    d.id AS screener_id,
    d.submission_date,
    d.white_label_id
FROM screener_expense AS se
LEFT JOIN data AS d ON se.screen_id = d.id
WHERE se.screen_id IN (d.id)
