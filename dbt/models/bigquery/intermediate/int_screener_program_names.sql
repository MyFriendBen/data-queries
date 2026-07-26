{{
  config(
    materialized='view'
  )
}}

-- program_id -> display name lookup, one row per program_id, built from any event
-- carrying both. The name is derived from events already collected rather than a
-- maintained mapping, so a rename flows through automatically. All-time (no date
-- filter) so an id seen on any prior day still resolves. Marts key on program_id
-- and left-join here for the label.

select
    program_id,
    max(program_name) as program_name
from {{ ref('stg_ga_screener_program_interactions') }}
where program_id is not null
    and program_name is not null
group by program_id
