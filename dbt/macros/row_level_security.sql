/*
  Row Level Security (RLS) macro for white label filtering
  
  This macro creates database policies that restrict users to only see data 
  for their associated white label.
  
  Usage:
    {{ setup_white_label_rls('table_name', 'white_label_id_column') }}
    
  Parameters:
    - table_name: The name of the table to apply RLS to
    - white_label_column: The column name containing white label IDs (default: 'white_label_id')
    - schema_name: Optional schema name (default: current schema)
*/

{% macro setup_white_label_rls(table_name, white_label_column='white_label_id', schema_name=none) %}
  
  {% set full_table_name %}
    {% if schema_name %}{{ schema_name }}.{{ table_name }}{% else %}{{ target.schema }}.{{ table_name }}{% endif %}
  {% endset %}
  
  {% set policy_name %}rls_white_label_{{ table_name }}{% endset %}
  
  -- Enable RLS on the table
  ALTER TABLE {{ full_table_name }} ENABLE ROW LEVEL SECURITY;
  
  -- Drop existing policy if it exists
  DROP POLICY IF EXISTS {{ policy_name }} ON {{ full_table_name }};
  
  -- Create RLS policy that filters by user's white label setting
  CREATE POLICY {{ policy_name }}
    ON {{ full_table_name }}
    FOR ALL
    TO PUBLIC
    USING (
      {{ white_label_column }} = COALESCE(
        NULLIF(current_setting('rls.white_label_id', true), '')::integer,
        -999999  -- Deny access if no white_label_id is set
      )
    );
  
  -- Grant necessary permissions
  GRANT SELECT ON {{ full_table_name }} TO PUBLIC;

  -- Create index for white_label_id 
  CREATE INDEX IF NOT EXISTS idx_{{ table_name }}_{{ white_label_column }}
    ON {{ full_table_name }} ({{ white_label_column }});

{% endmacro %}
