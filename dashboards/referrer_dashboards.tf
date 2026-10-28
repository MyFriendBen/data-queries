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
# Tabs:
#   Overview             — the compact impact card set first built for 211 Metro
#                          Chicago, from the Postgres mart_screener_data.
#   Engagement Overview, — with engagement_tabs = true: every card on the
#   Results Page           tenant dashboard's tabs of the same name, in the same
#                          grid. Each card is the tenant card's JSON with
#                          `AND screener_referrer IN (<codes>)` added to its state
#                          filter, so a card added to or changed on the tenant
#                          tab shows up here on the next apply. A tenant card
#                          missing from referrer_tenant_ga_cards fails the plan.
#
# To add a partner:
#   1. Add a chained metabase_collection in metabase.tf (collections can't use
#      for_each — Metabase races on concurrent creates, see the note there).
#   2. Add an entry to local.referrer_dashboards below.
# The viewer group, cards, dashboard and both permission graphs follow from the
# map. Members are still added to the viewer group by hand in the Metabase UI.
#
# cu_denver and cpal stay hand-written: their card sets were built to each
# partner's request (CU Denver's student-household cards, CPAL's All Texas
# comparison tab) and don't share this shape.
#
# Test and incomplete screens never reach the Overview cards:
# int_complete_screener_data already filters completed = TRUE, is_test = FALSE,
# is_test_data = FALSE and partner IS DISTINCT FROM 'Test'.
# =============================================================================

