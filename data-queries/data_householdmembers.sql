-- # This creates data_householdmember
CREATE MATERIALIZED VIEW
data_householdmembers AS

SELECT
    sh.*,
    d.id AS screener_id,
    d.white_label_id,
    d.partner,
    d.submission_date
FROM screener_householdmember AS sh
LEFT JOIN data AS d ON sh.screen_id = d.id
WHERE sh.screen_id IN (d.id)
