{#
  LEFT JOIN onto int_screener_referrer, so a screener event mart can carry the
  partner referrer as a screener_referrer column (null when unreferred).
  Referrer dashboards scope every GA card with `screener_referrer IN (...)`, so
  each mart a referrer dashboard reads must select it, and an aggregated mart
  must also group by it. A key belongs to at most one referrer, so adding it to
  a GROUP BY splits rows without changing any total the tenant cards sum.

  key_type is 'screener' (key_expr is a screener_uid) or 'session' (key_expr is
  a to_json_string(struct(user_pseudo_id, ga_session_id)) session key).
#}
{% macro join_screener_referrer(key_type, key_expr, alias='referrer') %}
    left join {{ ref('int_screener_referrer') }} as {{ alias }}
        on {{ alias }}.key_type = '{{ key_type }}'
        and {{ alias }}.key = {{ key_expr }}
{% endmacro %}
