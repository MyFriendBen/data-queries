{{
  config(
    materialized='table',
    description='Referrer codes with partner names per white label. Sources from the Django Referrer model, where every referrer belongs to exactly one white label.',
    post_hook="{{ setup_white_label_rls(this.name) }}"
  )
}}

SELECT
  rc.referrer_code,
  rc.partner,
  rc.white_label_id,
  wl.white_label_code
FROM {{ ref('stg_referrer_codes') }} rc
INNER JOIN {{ ref('stg_white_label') }} wl
  ON rc.white_label_id = wl.white_label_id
