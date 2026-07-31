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
    - cesn-*: energy flow, off the shared ladder; ranked instead by the two
      CESN per-path ranks below.

  CESN branches into a homeowner and a renter path that order the same steps
  differently and each have one exclusive step (homeowner: appliances; renter:
  energy-expenses, shown first). A single `rank` can't express both, so
  cesn_home / cesn_rent give each step its position within that path (none = not
  on it), mirroring the FE stepDirectory in cesn.py.
#}

{% macro _screener_steps() %}
  {# rank = shared non-CESN funnel position; cesn_home / cesn_rent = CESN per-path position. none = off that ladder. #}
  {{ return([
    {'slug': 'language',              'label': 'Language',                   'rank': 1,    'cesn_home': 1,    'cesn_rent': 1},
    {'slug': 'disclaimer',            'label': 'Disclaimer',                 'rank': 2,    'cesn_home': 2,    'cesn_rent': 2},
    {'slug': 'select-state',          'label': 'Select State',               'rank': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'cesn-energy-expenses',  'label': 'Energy Expenses',            'rank': none, 'cesn_home': none, 'cesn_rent': 3},
    {'slug': 'zip-code',              'label': 'Zip Code',                   'rank': 3,    'cesn_home': 3,    'cesn_rent': 4},
    {'slug': 'household-size',        'label': 'Household Size',             'rank': 4,    'cesn_home': 4,    'cesn_rent': 5},
    {'slug': 'member-basics',         'label': 'Member Basics',              'rank': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'member-details',        'label': 'Member Details',             'rank': 5,    'cesn_home': 5,    'cesn_rent': 6},
    {'slug': 'household-members',     'label': 'Household & Member Details', 'rank': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'household-basics',      'label': 'Household Basics',           'rank': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'cesn-electric-provider','label': 'Electric Provider',          'rank': none, 'cesn_home': 6,    'cesn_rent': 7},
    {'slug': 'cesn-gas-provider',     'label': 'Gas Provider',               'rank': none, 'cesn_home': 7,    'cesn_rent': 8},
    {'slug': 'cesn-utility-status',   'label': 'Utility Status',             'rank': none, 'cesn_home': 8,    'cesn_rent': 9},
    {'slug': 'cesn-appliances',       'label': 'Appliances',                 'rank': none, 'cesn_home': 9,    'cesn_rent': none},
    {'slug': 'expenses',              'label': 'Expenses',                   'rank': 6,    'cesn_home': none, 'cesn_rent': none},
    {'slug': 'assets',                'label': 'Assets',                     'rank': 7,    'cesn_home': none, 'cesn_rent': none},
    {'slug': 'current-benefits',      'label': 'Current Benefits',           'rank': 8,    'cesn_home': 10,   'cesn_rent': 10},
    {'slug': 'additional-resources',  'label': 'Additional Resources',       'rank': 9,    'cesn_home': none, 'cesn_rent': none},
    {'slug': 'referral-source',       'label': 'Referral Source',            'rank': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'sign-up',               'label': 'Sign Up',                    'rank': 10,   'cesn_home': none, 'cesn_rent': none},
    {'slug': 'confirm-information',   'label': 'Confirm Information',         'rank': 11,   'cesn_home': 11,   'cesn_rent': 11},
    {'slug': 'results',               'label': 'Reached Results',            'rank': 12,   'cesn_home': 12,   'cesn_rent': 12},
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


{# SQL rows (path, step, label, rank) for the CESN two-path funnel: one row per
   (step, path) the step is on. The card LEFT JOINs this per path and orders by rank. #}
{% macro screener_cesn_step_ladder() %}
    {%- set paths = [('homeowner', 'cesn_home'), ('renter', 'cesn_rent')] %}
    {%- set rows = [] %}
    {# rank 0 = the synthetic form-start rung both paths share (the funnel top). #}
    {%- for path_name, rank_key in paths %}
        {%- do rows.append((path_name, '__form_start__', 'Started Screener', 0)) %}
    {%- endfor %}
    {%- for step in _screener_steps() %}
        {%- for path_name, rank_key in paths %}
            {%- if step[rank_key] is not none %}
                {%- do rows.append((path_name, step.slug, step.label, step[rank_key])) %}
            {%- endif %}
        {%- endfor %}
    {%- endfor %}
    {%- for path_name, slug, label, rank in rows %}
    select
        '{{ path_name }}' as cesn_path,
        '{{ slug }}' as screener_step_name,
        '{{ label | replace("'", "\\'") }}' as screener_step_label,
        {{ rank }} as funnel_rank
    {%- if not loop.last %} union all {% endif %}
    {%- endfor %}
{% endmacro %}
