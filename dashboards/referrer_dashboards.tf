# =============================================================================
# Referrer dashboards — one map entry per partner
# =============================================================================
# A referrer dashboard is a partner inside a tenant's white label, NOT a tenant:
# cards query the tenant's connection (so white-label RLS limits rows to that
# state) and every card bakes in the partner's scope predicate. There are no
# editable parameters, and the viewer group has collection-read only with no
# ad-hoc DB query access (see permissions.tf), so a viewer sees exactly what is
# defined here and cannot broaden it.
#
# The card set is the compact partner shape first built for 211 Metro Chicago
# (chicago211_dashboard.tf). cu_denver, cpal and chicago211 predate this file
# and are still hand-written.
#
# To add a partner:
#   1. Add a chained metabase_collection in metabase.tf (collections can't use
#      for_each — Metabase races on concurrent creates, see the note there).
#   2. Add an entry to local.referrer_dashboards below.
# The viewer group, cards, dashboard and both permission graphs follow from the
# map. Members are still added to the viewer group by hand in the Metabase UI.
#
# Test and incomplete screens never reach these cards: int_complete_screener_data
# already filters completed = TRUE, is_test = FALSE, is_test_data = FALSE and
# partner IS DISTINCT FROM 'Test'.
# =============================================================================

locals {
  referrer_dashboards = {
    dpp = {
      display_name  = "Denver Preschool Program"
      tenant        = "co"
      collection_id = metabase_collection.dpp.id
      # The Referrer row's display name, which the mart's `partner` column
      # carries for both the ?referrer=dpp link and the referral dropdown. RLS on
      # the tenant connection keeps it from matching another state's referrer.
      # If the Referrer's name is edited in the admin, change it here too.
      partner_name = "Denver Preschool Program"
      # Extra SQL ANDed onto the scope (e.g. a county limit), or null.
      extra_predicate = null
      # ISO date; screens before it are excluded. null covers all history.
      launch_date = null
      # Completes "... for households reaching MyFriendBen through <audience>."
      audience = "the Denver Preschool Program"
      # ?referrer= codes, as the app sends them to GA4 (screener_referrer). Scopes
      # the Engagement tab; empty list = no Engagement tab.
      ga_referrer_codes = ["dpp"]
    }
  }

  # Full WHERE-clause scope per dashboard: partner, then any extra predicate
  # and launch date.
  referrer_scope = {
    for key, d in local.referrer_dashboards : key => join(" AND ", compact([
      "partner = '${d.partner_name}'",
      d.extra_predicate == null ? "" : d.extra_predicate,
      d.launch_date == null ? "" : "submission_date >= '${d.launch_date}'",
    ]))
  }

  # Scorecards share one shape: a single aggregate over the scoped mart.
  # `having_value` restricts to households with any value matched.
  referrer_scorecards = {
    completed_screeners = { name = "Respondents (Completed Screeners)", select = "count(*)", having_value = false, currency = false }
    total_benefits      = { name = "Total Annual Benefits $ Identified", select = "COALESCE(SUM(non_tax_credit_benefits_annual), 0)", having_value = false, currency = true }
    total_tax_credits   = { name = "Total Potential Tax Credits $", select = "COALESCE(SUM(tax_credits_annual), 0)", having_value = false, currency = true }
    total_combined      = { name = "Total Annual Value Identified (Benefits + Tax Credits)", select = "COALESCE(SUM(non_tax_credit_benefits_annual + tax_credits_annual), 0)", having_value = false, currency = true }
    highest_value       = { name = "Highest Annual Value / Household", select = "COALESCE(MAX(non_tax_credit_benefits_annual + tax_credits_annual), 0)", having_value = false, currency = true }
    median_value        = { name = "Median Annual Value / Household (of those matched)", select = "PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual + tax_credits_annual)", having_value = true, currency = true }
    lowest_value        = { name = "Lowest Annual Value / Household (of those matched)", select = "COALESCE(MIN(non_tax_credit_benefits_annual + tax_credits_annual), 0)", having_value = true, currency = true }
  }

  # Every card's JSON, keyed "<dashboard>/<card>". Built as strings so cards of
  # different shapes can share one for_each.
  referrer_card_json = merge([
    for key, d in local.referrer_dashboards : merge(
      {
        for card, s in local.referrer_scorecards : "${key}/${card}" => jsonencode(merge(local.global_scorecard_config, {
          name          = s.name
          collection_id = tonumber(d.collection_id)
          dataset_query = {
            type     = "native"
            database = tonumber(metabase_database.tenant_postgres[d.tenant].id)
            native = {
              query = "SELECT ${s.select} AS value FROM analytics.mart_screener_data WHERE ${local.referrer_scope[key]}${s.having_value ? " AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0" : ""}"
            }
          }
          visualization_settings = {
            "scalar.field"    = "value"
            "column_settings" = jsondecode(s.currency ? jsonencode({ "[\"name\",\"value\"]" = local.currency_format_0 }) : "{}")
          }
        }))
      },
      {
        "${key}/value_distribution" = jsonencode(merge(local.global_card_base_config, {
          name          = "Annual Value per Household — Distribution"
          description   = "How much annual benefit value each household reaching MyFriendBen through ${d.audience} could access, bucketed."
          collection_id = tonumber(d.collection_id)
          display       = "bar"
          dataset_query = {
            type     = "native"
            database = tonumber(metabase_database.tenant_postgres[d.tenant].id)
            native = {
              query = "WITH vals AS (SELECT non_tax_credit_benefits_annual + tax_credits_annual AS v FROM analytics.mart_screener_data WHERE ${local.referrer_scope[key]}) SELECT CASE WHEN v = 0 THEN '$0' WHEN v < 5000 THEN '$1-$4,999' WHEN v < 10000 THEN '$5,000-$9,999' WHEN v < 20000 THEN '$10,000-$19,999' WHEN v < 40000 THEN '$20,000-$39,999' ELSE '$40,000+' END AS bucket, count(*) AS households FROM vals GROUP BY 1 ORDER BY MIN(CASE WHEN v = 0 THEN 0 WHEN v < 5000 THEN 1 WHEN v < 10000 THEN 2 WHEN v < 20000 THEN 3 WHEN v < 40000 THEN 4 ELSE 5 END)"
            }
          }
          visualization_settings = {
            "graph.dimensions"        = ["BUCKET"]
            "graph.metrics"           = ["HOUSEHOLDS"]
            "graph.x_axis.title_text" = "Annual Value Identified"
            "graph.y_axis.title_text" = "Households"
            "graph.show_values"       = true
          }
        }))

        "${key}/monthly_screeners" = jsonencode(merge(local.global_card_base_config, {
          name          = "Completed Screeners by Month"
          collection_id = tonumber(d.collection_id)
          display       = "bar"
          dataset_query = {
            type     = "native"
            database = tonumber(metabase_database.tenant_postgres[d.tenant].id)
            native = {
              query = "SELECT DATE_TRUNC('month', submission_date)::date AS month, count(*) AS screeners FROM analytics.mart_screener_data WHERE ${local.referrer_scope[key]} GROUP BY 1 ORDER BY 1"
            }
          }
          visualization_settings = {
            "graph.dimensions"        = ["MONTH"]
            "graph.metrics"           = ["SCREENERS"]
            "graph.x_axis.title_text" = "Month"
            "graph.y_axis.title_text" = "Completed Screeners"
            "graph.show_values"       = true
          }
        }))

        # The shared qualified-benefits SQL with its optional [[...]] filters
        # stripped and the scope injected at every "WHERE 1 = 1" anchor (the CTE
        # and the denominator subquery both need it for correct percentages).
        "${key}/qualified_benefits_table" = jsonencode(merge(local.global_table_card_config, {
          name          = "What benefits did people qualify for?"
          description   = "Most common benefits matched for completed screeners from households reaching MyFriendBen through ${d.audience}."
          collection_id = tonumber(d.collection_id)
          dataset_query = {
            type     = "native"
            database = tonumber(metabase_database.tenant_postgres[d.tenant].id)
            native = {
              query = replace(
                replace(templatefile("${path.module}/sql/qualified_benefits.sql", {}), local._optional_clause_regex, ""),
                "WHERE 1 = 1",
                "WHERE 1 = 1 AND ${local.referrer_scope[key]}"
              )
            }
          }
          visualization_settings = merge(local.global_table_card_config.visualization_settings, {
            "table.column_widths" = [
              { "name" = "Benefit Name", "width" = 300 },
              { "name" = "# of Screeners", "width" = 120 },
              { "name" = "% of Screeners", "width" = 120 },
            ]
            "column_settings" = local.benefits_column_settings
          })
        }))
      }
    )
  ]...)

  # Engagement tab: the tenant dashboard's GA4 screener cards whose marts carry a
  # screener_uid or session_key, rebuilt from the same SQL (screener_analytics_sql.tf)
  # so partner and tenant numbers can't drift. Scoping goes through the tenant
  # cards' state-filter placeholders, so the tenant and Global cards are untouched.
  # `key` says which mart_screener_referrer key the card's mart joins on.
  # Presentation settings mirror the tenant cards in screener_analytics.tf.
  referrer_ga_cards = {
    results_viewed = {
      sql         = local.screener_sql_results_viewed
      key         = "screener"
      name        = "Results Viewed"
      description = "How many screenings reached the results page at least once. Counts each screening once, not total views."
      display     = "scalar"
      viz         = jsonencode({ "scalar.field" = "Results Viewed" })
    }
    completion_time = {
      sql         = local.screener_sql_completion_time
      key         = "screener"
      name        = "Completion Time (approx. median)"
      description = "Median time from starting a screener to reaching a clean results load. Half of screeners finish faster than this."
      display     = "scalar"
      viz         = jsonencode({ "scalar.field" = "Time to Completion" })
    }
    macro_funnel = {
      sql         = local.screener_sql_macro_funnel
      key         = "screener"
      name        = "Screener Conversion Funnel"
      description = "Of screeners created, how many reached results, viewed a program ('More info'), and clicked Apply. Each bar counts unique screeners. A screener is \"created\" as soon as a user passes the Terms & Conditions Disclaimer step."
      display     = "funnel"
      viz = jsonencode({
        "graph.dimensions" = ["Funnel Step"]
        "graph.metrics"    = ["Screenings"]
      })
    }
    sessions_per_screener = {
      sql         = local.screener_sql_sessions_per_screener
      key         = "screener"
      name        = "Sessions per Screener"
      description = "How many browsing sessions a screener spans — the share worked on in a single session vs. picked back up across return visits. Screeners spanning 4 or more sessions are grouped into 4+. Bars are % of all screeners and sum to 100%."
      display     = "bar"
      viz = jsonencode({
        "graph.dimensions"        = ["Sessions"]
        "graph.metrics"           = ["% of Screeners"]
        "graph.show_values"       = true
        "graph.x_axis.title_text" = "Sessions per Screener"
        "graph.x_axis.scale"      = "ordinal"
        "column_settings"         = { "[\"name\",\"% of Screeners\"]" = { suffix = "%" } }
        "series_settings"         = { "% of Screeners" = { color = "#b07aa1" } }
      })
    }
    results_revisits = {
      sql         = local.screener_sql_results_revisits
      key         = "screener"
      name        = "Results Views per Screening"
      description = "How many screenings loaded their results page once, twice, or 3+ times — a sign of people returning to a saved result."
      display     = "bar"
      viz = jsonencode({
        "graph.show_values"       = true
        "graph.dimensions"        = ["Times Viewed"]
        "graph.metrics"           = ["Screenings"]
        "graph.x_axis.title_text" = "Times Results Viewed"
        "graph.y_axis.decimals"   = 0
        "series_settings"         = { "Screenings" = { color = "#e8a33d" } }
      })
    }
    chrome_nav = {
      sql         = local.screener_sql_chrome_nav
      key         = "session"
      name        = "Header & Footer Links"
      description = "Of all sessions, the % that used each persistent header/footer element: the logo, the footer About/Privacy/Terms links, and the language switcher. Hover for the session count."
      display     = "row"
      viz = jsonencode({
        "graph.dimensions"      = ["Element"]
        "graph.metrics"         = ["% of Sessions"]
        "graph.show_values"     = true
        "column_settings"       = { "[\"name\",\"% of Sessions\"]" = { suffix = "%" } }
        "graph.tooltip_columns" = ["Sessions"]
        "series_settings"       = { "% of Sessions" = { color = "#76b7b2" } }
      })
    }
    footer_feedback_share = {
      sql         = local.screener_sql_footer_feedback_share
      key         = "session"
      name        = "Footer Feedback & Share"
      description = "Of all sessions, the % that clicked a footer support/share action: Report a Bug, Contact Us, or Share. Hover for the session count."
      display     = "row"
      viz = jsonencode({
        "graph.dimensions"      = ["Action"]
        "graph.metrics"         = ["% of Sessions"]
        "graph.show_values"     = true
        "column_settings"       = { "[\"name\",\"% of Sessions\"]" = { suffix = "%" } }
        "graph.tooltip_columns" = ["Sessions"]
        "series_settings"       = { "% of Sessions" = { color = "#f28e2b" } }
      })
    }
    social_clicks = {
      sql         = local.screener_sql_social_clicks
      key         = "session"
      name        = "Social Link Clicks"
      description = "Of all sessions, the % that clicked a footer social icon, by network. Hover for the session count."
      display     = "row"
      viz = jsonencode({
        "graph.dimensions"      = ["Network"]
        "graph.metrics"         = ["% of Sessions"]
        "graph.show_values"     = true
        "column_settings"       = { "[\"name\",\"% of Sessions\"]" = { suffix = "%" } }
        "graph.tooltip_columns" = ["Sessions"]
        "series_settings"       = { "% of Sessions" = { color = "#b07aa1" } }
      })
    }
  }

  # Dashboards that get the Engagement tab: BigQuery is on and codes are set.
  referrer_ga_dashboards = {
    for key, d in local.referrer_dashboards : key => d
    if var.bigquery_enabled && length(d.ga_referrer_codes) > 0
  }

  # The tenant state filter plus "this key belongs to one of the partner's codes",
  # substituted for both state-filter placeholders (CESN first: the plain one is
  # its prefix). The [[...]] date filters are stripped — referrer dashboards have
  # no editable parameters.
  referrer_ga_card_json = merge([
    for key, d in local.referrer_ga_dashboards : {
      for card, c in local.referrer_ga_cards : "${key}/${card}" => jsonencode(merge(local.global_card_base_config, {
        name          = c.name
        description   = c.description
        collection_id = tonumber(d.collection_id)
        display       = c.display
        dataset_query = {
          type     = "native"
          database = tonumber(metabase_database.bigquery[0].id)
          native = {
            query = replace(
              replace(
                replace(c.sql, local._optional_clause_regex, ""),
                "__STATE_FILTER_CESN__",
                "screener_state IN (${local.tenant_ga_state_filter[d.tenant]}) AND ${c.key == "screener" ? "screener_uid" : "session_key"} IN (SELECT key FROM `${local.bq_dataset}.mart_screener_referrer` WHERE key_type = '${c.key}' AND screener_referrer IN (${join(", ", [for code in d.ga_referrer_codes : "'${code}'"])}))"
              ),
              "__STATE_FILTER__",
              "screener_state IN (${local.tenant_ga_state_filter[d.tenant]}) AND ${c.key == "screener" ? "screener_uid" : "session_key"} IN (SELECT key FROM `${local.bq_dataset}.mart_screener_referrer` WHERE key_type = '${c.key}' AND screener_referrer IN (${join(", ", [for code in d.ga_referrer_codes : "'${code}'"])}))"
            )
          }
        }
        visualization_settings = jsondecode(c.viz)
      }))
    }
  ]...)

  # Engagement tab grid (tab 2), in row-then-col order.
  referrer_ga_layout = [
    { card = "results_viewed", row = 0, col = 0, size_x = 12, size_y = 4 },
    { card = "completion_time", row = 0, col = 12, size_x = 12, size_y = 4 },
    { card = "macro_funnel", row = 4, col = 0, size_x = 12, size_y = 8 },
    { card = "sessions_per_screener", row = 4, col = 12, size_x = 12, size_y = 8 },
    { card = "results_revisits", row = 12, col = 0, size_x = 12, size_y = 6 },
    { card = "chrome_nav", row = 12, col = 12, size_x = 12, size_y = 6 },
    { card = "footer_feedback_share", row = 18, col = 0, size_x = 12, size_y = 6 },
    { card = "social_clicks", row = 18, col = 12, size_x = 12, size_y = 6 },
  ]

  # Grid positions, shared by every referrer dashboard. The provider fails an
  # apply with "inconsistent result" unless cards_json is in the order Metabase
  # returns it: dashboard_tab_id, then row, then col. Keep this list in that order.
  referrer_dashboard_layout = [
    # Row 0 — raw totals
    { card = "completed_screeners", row = 0, col = 0, size_x = 6, size_y = 4 },
    { card = "total_benefits", row = 0, col = 6, size_x = 6, size_y = 4 },
    { card = "total_tax_credits", row = 0, col = 12, size_x = 6, size_y = 4 },
    { card = "total_combined", row = 0, col = 18, size_x = 6, size_y = 4 },
    # Row 4 — high / median / low per household
    { card = "highest_value", row = 4, col = 0, size_x = 8, size_y = 4 },
    { card = "median_value", row = 4, col = 8, size_x = 8, size_y = 4 },
    { card = "lowest_value", row = 4, col = 16, size_x = 8, size_y = 4 },
    # Row 8 — value distribution + monthly trend
    { card = "value_distribution", row = 8, col = 0, size_x = 12, size_y = 6 },
    { card = "monthly_screeners", row = 8, col = 12, size_x = 12, size_y = 6 },
    # Row 14 — program mix
    { card = "qualified_benefits_table", row = 14, col = 0, size_x = 24, size_y = 8 },
  ]
}

