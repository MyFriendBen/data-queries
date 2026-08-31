# CESN-only tab: Heat Pump Journey (Tab 11).
#
# Cards for the CESN HVAC / heat-pump results-page journey, powered by the
# BigQuery heat-pump marts:
#   mart_heat_pump_engagement          — clicks + users per interaction (Story 1/3)
#   mart_heat_pump_calculator_funnel   — impact-calculator step funnel (Story 2)
#   mart_heat_pump_calculator_errors   — errors by type (Story 2)
#   mart_heat_pump_calculator_results  — one row per screening that saw results,
#                                        with the contractor-search cohort flag
#                                        and emissions in tons / forest acres (Story 7)
#   mart_heat_pump_user_journey        — per-uid milestone flags + first/last
#                                        section (Stories 5/6)
#
# All cards are for_each = local.ga_tenants_enabled to match the other BigQuery
# screener cards, but are only PLACED on the dashboard for "cesn" (via the layout
# gate in metabase.tf, keyed on tenant_has_tab[...]["heat_pump_energy_journey"]).
# CESN is the only tenant with the tab, and CESN is the only screener_state that
# emits heat_pump_* events, so every card filters screener_state = 'cesn'.
#
# Date filtering mirrors the other BigQuery cards: an epoch floor plus the optional
# {{start_date}}/{{end_date}} template tags (local.ga_date_tags), mapped onto the
# shared dashboard date filter in the layout block at the bottom.
#
# Partner decisions baked in here (see MFB-1182): trends are WEEKLY, emissions are
# metric tons plus the forest-acre equivalency the product shows, savings/emissions
# are split by whether the screening went on to a contractor search, and any group
# smaller than hp_min_group_size is suppressed on segment-level cards.

