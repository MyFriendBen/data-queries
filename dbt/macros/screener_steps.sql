{#
  Single source of truth for each screener step's slug, label, and funnel rank.
  Slugs are the FE contract; labels are a presentation choice; everything else is
  generated from this list so the three can't diverge. Consumed via
  screener_step_label() and the ladder macros below.

  Rank columns give a step its position in a funnel, or none to keep it off that
  funnel (still labeled, just not a rung):
    - rank: the shared non-CESN funnel.
    - cesn: the combined CESN funnel (steps common to both energy paths).
    - cesn_home / cesn_rent: the per-path CESN funnels — currently unused, kept
      for a future per-path split.
  Off-ladder cases: select-state / referral-source are conditionally shown (a skip
  would read as drop-off); member-basics shows only for household size > 1;
  household-members / household-basics are legacy slugs kept only for old rows.

  CESN's energy flow branches into a homeowner and a renter path (mirroring the FE
  stepDirectory in cesn.py) that order the same steps differently, each with one
  exclusive step: appliances (homeowner) and energy-expenses (renter, shown first).
  The combined `cesn` rank omits both exclusives; the per-path ranks include them.
#}

{% macro _screener_steps() %}
  {{ return([
    {'slug': 'language',              'label': 'Language',                   'rank': 1,    'cesn': 1,    'cesn_home': 1,    'cesn_rent': 1},
    {'slug': 'disclaimer',            'label': 'Disclaimer',                 'rank': 2,    'cesn': 2,    'cesn_home': 2,    'cesn_rent': 2},
    {'slug': 'select-state',          'label': 'Select State',               'rank': none, 'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'cesn-energy-expenses',  'label': 'Energy Expenses',            'rank': none, 'cesn': none, 'cesn_home': none, 'cesn_rent': 3},
    {'slug': 'zip-code',              'label': 'Zip Code',                   'rank': 3,    'cesn': 3,    'cesn_home': 3,    'cesn_rent': 4},
    {'slug': 'household-size',        'label': 'Household Size',             'rank': 4,    'cesn': 4,    'cesn_home': 4,    'cesn_rent': 5},
    {'slug': 'member-basics',         'label': 'Member Basics',              'rank': none, 'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'member-details',        'label': 'Member Details',             'rank': 5,    'cesn': 5,    'cesn_home': 5,    'cesn_rent': 6},
    {'slug': 'household-members',     'label': 'Household & Member Details', 'rank': none, 'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'household-basics',      'label': 'Household Basics',           'rank': none, 'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'cesn-electric-provider','label': 'Electric Provider',          'rank': none, 'cesn': 6,    'cesn_home': 6,    'cesn_rent': 7},
    {'slug': 'cesn-gas-provider',     'label': 'Gas Provider',               'rank': none, 'cesn': 7,    'cesn_home': 7,    'cesn_rent': 8},
    {'slug': 'cesn-utility-status',   'label': 'Utility Status',             'rank': none, 'cesn': 8,    'cesn_home': 8,    'cesn_rent': 9},
    {'slug': 'cesn-appliances',       'label': 'Appliances',                 'rank': none, 'cesn': none, 'cesn_home': 9,    'cesn_rent': none},
    {'slug': 'expenses',              'label': 'Expenses',                   'rank': 6,    'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'assets',                'label': 'Assets',                     'rank': 7,    'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'current-benefits',      'label': 'Current Benefits',           'rank': 8,    'cesn': 9,    'cesn_home': 10,   'cesn_rent': 10},
    {'slug': 'additional-resources',  'label': 'Additional Resources',       'rank': 9,    'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'referral-source',       'label': 'Referral Source',            'rank': none, 'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'sign-up',               'label': 'Sign Up',                    'rank': 10,   'cesn': none, 'cesn_home': none, 'cesn_rent': none},
    {'slug': 'confirm-information',   'label': 'Confirm Information',         'rank': 11,   'cesn': 10,   'cesn_home': 11,   'cesn_rent': 11},
    {'slug': 'results',               'label': 'Reached Results',            'rank': 12,   'cesn': 11,   'cesn_home': 12,   'cesn_rent': 12},
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


{# SQL rows (path, step, label, rank) for the per-path CESN funnels: one row per
   (step, path) the step is on. Currently unused — kept for a future per-path split. #}
{% macro screener_cesn_step_ladder() %}
    {%- set paths = [('homeowner', 'cesn_home'), ('renter', 'cesn_rent')] %}
    {%- set rows = [] %}
    {# rank 0 = the synthetic form-start rung both paths share (the funnel top). #}
    {%- for path_name, _ in paths %}
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


{# SQL rows (step, label, rank) for the combined CESN funnel — the steps common
   to both paths (the appliance and energy-expenses steps, exclusive to one path,
   are excluded). rank 0 is the synthetic form-start rung. #}
{% macro screener_cesn_combined_ladder() %}
    {%- set rows = [('__form_start__', 'Started Screener', 0)] %}
    {%- for step in _screener_steps() %}
        {%- if step.cesn is not none %}
            {%- do rows.append((step.slug, step.label, step.cesn)) %}
        {%- endif %}
    {%- endfor %}
    {%- for slug, label, rank in rows %}
    select
        '{{ slug }}' as screener_step_name,
        '{{ label | replace("'", "\\'") }}' as screener_step_label,
        {{ rank }} as funnel_rank
    {%- if not loop.last %} union all {% endif %}
    {%- endfor %}
{% endmacro %}