locals {
  referrer_dashboards = {
    chicago211 = {
      display_name  = "211 Metro Chicago"
      tenant        = "il"
      collection_id = metabase_collection.chicago211.id
      # Referrer codes (programs_referrer.referrer_code) the partner's screens
      # arrive with: the ?referrer= link or the referral dropdown value.
      referrer_codes = ["211_metro_chicago"]
      # Cook County. Normalized both sides because county text arrives as either
      # "Cook" or "Cook County" — the same normalizer
      # mart_screener_household_attributes.sql uses. Not equivalent to a ZIP
      # allowlist in Illinois: some ZIPs map to more than one county and the
      # county is then the user's own selection (MFB-1885 §4).
      extra_predicate = "lower(regexp_replace(trim(county), '\\s+county$', '', 'i')) = 'cook'"
      launch_date     = var.chicago211_launch_date
      # Completes "... households reaching MyFriendBen through <audience>."
      audience        = "211 Metro Chicago (Cook County)"
      engagement_tabs = false
    }
    dpp = {
      display_name    = "Denver Preschool Program"
      tenant          = "co"
      collection_id   = metabase_collection.dpp.id
      referrer_codes  = ["dpp"]
      extra_predicate = null
      launch_date     = null
      audience        = "the Denver Preschool Program"
      engagement_tabs = true
    }
  }

  # SQL IN-list of each dashboard's codes. Codes are admin-entered slugs; the
  # check below keeps a quote from breaking out of the literal.
  referrer_codes_sql = {
    for key, d in local.referrer_dashboards : key => join(", ", [for c in d.referrer_codes : "'${c}'"])
  }

  # Overview scope: the partner's codes, then any extra predicate and launch
  # date. The CASE picks the code mart_screener_data's `partner` column is
  # derived from (int_complete_screener_data): the ?referrer= code, else the
  # referral dropdown value. Matching on code rather than the admin display name
  # means renaming a Referrer can't silently empty the cards.
  referrer_scope = {
    for key, d in local.referrer_dashboards : key => join(" AND ", compact([
      "(CASE WHEN TRIM(referrer_code) <> '' THEN referrer_code ELSE referral_source END) IN (${local.referrer_codes_sql[key]})",
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

  # Overview card JSON, keyed "<dashboard>/<card>". Built as strings so cards of
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

  # Every tenant screener card on the Engagement Overview (tab 10) and Results
  # Page (tab 8) tabs, by key. Add a card here when it is added to either tab;
  # until then the partner layout lookup below fails the plan.
  referrer_tenant_ga_cards = {
    # Engagement Overview
    completion_time       = metabase_card.screener_completion_time
    macro_funnel          = metabase_card.screener_macro_funnel
    sessions_per_screener = metabase_card.screener_sessions_per_screener
    chrome_nav            = metabase_card.screener_chrome_nav
    language_distribution = metabase_card.screener_language_distribution
    social_clicks         = metabase_card.screener_social_clicks
    footer_feedback_share = metabase_card.screener_footer_feedback_share
    # Results Page
    results_viewed                 = metabase_card.screener_results_viewed
    results_pct_eligible           = metabase_card.screener_results_pct_eligible
    results_error_rate             = metabase_card.screener_results_error_rate
    back_to_screener               = metabase_card.screener_back_to_screener
    results_revisits               = metabase_card.screener_results_revisits
    scroll_depth                   = metabase_card.screener_scroll_depth
    program_most_shown             = metabase_card.screener_program_most_shown
    program_engagement             = metabase_card.screener_program_engagement
    program_conversion             = metabase_card.screener_program_conversion
    filter_usage                   = metabase_card.screener_filter_usage
    get_help_clicks                = metabase_card.screener_get_help_clicks
    resources_tab_engagement       = metabase_card.screener_resources_tab_engagement
    additional_resources_edits     = metabase_card.screener_additional_resources_edits
    filter_usage_avg               = metabase_card.screener_filter_usage_avg
    more_help_avg                  = metabase_card.screener_more_help_avg
    resources_tab_avg              = metabase_card.screener_resources_tab_avg
    additional_resources_edits_avg = metabase_card.screener_additional_resources_edits_avg
    resource_engagement            = metabase_card.screener_resource_engagement
    navigator_engagement           = metabase_card.screener_navigator_engagement
    document_downloads             = metabase_card.screener_document_downloads
    more_help_resources            = metabase_card.screener_more_help_resources
    nps_distribution               = metabase_card.screener_nps_distribution
    nps_engagement                 = metabase_card.screener_nps_engagement
  }

  # Dashboards that get the engagement tabs: BigQuery is on and the tenant has
  # the screener cards.
  referrer_ga_dashboards = {
    for key, d in local.referrer_dashboards : key => d
    if d.engagement_tabs && contains(keys(local.ga_tenants_enabled), d.tenant)
  }

  # Partner copies of the tenant cards. Every tenant card filters each mart with
  # the same "screener_state IN (...)" predicate; the copy ANDs the partner's
  # codes onto every occurrence (each mart it reads carries screener_referrer,
  # see the join_screener_referrer dbt macro), drops the [[...]] date filters
  # and their template tags (no editable parameters), and moves into the
  # partner collection.
  referrer_ga_card_json = merge([
    for key, d in local.referrer_ga_dashboards : {
      for card, r in local.referrer_tenant_ga_cards : "${key}/${card}" => jsonencode(merge(jsondecode(r[d.tenant].json), {
        collection_id = tonumber(d.collection_id)
        dataset_query = merge(jsondecode(r[d.tenant].json).dataset_query, {
          native = {
            query = replace(
              replace(jsondecode(r[d.tenant].json).dataset_query.native.query, local._optional_clause_regex, ""),
              "screener_state IN (${local.tenant_ga_state_filter[d.tenant]})",
              "screener_state IN (${local.tenant_ga_state_filter[d.tenant]}) AND screener_referrer IN (${local.referrer_codes_sql[key]})"
            )
            template-tags = {}
          }
        })
      }))
    }
  ]...)

  # Tenant card id -> card key, per tenant, to rebuild the tenant grids with the
  # partner's cards.
  referrer_tenant_card_key_by_id = {
    for tenant in distinct([for d in local.referrer_ga_dashboards : d.tenant]) : tenant => {
      for card, r in local.referrer_tenant_ga_cards : r[tenant].id => card
    }
  }

  # Row 0 of both engagement tabs, in place of the tenant's epoch note.
  referrer_ga_note = {
    for key, d in local.referrer_ga_dashboards : key => join(" ", [
      "📊 **About this data** — These tabs count visits that arrived through ${d.display_name}'s MyFriendBen link, from when partner links were first tracked; there is no earlier history.",
      "The Overview tab also counts households that picked ${d.display_name} under \"How did you hear about us?\", so its totals can be higher.",
    ])
  }

  # Overview tab grid. The provider fails an apply with "inconsistent result"
  # unless cards_json is in the order Metabase returns it: dashboard_tab_id,
  # then row, then col. Keep this list in that order; the engagement tabs
  # inherit the tenant layouts' order.
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

  lifecycle {
    precondition {
      condition     = alltrue([for c in each.value.referrer_codes : can(regex("^[A-Za-z0-9_-]+$", c))])
      error_message = "Referrer codes for '${each.key}' must be letters, digits, '_' or '-'; they are interpolated into card SQL."
    }
  }
}

resource "metabase_card" "referrer" {
  for_each = merge(local.referrer_card_json, local.referrer_ga_card_json)

  json = each.value

  # replace() returns its input unchanged when the anchor is missing, which
  # would ship a card with no partner scope. Fail the plan instead.
  lifecycle {
    precondition {
      condition     = strcontains(each.value, "IN (${local.referrer_codes_sql[split("/", each.key)[0]]})")
      error_message = "Referrer card '${each.key}' has no partner scope: its SQL lost the \"WHERE 1 = 1\" or \"screener_state IN (...)\" anchor the scope is attached to."
    }
  }
}

resource "metabase_dashboard" "referrer" {
  for_each = local.referrer_dashboards

  name                = "${each.value.display_name} Screener Impact"
  description         = "Aggregate impact of the MyFriendBen screener for households reaching it through ${each.value.audience}. Overview counts completed screeners only; no personal data."
  collection_id       = tonumber(each.value.collection_id)
  collection_position = 1

  tabs_json = jsonencode(concat(
    [{ id = 1, name = "Overview" }],
    contains(keys(local.referrer_ga_dashboards), each.key) ? [
      { id = 2, name = "Engagement Overview" },
      { id = 3, name = "Results Page" },
    ] : [],
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
    # Engagement tabs: the tenant grids, note first (row 0), with each tenant
    # card swapped for the partner copy.
    flatten([
      for tab in [
        { id = 2, layout = local.tenant_dashboard_screener_overview_layout[each.value.tenant] },
        { id = 3, layout = local.tenant_dashboard_screener_results_layout[each.value.tenant] },
        ] : concat(
        [{
          card_id                = null
          dashboard_tab_id       = tab.id
          row                    = 0
          col                    = 0
          size_x                 = 24
          size_y                 = 2
          parameter_mappings     = []
          series                 = []
          visualization_settings = { virtual_card = { name = null, dataset_query = {}, display = "text", visualization_settings = {} }, text = local.referrer_ga_note[each.key] }
        }],
        [
          for dc in tab.layout : {
            card_id                = tonumber(metabase_card.referrer["${each.key}/${local.referrer_tenant_card_key_by_id[each.value.tenant][tostring(dc.card_id)]}"].id)
            dashboard_tab_id       = tab.id
            row                    = dc.row
            col                    = dc.col
            size_x                 = dc.size_x
            size_y                 = dc.size_y
            parameter_mappings     = []
            series                 = []
            visualization_settings = {}
          }
        ],
      ) if contains(keys(local.referrer_ga_dashboards), each.key)
    ]),
  ))
}

# 211 Metro Chicago moved onto the map from its hand-written
# chicago211_dashboard.tf; these keep its live group, cards and dashboard.
moved {
  from = metabase_permissions_group.chicago211
  to   = metabase_permissions_group.referrer["chicago211"]
}

moved {
  from = metabase_dashboard.chicago211
  to   = metabase_dashboard.referrer["chicago211"]
}

moved {
  from = metabase_card.chicago211_completed_screeners
  to   = metabase_card.referrer["chicago211/completed_screeners"]
}

moved {
  from = metabase_card.chicago211_total_benefits_dollars
  to   = metabase_card.referrer["chicago211/total_benefits"]
}

moved {
  from = metabase_card.chicago211_total_tax_credits
  to   = metabase_card.referrer["chicago211/total_tax_credits"]
}

moved {
  from = metabase_card.chicago211_total_combined
  to   = metabase_card.referrer["chicago211/total_combined"]
}

moved {
  from = metabase_card.chicago211_highest_household_value
  to   = metabase_card.referrer["chicago211/highest_value"]
}

moved {
  from = metabase_card.chicago211_median_household_value
  to   = metabase_card.referrer["chicago211/median_value"]
}

moved {
  from = metabase_card.chicago211_lowest_household_value
  to   = metabase_card.referrer["chicago211/lowest_value"]
}

moved {
  from = metabase_card.chicago211_value_distribution
  to   = metabase_card.referrer["chicago211/value_distribution"]
}

moved {
  from = metabase_card.chicago211_monthly_screeners
  to   = metabase_card.referrer["chicago211/monthly_screeners"]
}

moved {
  from = metabase_card.chicago211_qualified_benefits_table
  to   = metabase_card.referrer["chicago211/qualified_benefits_table"]
}