locals {
  hp_state_filter = "screener_state = 'cesn'"

  # Suppress groups smaller than this on cards that slice people into segments
  # (savings bands, and later the income / region filters). Raw interaction counts
  # are not suppressed — they identify nobody, and at CESN volume suppressing them
  # would empty the tab.
  hp_min_group_size = 5

  # Story 4 segmentation filters. Plain text variables rather than Metabase field
  # filters, for the same reason the date filters are: the BigQuery driver mangles
  # the column reference a field filter generates. Each clause is optional, so an
  # unset filter drops out of the SQL entirely.
  hp_segment_tags = {
    income_band = {
      id             = "hp_income_band_filter"
      name           = "income_band"
      "display-name" = "Income Band"
      type           = "text"
    }
    region = {
      id             = "hp_region_filter"
      name           = "region"
      "display-name" = "Region"
      type           = "text"
    }
    utility = {
      id             = "hp_utility_filter"
      name           = "utility"
      "display-name" = "Utility"
      type           = "text"
    }
  }

  # ── Story 1 & 3: what users click on the HVAC page + contractor lookups ──────
  # Clicks and distinct users per interaction. PDF pages sort naturally via
  # interaction_sort so "page 2" precedes "page 10".
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
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    GROUP BY interaction, interaction_sort
    ORDER BY interaction_sort, `Clicks` DESC
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
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    GROUP BY interaction
    ORDER BY `% of viewers who clicked` DESC
  SQL

  # ── Story 2: impact-calculator funnel ───────────────────────────────────────
  # Distinct users reaching each calculator stage, in funnel order. The errors
  # stage (funnel_rank 10) is excluded here — it's off-funnel and gets its own
  # card below. clicked_calculate (button pressed) precedes calculate_impact
  # (passed validation); the drop between them is validation failures.
  hp_sql_calculator_funnel = <<-SQL
    WITH agg AS (
      SELECT stage, funnel_rank, SUM(users) AS users
      FROM `${local.bq_dataset}.mart_heat_pump_calculator_funnel`
      WHERE ${local.hp_state_filter}
        AND funnel_rank < 10
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
      GROUP BY stage, funnel_rank
    )
    SELECT
      CASE stage
        WHEN 'household_type'     THEN 'Household type'
        WHEN 'address'            THEN 'Address'
        WHEN 'heating_fuel'       THEN 'Heating fuel'
        WHEN 'water_heating'      THEN 'Water heating'
        WHEN 'project_type'       THEN 'Project type'
        WHEN 'clicked_calculate'  THEN 'Clicked Calculate impact'
        WHEN 'calculate_impact'   THEN 'Passed validation'
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
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    GROUP BY error_label
    ORDER BY `Errors` DESC
  SQL

  # ── Story 5: page-level drop-off ────────────────────────────────────────────
  # Debra's chosen main view for "order in which people click through". Distinct
  # screenings reaching each milestone of the page journey, in order, so the
  # weakest link is visible. Built from the per-uid journey mart, so a screening
  # is counted once no matter how many times it clicked.
  hp_sql_page_funnel = <<-SQL
    WITH j AS (
      SELECT *
      FROM `${local.bq_dataset}.mart_heat_pump_user_journey`
      WHERE ${local.hp_state_filter}
        AND first_event_date >= DATE('${local.screener_analytics_epoch}')
        [[AND first_event_date >= CAST({{start_date}} AS DATE)]]
        [[AND first_event_date <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    )
    SELECT `Stage`, `Screenings` FROM (
      SELECT 'Reached the heat pump section' AS `Stage`, COUNT(*) AS `Screenings`, 1 AS o FROM j
      UNION ALL
      SELECT 'Clicked "Learn more"', COUNTIF(clicked_learn_more), 2 FROM j
      UNION ALL
      SELECT 'Clicked "Calculate impact"', COUNTIF(clicked_calculate_impact_cta), 3 FROM j
      UNION ALL
      SELECT 'Engaged the calculator', COUNTIF(engaged_calculator), 4 FROM j
      UNION ALL
      SELECT 'Saw calculator results', COUNTIF(saw_calculator_results), 5 FROM j
      UNION ALL
      SELECT 'Opened the contractor PDF', COUNTIF(opened_contractor_pdf), 6 FROM j
      UNION ALL
      SELECT 'Reached a contractor search', COUNTIF(reached_contractor_search), 7 FROM j
    )
    ORDER BY o
  SQL

  # ── Story 5: where journeys start and end ───────────────────────────────────
  # The companion view Debra asked for beside the drop-off chart: the section a
  # screening engaged with FIRST, and the last one it touched before leaving.
  hp_sql_journey_start_end = <<-SQL
    WITH j AS (
      SELECT first_section, last_section
      FROM `${local.bq_dataset}.mart_heat_pump_user_journey`
      WHERE ${local.hp_state_filter}
        AND first_event_date >= DATE('${local.screener_analytics_epoch}')
        [[AND first_event_date >= CAST({{start_date}} AS DATE)]]
        [[AND first_event_date <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    ),
    labelled AS (
      SELECT
        CASE section
          WHEN 'why_heat_pump'        THEN 'Why get a heat pump?'
          WHEN 'bills_impact'         THEN 'Will it impact my bills?'
          WHEN 'find_contractor_card' THEN 'Whom should I hire?'
          WHEN 'connect_now_page'     THEN 'Connect now page'
          WHEN 'rebates'              THEN 'Rebates'
          WHEN 'calculator'           THEN 'Impact calculator'
          WHEN 'contractor_pdf'       THEN 'Contractor tips PDF'
          ELSE '(unknown)'
        END AS `Section`,
        journey_position
      FROM (
        SELECT first_section AS section, 'Started here' AS journey_position FROM j WHERE first_section IS NOT NULL
        UNION ALL
        SELECT last_section, 'Ended here' FROM j WHERE last_section IS NOT NULL
      )
    )
    SELECT `Section`, journey_position AS `Position`, COUNT(*) AS `Screenings`
    FROM labelled
    GROUP BY `Section`, `Position`
    ORDER BY `Screenings` DESC
  SQL

  # ── Story 6: contractor-search correlation ──────────────────────────────────
  # Of users who reached a contractor search, what share also clicked "Learn more"
  # and what share engaged the impact calculator. The per-uid journey mart makes
  # each user one row, so these are clean subset shares.
  hp_sql_contractor_correlation = <<-SQL
    WITH reached AS (
      SELECT clicked_learn_more, engaged_calculator, saw_calculator_results, opened_contractor_pdf
      FROM `${local.bq_dataset}.mart_heat_pump_user_journey`
      WHERE ${local.hp_state_filter}
        AND reached_contractor_search
        AND first_event_date >= DATE('${local.screener_analytics_epoch}')
        [[AND first_event_date >= CAST({{start_date}} AS DATE)]]
        [[AND first_event_date <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    )
    SELECT `Cohort`, `% of contractor-search users` FROM (
      SELECT 'Also clicked "Learn more"' AS `Cohort`,
        ROUND(COUNTIF(clicked_learn_more) * 100.0 / NULLIF(COUNT(*), 0), 1) AS `% of contractor-search users`,
        1 AS o
      FROM reached
      UNION ALL
      SELECT 'Also engaged the calculator',
        ROUND(COUNTIF(engaged_calculator) * 100.0 / NULLIF(COUNT(*), 0), 1), 2
      FROM reached
      UNION ALL
      SELECT 'Also saw calculator results',
        ROUND(COUNTIF(saw_calculator_results) * 100.0 / NULLIF(COUNT(*), 0), 1), 3
      FROM reached
      UNION ALL
      SELECT 'Also opened the contractor PDF',
        ROUND(COUNTIF(opened_contractor_pdf) * 100.0 / NULLIF(COUNT(*), 0), 1), 4
      FROM reached
    )
    ORDER BY o
  SQL

  # ── Story 7: annual bill savings trend ──────────────────────────────────────
  # Weekly MEDIAN of the per-screening estimated annual saving, split by whether
  # the screening went on to a contractor search. The AC asks for the trend among
  # contractor-search users; the second series is everyone else, so the comparison
  # answers "do bigger savings actually move people to act?".
  # The mart already flips the sign, so a positive number is a saving.
  hp_sql_savings_trend = <<-SQL
    SELECT
      event_week AS `Week`,
      CASE WHEN reached_contractor_search
        THEN 'Went to a contractor search'
        ELSE 'Did not'
      END AS `Cohort`,
      ROUND(APPROX_QUANTILES(annual_bill_savings, 100 IGNORE NULLS)[OFFSET(50)], 2)
        AS `Median annual savings ($)`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND annual_bill_savings IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    GROUP BY `Week`, `Cohort`
    ORDER BY `Week`, `Cohort`
  SQL

  # ── Story 7: annual emissions reduction trend ───────────────────────────────
  # Metric tons CO2e, Debra's requested unit. Same weekly median + cohort split.
  hp_sql_emissions_trend = <<-SQL
    SELECT
      event_week AS `Week`,
      CASE WHEN reached_contractor_search
        THEN 'Went to a contractor search'
        ELSE 'Did not'
      END AS `Cohort`,
      ROUND(APPROX_QUANTILES(annual_emissions_reduction_tons, 100 IGNORE NULLS)[OFFSET(50)], 2)
        AS `Median annual reduction (metric tons CO2e)`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND annual_emissions_reduction_tons IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    GROUP BY `Week`, `Cohort`
    ORDER BY `Week`, `Cohort`
  SQL

  # ── Story 7: headline equivalency ───────────────────────────────────────────
  # The number a program manager quotes. Same EPA equivalency the results page
  # shows ("acres of U.S. forests in one year"), totalled over the date range.
  hp_sql_emissions_equivalency = <<-SQL
    SELECT
      ROUND(SUM(annual_emissions_forest_acres), 1) AS `Acres of U.S. forest (one year)`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND annual_emissions_forest_acres IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
  SQL

  # ── Story 7: does a bigger estimate drive action? ───────────────────────────
  # Debra's follow-up question. Buckets screenings by the size of the saving they
  # were shown, then reports what share of each bucket went on to a contractor
  # search. Buckets under hp_min_group_size are suppressed.
  hp_sql_savings_band_conversion = <<-SQL
    WITH banded AS (
      SELECT
        CASE
          WHEN annual_bill_savings < 0    THEN 'No saving (costs more)'
          WHEN annual_bill_savings < 250  THEN 'Under $250'
          WHEN annual_bill_savings < 500  THEN '$250–$499'
          WHEN annual_bill_savings < 1000 THEN '$500–$999'
          ELSE '$1,000+'
        END AS band,
        CASE
          WHEN annual_bill_savings < 0    THEN 1
          WHEN annual_bill_savings < 250  THEN 2
          WHEN annual_bill_savings < 500  THEN 3
          WHEN annual_bill_savings < 1000 THEN 4
          ELSE 5
        END AS band_sort,
        reached_contractor_search
      FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
      WHERE ${local.hp_state_filter}
        AND annual_bill_savings IS NOT NULL
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
    )
    SELECT
      band AS `Estimated annual saving`,
      COUNT(*) AS `Screenings`,
      ROUND(COUNTIF(reached_contractor_search) * 100.0 / NULLIF(COUNT(*), 0), 1)
        AS `% who searched for a contractor`
    FROM banded
    GROUP BY band, band_sort
    HAVING COUNT(*) >= ${local.hp_min_group_size}
    ORDER BY band_sort
  SQL
}

# ── Cards ─────────────────────────────────────────────────────────────────────

resource "metabase_card" "hp_engagement" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "HVAC Page Engagement"
    description         = "Clicks and unique users per interaction on the heat-pump journey: the 'Learn more' / 'Learn how to apply' links, the Calculate impact and Connect now CTAs, the two contractor searches, and the contractor-tips PDF broken out page by page."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_engagement
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
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
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
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

resource "metabase_card" "hp_page_funnel" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Heat Pump Journey Drop-Off"
    description         = "Distinct screenings reaching each milestone of the HVAC page journey, in order, so you can see where people fall away on the path toward contacting a contractor. Counted once per screening."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_page_funnel
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["Stage"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_journey_start_end" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Where Journeys Start and End"
    description         = "The section each screening engaged with first, and the last section it touched before leaving. Read alongside the drop-off chart: a section that is often the last one touched is where people give up."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_journey_start_end
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Section", "Position"]
      "graph.metrics"     = ["Screenings"]
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
    description         = "Unique users reaching each step of the impact calculator, in order: household type → address → heating fuel → water heating → project type → Calculate impact → results shown → edit after results. The drop between 'Clicked Calculate impact' and 'Passed validation' is submissions that failed validation."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_calculator_funnel
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
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
    description         = "Calculator errors thrown, broken out by type: unsupported address, invalid response from the calculator, form validation, or other error."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_calculator_errors
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
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

resource "metabase_card" "hp_contractor_correlation" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Contractor-Search Users: Info Consumed"
    description         = "Of screenings that reached a contractor search (Power Ahead Colorado or Love Electric), the share that also clicked 'Learn more', engaged the impact calculator, saw results, or opened the contractor-tips PDF."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_contractor_correlation
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
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

resource "metabase_card" "hp_savings_trend" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Estimated Annual Bill Savings (weekly median)"
    description         = "Weekly median of the calculator's estimated annual bill saving, split by whether the screening went on to a contractor search. A gap between the two lines means the size of the estimate is influencing whether people act on it."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_savings_trend
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "line"
    visualization_settings = {
      "graph.dimensions" = ["Week", "Cohort"]
      "graph.metrics"    = ["Median annual savings ($)"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_emissions_trend" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Estimated Annual Emissions Reduction (weekly median)"
    description         = "Weekly median of the calculator's estimated annual emissions reduction in metric tons of CO2e, split by whether the screening went on to a contractor search. Converted from the pounds the calculator returns using the EPA factor the results page uses (2,204.62 lb per metric ton)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_emissions_trend
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "line"
    visualization_settings = {
      "graph.dimensions" = ["Week", "Cohort"]
      "graph.metrics"    = ["Median annual reduction (metric tons CO2e)"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_emissions_equivalency" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Total Emissions Impact (forest acres)"
    description         = "Every estimated annual emissions reduction in the selected period, added up and expressed as the EPA equivalency the results page shows users: acres of average U.S. forest sequestering carbon for one year. This is modelled potential impact from the calculator, not verified installations."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_emissions_equivalency
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display                = "scalar"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

resource "metabase_card" "hp_savings_band_conversion" {
  for_each = local.ga_tenants_enabled
  json = jsonencode({
    name                = "Does a Bigger Estimate Drive Action?"
    description         = "Screenings bucketed by the size of the annual saving they were shown, and the share of each bucket that went on to search for a contractor. Buckets with fewer than ${local.hp_min_group_size} screenings are hidden."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_savings_band_conversion
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Estimated annual saving"]
      "graph.metrics"     = ["% who searched for a contractor"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ── Layout (placed on tab 11 for cesn only) ─────────────────────────────────────
#
# Every card is date-filtered, so each dashcard maps the shared
# ga_start_date_filter / ga_end_date_filter parameters onto its start_date /
# end_date template-tags — same wiring as the screener tabs. Without these the
# cards silently ignore the dashboard date picker and always read all-time.
#
# Cards must be ordered by dashboard_tab_id then row ascending to avoid the
# provider "inconsistent result" error on cards_json round-trip comparison.

locals {
  # Reused on every dashcard below; Terraform has no functions, so the pair is
  # built per card from its own id.
  tenant_dashboard_heat_pump_layout = concat(
    # Row 0: "data starts <epoch>" banner, matching the other analytics tabs.
    [local.tenant_screener_epoch_note_card[11]],
    [
      # Row 2: HVAC page engagement (left) | calculator errors (right)
      {
        card_id          = tonumber(metabase_card.hp_engagement["cesn"].id)
        dashboard_tab_id = 11
        row              = 2
        col              = 0
        size_x           = 18
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
        dashboard_tab_id = 11
        row              = 2
        col              = 18
        size_x           = 6
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 9: click-through rate (full width)
      {
        card_id          = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
        dashboard_tab_id = 11
        row              = 9
        col              = 0
        size_x           = 24
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 16: page drop-off (left) | where journeys start and end (right)
      {
        card_id          = tonumber(metabase_card.hp_page_funnel["cesn"].id)
        dashboard_tab_id = 11
        row              = 16
        col              = 0
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
        dashboard_tab_id = 11
        row              = 16
        col              = 12
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 24: impact calculator funnel (left) | contractor correlation (right)
      {
        card_id          = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
        dashboard_tab_id = 11
        row              = 24
        col              = 0
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
        dashboard_tab_id = 11
        row              = 24
        col              = 12
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 32: savings trend (left) | emissions trend (right)
      {
        card_id          = tonumber(metabase_card.hp_savings_trend["cesn"].id)
        dashboard_tab_id = 11
        row              = 32
        col              = 0
        size_x           = 12
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
        dashboard_tab_id = 11
        row              = 32
        col              = 12
        size_x           = 12
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 39: savings-band conversion (left) | forest-acre equivalency (right)
      {
        card_id          = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
        dashboard_tab_id = 11
        row              = 39
        col              = 0
        size_x           = 18
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
        dashboard_tab_id = 11
        row              = 39
        col              = 18
        size_x           = 6
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
    ]
  )
}
