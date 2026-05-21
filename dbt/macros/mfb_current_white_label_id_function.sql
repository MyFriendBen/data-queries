{#
  Session variable helper for index-friendly RLS (Benefits / Metabase dashboards).

  Enabled via `vars.mfb_rls_policy_mode: session_guc` in dbt_project.yml. Each
  tenant's GUC is set once per connection by Metabase via JDBC options
  (`options=-c app.white_label_id=<id>`, configured in dashboards/metabase.tf).
  Postgres applies the option at connect time, so the GUC is available before
  any query runs — no per-query `set_config()` call is required.

  For ad-hoc testing outside Metabase (e.g. psql), set the GUC manually:

    SELECT set_config('app.white_label_id', '<id>', false);

  Security note: custom GUCs (`app.*`) are user-settable by default in Postgres,
  so any role with native-SQL access could `SET app.white_label_id = <other_id>`
  to bypass RLS. Tenant isolation depends on Metabase native-query access being
  restricted to the Administrators group — preserve this invariant when adding
  new tenant groups.
#}

{% macro ensure_mfb_current_white_label_id_function() %}
  {% if target.type != 'postgres' %}
    {{ return('') }}
  {% endif %}

  CREATE OR REPLACE FUNCTION {{ target.schema }}.mfb_current_white_label_id()
  RETURNS integer
  LANGUAGE sql
  STABLE
  PARALLEL SAFE
  SET search_path = ''
  AS $fn$
    SELECT (NULLIF(TRIM(BOTH FROM current_setting('app.white_label_id', true)), ''))::integer
  $fn$;

  GRANT EXECUTE ON FUNCTION {{ target.schema }}.mfb_current_white_label_id() TO PUBLIC;

{% endmacro %}
