{{
  config(
    materialized='table',
    description='Referrer codes with partner names, expanded per white label. Generic codes (null white_label_code) are duplicated for each WL. Used by Metabase partner dropdown filters.',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

-- WL-specific referrer codes: join to get white_label_id
SELECT
    rc.referrer_code,
    rc.partner,
    wl.white_label_id,
    wl.white_label_code
FROM {{ ref('stg_referrer_codes') }} rc
INNER JOIN {{ ref('stg_white_label') }} wl
    ON rc.white_label_code = wl.white_label_code

UNION ALL

-- Generic codes (null/empty WL): duplicate for every WL
SELECT
    rc.referrer_code,
    rc.partner,
    wl.white_label_id,
    wl.white_label_code
FROM {{ ref('stg_referrer_codes') }} rc
CROSS JOIN {{ ref('stg_white_label') }} wl
WHERE rc.white_label_code IS NULL OR rc.white_label_code = ''
