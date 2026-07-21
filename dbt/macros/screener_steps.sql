{#
  Canonical screener step definitions — the SINGLE source of truth for step slug,
  human label, and funnel rank. The ladder is a Jinja list here; everything else is
  generated from it so slug/label/rank can never diverge:
    - screener_step_label(col): inline CASE slug -> label (marts surfacing a label)
    - screener_step_ladder():    SQL rows (slug, label, funnel_rank) for the
                                 int model and the published mart_screener_step_ladder,
                                 which the Metabase-side funnel card LEFT JOINs
                                 (Metabase SQL can't call dbt macros).

  Slugs are the FE contract (getStepAnalyticsId); labels are a data-layer
  presentation choice. `rank` is the position in the monotonic drop-off funnel;
  `none` = deliberately OFF the ranked ladder (still labeled, so it renders if
  surfaced, but not a funnel rung):
    - select-state / referral-source: conditionally shown -> a skip would look
      like drop-off; reported separately.
    - member-basics: shown only for household size > 1, so it can't be a monotonic
      rung (fewer viewers than the universal member-details).
    - household-members / household-basics: legacy slugs kept labeled for old
      rows; the household funnel role is now member-details (MFB-1348 sub-steps).
    - cesn-*: energy flow, excluded from the non-CESN global funnel.
#}

{% macro _screener_steps() %}
  {# rank = funnel position, or none for off-ladder steps #}
  {{ return([
    {'slug': 'language',              'label': 'Language',                   'rank': 1},
    {'slug': 'disclaimer',            'label': 'Disclaimer',                 'rank': 2},
    {'slug': 'select-state',          'label': 'Select State',               'rank': none},
    {'slug': 'zip-code',              'label': 'Zip Code',                   'rank': 3},
    {'slug': 'household-size',        'label': 'Household Size',             'rank': 4},
    {'slug': 'member-basics',         'label': 'Member Basics',              'rank': none},
    {'slug': 'member-details',        'label': 'Member Details',             'rank': 5},
    {'slug': 'household-members',     'label': 'Household & Member Details', 'rank': none},
    {'slug': 'household-basics',      'label': 'Household Basics',           'rank': none},
    {'slug': 'expenses',              'label': 'Expenses',                   'rank': 6},
    {'slug': 'assets',                'label': 'Assets',                     'rank': 7},
    {'slug': 'current-benefits',      'label': 'Current Benefits',           'rank': 8},
    {'slug': 'additional-resources',  'label': 'Additional Resources',       'rank': 9},
    {'slug': 'referral-source',       'label': 'Referral Source',            'rank': none},
    {'slug': 'sign-up',               'label': 'Sign Up',                    'rank': 10},
    {'slug': 'confirm-information',   'label': 'Confirm Information',         'rank': 11},
    {'slug': 'results',               'label': 'Reached Results',            'rank': 12},
    {'slug': 'cesn-electric-provider','label': 'CESN Electric Provider',     'rank': none},
    {'slug': 'cesn-gas-provider',     'label': 'CESN Gas Provider',          'rank': none},
    {'slug': 'cesn-energy-expenses',  'label': 'CESN Energy Expenses',       'rank': none},
    {'slug': 'cesn-appliances',       'label': 'CESN Appliances',            'rank': none},
    {'slug': 'cesn-utility-status',   'label': 'CESN Utility Status',        'rank': none},
  ]) }}
{% endmacro %}


{# Inline CASE slug -> label. Unmapped/future slugs fall back to the raw slug. #}
{% macro screener_step_label(column_name) %}
    case {{ column_name }}
    {%- for step in _screener_steps() %}
        when '{{ step.slug }}' then '{{ step.label | replace("'", "\\'") }}'
    {%- endfor %}
        else {{ column_name }}
    end
{% endmacro %}


{# SQL rows (screener_step_name, screener_step_label, funnel_rank) for the ranked
   ladder and the published mart. #}
{% macro screener_step_ladder() %}
    {%- for step in _screener_steps() %}
    select
        '{{ step.slug }}' as screener_step_name,
        '{{ step.label | replace("'", "\\'") }}' as screener_step_label,
        {{ step.rank if step.rank is not none else 'cast(null as int64)' }} as funnel_rank
    {%- if not loop.last %} union all {% endif %}
    {%- endfor %}
{% endmacro %}
