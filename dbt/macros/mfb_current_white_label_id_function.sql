{#
  Session variable helper for index-friendly RLS (Benefits / Metabase dashboards).

  Prefer `vars.mfb_rls_policy_mode: session_guc` in dbt_project.yml only after the
  warehouse client (e.g. Metabase) runs per session:

    SELECT set_config('app.white_label_id', '<id>', false);

  See dashboards/sql/BENEFITS_TAB_PLAN_AND_RLS.md and dashboards/sql/tests/benefits_tab_queries/reproduce_issue.sh
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
