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

{% endmacro %}


/*
  Create a user and set their white label RLS policy
  
  This macro creates a database user with either specific white label access
  or admin access that bypasses RLS entirely.
  
  Usage:
    {{ create_rls_user('username', 'password', white_label_id) }}
    {{ create_rls_user('admin_user', 'password', 'ADMIN') }}
    
  Parameters:
    - username: The database username to create
    - password: The user's password
    - white_label_access: Either a white_label_id (integer) or 'ADMIN' for bypass access
*/

{% macro create_rls_user() %}
  
  {% set username = var('username') %}
  {% set password = var('password') %}
  {% set white_label_access = var('white_label_access') %}
  
  {% if white_label_access == 'ADMIN' %}
    -- Create admin user with BYPASSRLS privilege
    {% set create_user_sql %}
      CREATE USER {{ username }} WITH PASSWORD '{{ password }}' BYPASSRLS;
    {% endset %}
  {% else %}
    -- Create regular user and set their white label ID
    {% set create_user_sql %}
      CREATE USER {{ username }} WITH PASSWORD '{{ password }}';
      ALTER USER {{ username }} SET rls.white_label_id = '{{ white_label_access }}';
    {% endset %}
  {% endif %}
  
  {% set grant_permissions_sql %}
    GRANT CONNECT ON DATABASE {{ target.database }} TO {{ username }};
    GRANT USAGE ON SCHEMA {{ target.schema }} TO {{ username }};
    GRANT SELECT ON ALL TABLES IN SCHEMA {{ target.schema }} TO {{ username }};
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA {{ target.schema }} TO {{ username }};
    ALTER DEFAULT PRIVILEGES IN SCHEMA {{ target.schema }} GRANT SELECT ON TABLES TO {{ username }};
    ALTER DEFAULT PRIVILEGES IN SCHEMA {{ target.schema }} GRANT USAGE, SELECT ON SEQUENCES TO {{ username }};
  {% endset %}
  
  -- Execute the SQL statements
  {% do run_query(create_user_sql) %}
  {% do run_query(grant_permissions_sql) %}
  
  {{ log("Created user '" ~ username ~ "' with white_label_access: " ~ white_label_access, info=true) }}

{% endmacro %}