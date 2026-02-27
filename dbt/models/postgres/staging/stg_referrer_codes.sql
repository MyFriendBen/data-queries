{{
  config(
    materialized='view',
    description='This model maps referrer codes to partner names. It is used to standardize referrer codes across the system and ensure consistency in downstream models.'
  )
}}

SELECT *
FROM {{ ref('referrer_codes') }}
