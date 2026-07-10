-- % of household members with a disability, among members who answered the
-- disability questions. "Disabled" mirrors the screener's own definition
-- (HouseholdMember.has_disability in benefits-api): a member counts as disabled
-- if ANY of the three self-reported flags is true —
--   disabled              (the explicit "Disabled" option)
--   visually_impaired     (the "Blind or visually impaired" option)
--   long_term_disability  (the "Any medical condition" option)
-- These are all nullable booleans; NULL means the question was not recorded for
-- that member (the three are not always captured together — e.g. the medical-
-- condition option was added later, so older rows have it NULL). We include a
-- member in the denominator if they answered AT LEAST ONE of the three, and
-- treat NULL as "not that condition" in the numerator. Members with all three
-- NULL (never asked) are excluded so the rate reflects prevalence among
-- respondents, consistent with how the age card excludes null ages.
WITH filter_keys AS (
    SELECT id
    FROM analytics.mart_screener_data
    WHERE 1 = 1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]
)

SELECT
    count(*) FILTER (
        WHERE hm.disabled IS TRUE
            OR hm.visually_impaired IS TRUE
            OR hm.long_term_disability IS TRUE
    )::FLOAT
    / nullif(count(*), 0) AS pct
FROM analytics.mart_householdmembers hm
INNER JOIN filter_keys fk ON hm.screener_id = fk.id
WHERE hm.disabled IS NOT NULL
    OR hm.visually_impaired IS NOT NULL
    OR hm.long_term_disability IS NOT NULL
