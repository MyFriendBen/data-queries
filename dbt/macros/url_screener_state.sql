{#
  White label parsed from a screener page URL's first path segment
  (screener.myfriendben.org/<wl>/... and energysavings.colorado.gov/cesn/...).
  Restricted to the known slugs (screener_state_slugs var) so a non-wl first
  segment (e.g. 'step-1', 'select-state') doesn't masquerade as a state; null
  when the URL has no wl segment. Used to recover state for chrome events that
  can fire before the screener_state param is set.

  Matches the WHOLE first segment (up to the next slash / query / fragment) so a
  slug like 'co-tax-calculator' compares as itself and is correctly rejected,
  rather than truncating to a prefix that collides with 'co'.

  page_location_expr is a SQL expression evaluating to the page_location string.
#}
{% macro url_screener_state(page_location_expr) %}
    case
        when regexp_extract({{ page_location_expr }}, r'https?://[^/]+/([^/?#]+)')
            in ({{ "'" ~ var('screener_state_slugs') | join("', '") ~ "'" }})
        then regexp_extract({{ page_location_expr }}, r'https?://[^/]+/([^/?#]+)')
    end
{% endmacro %}
