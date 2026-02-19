{#
  Macro: enforce_rls_on_marts

  Enforces that all postgres mart models include the white label RLS post-hook
  (setup_white_label_rls). This macro is called via the on-run-end hook in
  dbt_project.yml and will raise a compilation error if any mart model under
  models/postgres/marts/ is missing the required post-hook.

  How it works:
    - Skips enforcement for non-postgres targets (e.g. BigQuery).
    - Iterates over all compiled graph nodes, filtering for mart models
      in the models/postgres/marts/ directory.
    - Inspects each model's 'post-hook' config for the presence of
      'setup_white_label_rls'.
    - Models can opt out by adding the tag 'no-rls' (e.g. tags=['no-rls']).
    - Collects non-compliant models and raises a clear error listing them.

  Usage:
    Added as an on-run-end hook in dbt_project.yml:
      on-run-end:
        - "{{ enforce_rls_on_marts() }}"

  Notes:
    - The {% if execute %} guard is required because the graph object is only
      available during execution, not during parsing.
    - dbt stores hooks under the hyphenated key 'post-hook' (not 'post_hook')
      in node.config.
    - Jinja's namespace() is used to work around for-loop variable scoping.
#}

{% macro enforce_rls_on_marts() %}
  {# Only enforce when running against postgres #}
  {% if target.type != 'postgres' %}
    {{ return('') }}
  {% endif %}

  {% set non_compliant = [] %}

  {% if execute %}
    {% for node in graph.nodes.values() %}
      {# Only check postgres mart models #}
      {% if node.resource_type == 'model'
         and node.fqn | length >= 3
         and node.fqn[1] == 'postgres'
         and node.fqn[2] == 'marts' %}

        {# Allow explicit opt-out via 'no-rls' tag #}
        {% if 'no-rls' in node.tags %}
          {{ log("ℹ️  " ~ node.name ~ " opted out of RLS via 'no-rls' tag", info=true) }}
        {% else %}
          {# Check if post-hook contains setup_white_label_rls #}
          {# Note: dbt stores hooks under the hyphenated key 'post-hook' in node.config #}
          {% set hooks = node.config.get('post-hook', []) %}
          {% set ns = namespace(has_rls_hook=false) %}
          {% for hook in hooks %}
            {% if 'setup_white_label_rls' in hook.sql %}
              {% set ns.has_rls_hook = true %}
            {% endif %}
          {% endfor %}

          {% if not ns.has_rls_hook %}
            {% do non_compliant.append(node.name) %}
          {% endif %}
        {% endif %}

      {% endif %}
    {% endfor %}
  {% endif %}

  {% if non_compliant | length > 0 %}
    {{ exceptions.raise_compiler_error(
      "\n🚨 RLS ENFORCEMENT FAILURE\n"
      ~ "The following mart models are missing the required white label RLS post-hook:\n\n  - "
      ~ non_compliant | join('\n  - ')
      ~ "\n\nTo fix, add this to each model's config block:\n"
      ~ '  post_hook="{{ setup_white_label_rls(this.name) }}"\n\n'
      ~ "If a model genuinely doesn't need RLS, add the tag 'no-rls':\n"
      ~ "  tags=['no-rls']\n"
    ) }}
  {% endif %}
{% endmacro %}