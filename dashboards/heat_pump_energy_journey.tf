# CESN-only tab: Heat Pump Journey (Tab 11).
#
# Cards for the CESN HVAC / heat-pump results-page journey, powered by the
# BigQuery heat-pump marts:
#   mart_heat_pump_engagement          — clicks + users per interaction (Story 1/3)
#   mart_heat_pump_calculator_funnel   — impact-calculator step funnel (Story 2)
#   mart_heat_pump_calculator_results  — computed savings / emissions (Story 7)
#   mart_heat_pump_user_journey        — per-uid milestone flags (Story 5/6)
#
# All cards are for_each = local.ga_tenants_enabled to match the other BigQuery
# screener cards, but are only PLACED on the dashboard for "cesn" (via the layout
# gate in metabase.tf, keyed on tenant_has_tab[...]["heat_pump_energy_journey"]).
# CESN is the only tenant with the tab, and CESN is the only screener_state that
# emits heat_pump_* events, so every card filters screener_state = 'cesn'.
#
# Date filtering mirrors the other BigQuery cards: an epoch floor plus the optional
# {{start_date}}/{{end_date}} template tags (local.ga_date_tags).

locals {
  hp_state_filter = "screener_state = 'cesn'"

  # ── Story 1 & 3: what users click on the HVAC page + contractor lookups ──────
  # Clicks and distinct users per interaction, most-clicked first. One bar per
  # interaction label from the engagement mart.
  hp_sql_engagement = <<-SQL
    SELECT
      interaction AS `Interaction`,
      SUM(total_clicks) AS `Clicks`,
      SUM(users) AS `Users`
    FROM `${local.bq_dataset}.mart_heat_pump_engagement`
    WHERE ${local.hp_state_filter}
      AND interaction IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY interaction
    ORDER BY `Clicks` DESC
  SQL

  # ── Story 1 & 3: click-through rate ─────────────────────────────────────────
  # % of users who SAW a section that then clicked its element. Recomputed from
  # summed users / view_users over the range (not an average of daily rates), so
  # the denominator is the section_view impression, not raw clicks.
  hp_sql_click_through_rate = <<-SQL
    SELECT
      interaction AS `Interaction`,
      ROUND(SUM(users) * 100.0 / NULLIF(SUM(view_users), 0), 1) AS `% of viewers who clicked`
    FROM `${local.bq_dataset}.mart_heat_pump_engagement`
    WHERE ${local.hp_state_filter}
      AND interaction IS NOT NULL
      AND view_users IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY interaction
    ORDER BY `% of viewers who clicked` DESC
  SQL

  # ── Story 2: impact-calculator funnel ───────────────────────────────────────
  # Distinct users reaching each calculator stage, in funnel order. The errors
  # stage (funnel_rank 9) is excluded here — it's off-funnel and gets its own
  # scorecard below.
  hp_sql_calculator_funnel = <<-SQL
    WITH agg AS (
      SELECT stage, funnel_rank, SUM(users) AS users
      FROM `${local.bq_dataset}.mart_heat_pump_calculator_funnel`
      WHERE ${local.hp_state_filter}
        AND funnel_rank < 9
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY stage, funnel_rank
    )
    SELECT
      CASE stage
        WHEN 'household_type'     THEN 'Household type'
        WHEN 'address'            THEN 'Address'
        WHEN 'heating_fuel'       THEN 'Heating fuel'
        WHEN 'water_heating'      THEN 'Water heating'
        WHEN 'project_type'       THEN 'Project type'
        WHEN 'calculate_impact'   THEN 'Calculate impact'
        WHEN 'results_shown'      THEN 'Results shown'
        WHEN 'edit_after_results' THEN 'Edit after results'
      END AS `Stage`,
      users AS `Users`
    FROM agg
    ORDER BY funnel_rank
  SQL

  # ── Story 2: calculator errors, by type ─────────────────────────────────────
  hp_sql_calculator_errors = <<-SQL
    SELECT
      error_label AS `Error`,
      SUM(total_errors) AS `Errors`,
      SUM(users) AS `Users`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_errors`
    WHERE ${local.hp_state_filter}
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY error_label
    ORDER BY `Errors` DESC
  SQL

  # ── Story 7: annual bill savings trend ──────────────────────────────────────
  # Daily median of the per-screening median bill delta, sign-flipped so a saving
  # reads positive (the mart stores a negative delta as a saving).
  hp_sql_savings_trend = <<-SQL
    SELECT
      event_date_parsed AS `Date`,
      ROUND(-1 * AVG(median_annual_bill_delta), 2) AS `Median annual savings ($)`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND median_annual_bill_delta IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY event_date_parsed
    ORDER BY event_date_parsed
  SQL

  # ── Story 7: annual emissions reduction trend ───────────────────────────────
  hp_sql_emissions_trend = <<-SQL
    SELECT
      event_date_parsed AS `Date`,
      ROUND(-1 * AVG(median_annual_emissions_delta), 2) AS `Median annual emissions reduction`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND median_annual_emissions_delta IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY event_date_parsed
    ORDER BY event_date_parsed
  SQL

  # ── Story 6: contractor-search correlation ──────────────────────────────────
  # Of users who reached a contractor search, what share also clicked "Learn more"
  # and what share engaged the impact calculator. The per-uid journey mart makes
  # each user one row, so these are clean subset shares.
  hp_sql_contractor_correlation = <<-SQL
    WITH reached AS (
      SELECT clicked_learn_more, engaged_calculator
      FROM `${local.bq_dataset}.mart_heat_pump_user_journey`
      WHERE ${local.hp_state_filter}
        AND reached_contractor_search
    )
    SELECT `Cohort`, `% of contractor-search users` FROM (
      SELECT 'Also clicked "Learn more"' AS `Cohort`,
        ROUND(COUNTIF(clicked_learn_more) * 100.0 / NULLIF(COUNT(*), 0), 1) AS `% of contractor-search users`,
        1 AS o
      FROM reached
      UNION ALL
      SELECT 'Also engaged the calculator',
        ROUND(COUNTIF(engaged_calculator) * 100.0 / NULLIF(COUNT(*), 0), 1),
        2
      FROM reached
    )
    ORDER BY o
  SQL
}

# ── Cards ─────────────────────────────────────────────────────────────────────

resource "metabase_card" "hp_engagement" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "HVAC Page Engagement"
    description         = "Clicks and unique users per interaction on the heat-pump journey: the two 'Learn more'/'Learn how to apply' links, the Calculate impact and Connect now CTAs, the two contractor searches, and the contractor-tips PDF."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_engagement
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Interaction"]
      "graph.metrics"     = ["Clicks", "Users"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_click_through_rate" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "HVAC Page Click-Through Rate"
    description         = "Of the users who saw each section, the percent who clicked its link or CTA. Denominator is the section-view impression, so this is a true click-through rate, not a share of clicks."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_click_through_rate
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Interaction"]
      "graph.metrics"     = ["% of viewers who clicked"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_calculator_funnel" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Impact Calculator Funnel"
    description         = "Unique users reaching each step of the impact calculator, in order: household type → address → heating fuel → water heating → project type → Calculate impact → results shown → edit after results. Shows where users drop off."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_calculator_funnel
        template-tags = local.ga_date_tags
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["Stage"]
      "graph.metrics"    = ["Users"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_calculator_errors" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Impact Calculator Errors by Type"
    description         = "Calculator errors thrown, broken out by type: unsupported address, invalid response from the calculator, or other error."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_calculator_errors
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Error"]
      "graph.metrics"     = ["Errors", "Users"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_savings_trend" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Estimated Annual Bill Savings (trend)"
    description         = "Daily median of the calculator's estimated annual bill savings across screenings that saw results. Higher is a larger estimated saving."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_savings_trend
        template-tags = local.ga_date_tags
      }
    }
    display = "line"
    visualization_settings = {
      "graph.dimensions" = ["Date"]
      "graph.metrics"    = ["Median annual savings ($)"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_emissions_trend" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Estimated Annual Emissions Reduction (trend)"
    description         = "Daily median of the calculator's estimated annual emissions reduction across screenings that saw results. Higher is a larger estimated reduction."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_emissions_trend
        template-tags = local.ga_date_tags
      }
    }
    display = "line"
    visualization_settings = {
      "graph.dimensions" = ["Date"]
      "graph.metrics"    = ["Median annual emissions reduction"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_contractor_correlation" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Contractor-Search Users: Info Consumed"
    description         = "Of users who reached a contractor search (Power Ahead Colorado or Love Electric), the share who also clicked 'Learn more' and the share who engaged the impact calculator."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_contractor_correlation
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Cohort"]
      "graph.metrics"     = ["% of contractor-search users"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ── Layout (placed on tab 11 for cesn only) ─────────────────────────────────────

locals {
  tenant_dashboard_heat_pump_layout = [
    # Row 0: HVAC page engagement (full width)
    {
      card_id                = tonumber(metabase_card.hp_engagement["cesn"].id)
      dashboard_tab_id       = 11
      row                    = 0
      col                    = 0
      size_x                 = 18
      size_y                 = 7
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    # Row 0: calculator errors scorecard (right)
    {
      card_id                = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
      dashboard_tab_id       = 11
      row                    = 0
      col                    = 18
      size_x                 = 6
      size_y                 = 7
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    # Row 7: click-through rate (full width)
    {
      card_id                = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
      dashboard_tab_id       = 11
      row                    = 7
      col                    = 0
      size_x                 = 24
      size_y                 = 7
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    # Row 14: impact calculator funnel (left) | contractor correlation (right)
    {
      card_id                = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
      dashboard_tab_id       = 11
      row                    = 14
      col                    = 0
      size_x                 = 12
      size_y                 = 8
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    {
      card_id                = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
      dashboard_tab_id       = 11
      row                    = 14
      col                    = 12
      size_x                 = 12
      size_y                 = 8
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    # Row 22: savings trend (left) | emissions trend (right)
    {
      card_id                = tonumber(metabase_card.hp_savings_trend["cesn"].id)
      dashboard_tab_id       = 11
      row                    = 22
      col                    = 0
      size_x                 = 12
      size_y                 = 7
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    {
      card_id                = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
      dashboard_tab_id       = 11
      row                    = 22
      col                    = 12
      size_x                 = 12
      size_y                 = 7
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
  ]
}
