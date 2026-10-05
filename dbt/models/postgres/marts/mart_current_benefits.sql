{{
  config(
    materialized='table',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

WITH federal AS (
    SELECT id
    FROM {{ source('django_apps', 'screener_whitelabel') }}
    WHERE code = 'federal'
)

-- DISTINCT ON keeps the screen x benefit grain: a screen can hold rows for both a federal
-- program and the deactivated state row it replaced (same name), and the federal one wins,
-- matching the API.
SELECT DISTINCT ON (cb.screen_id, pp.name_abbreviated)
    cb.screen_id,
    -- The screen's white label, not the program's: RLS scopes on this column, and a federal
    -- program's own white label is `federal`, which no partner can see.
    msd.white_label_id,
    msd.partner,
    msd.county,
    msd.submission_date,
    msd.utm_campaign,
    msd.utm_medium,
    msd.utm_source,
    pp.name_abbreviated AS benefit_name,
    COALESCE(pn.text, pp.name_abbreviated) AS benefit_display_name
FROM {{ ref('stg_current_benefits') }} AS cb
INNER JOIN {{ source('django_apps', 'programs_program') }} AS pp
    ON cb.program_id = pp.id
LEFT JOIN federal ON TRUE
INNER JOIN {{ ref('mart_screener_data') }} AS msd
    ON cb.screen_id = msd.id
    -- Defensive: also require the program to be one the screen's white label sees (its own,
    -- or a federal one). Silently drops any anomalous join-table rows that point at another
    -- state's program (should never happen, but safer to drop than to leak across WL boundaries).
    AND (pp.white_label_id = msd.white_label_id OR pp.white_label_id = federal.id)
LEFT JOIN {{ source('django_apps', 'translations_translation_translation') }} AS pn
    ON pp.name_id = pn.master_id
    AND pn.language_code = 'en-us'
ORDER BY cb.screen_id ASC, pp.name_abbreviated ASC, (pp.white_label_id = federal.id) DESC NULLS LAST, pp.id ASC
