{#
  Macro: screener_step_label

  Maps a screener step SLUG (the stable, language-neutral analytics id the FE
  emits via getStepAnalyticsId — e.g. 'household-members') to a human-readable
  Title Case label for dashboard display (e.g. 'Household Members').

  The slug is the FE contract; the pretty label is a presentation choice that
  belongs in the data layer, NOT the FE (a FE-emitted label would be English-only
  and would drift with UI copy, whereas the slug is stable + neutral). This macro
  is the single source of truth for that mapping so the marts that surface a step
  label (mart_screener_form_funnel, mart_screener_form_errors, mart_screener_help,
  and the step_ranks in the dashboard step-funnel SQL) don't each re-declare it.

  Unmapped / future slugs fall back to the raw slug so a new step never silently
  disappears from a funnel. Synthetic funnel rows ('__form_start__' /
  '__form_complete__') are intentionally NOT mapped here — they're funnel-shape
  sentinels, labeled by the consumer that uses them.

  Usage:  {{ screener_step_label('screener_step_name') }} as screener_step_label
#}

{% macro screener_step_label(column_name) %}
    case {{ column_name }}
        when 'language' then 'Language'
        when 'disclaimer' then 'Disclaimer'
        when 'select-state' then 'Select State'
        when 'zip-code' then 'Zip Code'
        when 'household-size' then 'Household Size'
        when 'household-basics' then 'Household Basics'
        when 'household-members' then 'Household & Member Details'
        when 'member-details' then 'Member Details'
        when 'expenses' then 'Expenses'
        when 'assets' then 'Assets'
        when 'current-benefits' then 'Current Benefits'
        when 'additional-resources' then 'Additional Resources'
        when 'referral-source' then 'Referral Source'
        when 'sign-up' then 'Sign Up'
        when 'confirm-information' then 'Confirm Information'
        when 'results' then 'Results'
        when 'cesn-electric-provider' then 'CESN Electric Provider'
        when 'cesn-gas-provider' then 'CESN Gas Provider'
        when 'cesn-energy-expenses' then 'CESN Energy Expenses'
        when 'cesn-appliances' then 'CESN Appliances'
        when 'cesn-utility-status' then 'CESN Utility Status'
        else {{ column_name }}
    end
{% endmacro %}
