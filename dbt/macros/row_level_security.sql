/*
  Row Level Security (RLS) macro for white label filtering.

  Creates database policies that restrict users to only see data for their
  associated white label.

  Usage:
    setup_white_label_rls('table_name', 'white_label_id_column')

  Parameters:
    - table_name: The name of the table to apply RLS to
    - white_label_column: The column name containing white label IDs (default: 'white_label_id')
    - schema_name: Optional schema name (default: current schema)

  Var (dbt_project.yml):
    mfb_rls_policy_mode: regex_user | session_guc

    session_guc (current, MFB-975): policy uses mfb_current_white_label_id() —
    a STABLE function that reads the `app.white_label_id` session GUC. Metabase
    sets the GUC at JDBC connect time via `options=-c app.white_label_id=<id>`.
    Index-friendly: Postgres can fold the function to a constant and use the
    white_label_id btree index.

    regex_user (legacy): policy extracts the ID from `current_user` via regex
    (`wl_<state>_<id>_ro`). Not index-friendly — forces seq scans. Kept as
    fallback in case the GUC setup needs to be rolled back.
*/

{% macro setup_white_label_rls(table_name, white_label_column='white_label_id', schema_name=none) %}

  {% set full_table_name %}
    {% if schema_name %}{{ schema_name }}.{{ table_name }}{% else %}{{ target.schema }}.{{ table_name }}{% endif %}
  {% endset %}

  {% set policy_name %}rls_white_label_{{ table_name }}{% endset %}

  {% set rls_mode = var('mfb_rls_policy_mode', 'regex_user') %}

  {% set using_clause %}
    {% if rls_mode == 'session_guc' %}
      {{ white_label_column }} = {{ target.schema }}.mfb_current_white_label_id()
    {% else %}
      {{ white_label_column }} = (regexp_match(current_user, '^wl_[a-z_]+_([0-9]+)_ro$'))[1]::int
    {% endif %}
  {% endset %}

  -- Enable RLS on the table
  ALTER TABLE {{ full_table_name }} ENABLE ROW LEVEL SECURITY;

  -- Drop existing policy if it exists
  DROP POLICY IF EXISTS {{ policy_name }} ON {{ full_table_name }};

  -- Table owners (dbt build user) bypass RLS automatically in PostgreSQL.
  -- Non-conforming role names (regex_user mode) or missing GUC (session_guc
  -- mode) yield NULL → no rows (safe denial).
  CREATE POLICY {{ policy_name }}
    ON {{ full_table_name }}
    FOR ALL
    TO PUBLIC
    USING (
      {{ using_clause }}
    );

  -- Grant necessary permissions
  GRANT SELECT ON {{ full_table_name }} TO PUBLIC;

  -- Create index for white_label_id
  CREATE INDEX IF NOT EXISTS idx_{{ table_name }}_{{ white_label_column }}
    ON {{ full_table_name }} ({{ white_label_column }});

{% endmacro %}
