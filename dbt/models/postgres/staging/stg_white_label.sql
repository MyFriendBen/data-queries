{{
  config(
    materialized='view',
    description='Staging model for white label organization data'
  )
}}

SELECT
    id AS white_label_id,
    name AS white_label_name,
    code AS white_label_code
FROM {{ source('django_apps', 'screener_whitelabel') }}
WHERE
    -- Only include white labels with at least a name or code
    (name IS NOT NULL AND name != '')
    OR (code IS NOT NULL AND code != '')
