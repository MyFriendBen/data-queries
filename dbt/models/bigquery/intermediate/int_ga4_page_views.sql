{{
  config(
    materialized='view'
  )
}}

-- Intermediate GA4 page views with derived fields
-- Adds business logic and extracted fields on top of staging model

select
    -- Event information
    event_date,
    event_timestamp,
    event_name,
    event_datetime,
    event_date_parsed,

    -- User information
    user_pseudo_id,
    user_id,

    -- Session information
    ga_session_id,

    -- Page information (from staging)
    page_location,

    -- Derived page fields (business logic)
    regexp_extract(page_location, r'[^/]+://[^/]+(/[^?]*)') as page_path,
    regexp_extract(page_location, r'[^/]+://([^/]+)') as page_hostname,
    regexp_extract(page_location, r'^[^/]+://[^/]+/([a-z]{2})/', 1) as state_code

from {{ ref('stg_ga_page_views') }}
where page_location is not null
