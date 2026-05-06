-- ## Sources from Django Referrer model (programs_referrer table)
-- ## No longer manually maintained — add/edit referrers via Django admin
CREATE MATERIALIZED VIEW
data_referrer_codes AS

SELECT
    referrer_code,
    name AS partner,
    white_label_id
FROM programs_referrer;