resource "metabase_permissions_group" "referrer" {
  for_each = local.referrer_dashboards

  name = "${each.value.display_name} Viewers"
}

resource "metabase_card" "referrer" {
  for_each = merge(local.referrer_card_json, local.referrer_ga_card_json)

  json = each.value
}

resource "metabase_dashboard" "referrer" {
  for_each = local.referrer_dashboards

  name                = "${each.value.display_name} Screener Impact"
  description         = "Aggregate impact of the MyFriendBen screener for households reaching it through ${each.value.audience}. Completed screeners only; no personal data."
  collection_id       = tonumber(each.value.collection_id)
  collection_position = 1

  tabs_json = jsonencode(concat(
    [{ id = 1, name = "Overview" }],
    contains(keys(local.referrer_ga_dashboards), each.key) ? [{ id = 2, name = "Engagement" }] : [],
  ))

  cards_json = jsonencode(concat(
    [
      for c in local.referrer_dashboard_layout : {
        card_id                = tonumber(metabase_card.referrer["${each.key}/${c.card}"].id)
        dashboard_tab_id       = 1
        row                    = c.row
        col                    = c.col
        size_x                 = c.size_x
        size_y                 = c.size_y
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      }
    ],
    [
      for c in local.referrer_ga_layout : {
        card_id                = tonumber(metabase_card.referrer["${each.key}/${c.card}"].id)
        dashboard_tab_id       = 2
        row                    = c.row
        col                    = c.col
        size_x                 = c.size_x
        size_y                 = c.size_y
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      } if contains(keys(local.referrer_ga_dashboards), each.key)
    ],
  ))
}
