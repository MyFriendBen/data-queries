{{
  config(
    materialized='view',
    description='One row per white label x program name that white label sees: its own programs plus the ones under the federal white label, which every white label sees. When a name exists on both sides (a state row deactivated after its program moved to federal), the federal row wins, matching the API (benefits-api programs/federal.py). Join on (white_label_id, name_abbreviated) to resolve the program a screen sees without fanning out.'
  )
}}

WITH federal AS (
    SELECT id
    FROM {{ source('django_apps', 'screener_whitelabel') }}
    WHERE code = 'federal'
),

candidates AS (
    SELECT
        wl.id AS white_label_id,
        pp.name_abbreviated,
        pp.id AS program_id,
        pp.name_id,
        pp.category_id,
        COALESCE(pp.white_label_id = federal.id, FALSE) AS is_federal
    FROM {{ source('django_apps', 'screener_whitelabel') }} AS wl
    LEFT JOIN federal ON TRUE
    INNER JOIN {{ source('django_apps', 'programs_program') }} AS pp
        ON
            wl.id = pp.white_label_id
            OR federal.id = pp.white_label_id
    -- No screen is created under the federal white label itself.
    WHERE federal.id IS NULL OR wl.id != federal.id
)

SELECT DISTINCT ON (white_label_id, name_abbreviated)
    white_label_id,
    name_abbreviated,
    program_id,
    name_id,
    category_id,
    is_federal
FROM candidates
ORDER BY white_label_id ASC, name_abbreviated ASC, is_federal DESC, program_id ASC
