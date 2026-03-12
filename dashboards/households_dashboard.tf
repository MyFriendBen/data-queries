# =============================================================================
# Households Dashboard Cards
# =============================================================================
#
# Recreates the "Households" page from the Looker Studio NC dashboard:
# https://lookerstudio.google.com/reporting/84ceeb5a-.../page/p_o3q7bcq1rd
#
# Data source: mart_households_dashboard (PostgreSQL analytics schema)
#   - One row per completed screener
#   - Uses tenant-specific RLS-filtered connections (metabase_database.tenant_postgres)
#
# These cards are placed into the "Households" tab (tab id = 4) of the main
# per-tenant dashboard defined in metabase.tf (metabase_dashboard.tenant_analytics).
#
# Cards:
#   KPIs (scalar):
#     1. Completed Screeners (count)
#     2. Median Household Size
#     3. Median Household Assets
#     4. Median Annual Income
#     5. Median Monthly Income
#     6. Median Monthly Expenses
#
#   Charts (bar):
#     7.  Ages of heads of household (% distribution, Census bins)
#     8.  Ages of all household members (% distribution, Census bins)
#     9.  Household size breakdown (% distribution, 1–8+)
#     10. Household income breakdown (% distribution, $0-15K … $100K+)
#     11. Household assets breakdown (% distribution, $0-1K … $50K+)
#
#   Charts (pie/donut):
#     12. Languages spoken
# =============================================================================

# ---------------------------------------------------------------------------
# KPI 1: Completed Screeners
# ---------------------------------------------------------------------------
resource "metabase_card" "households_completed_screeners" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "Completed Screeners"
    description         = "Total number of completed screeners"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native   = { query = "SELECT count(*) AS \"Completed Screeners\" FROM analytics.mart_households_dashboard;" }
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = {}
    parameters             = []
  })
}

# ---------------------------------------------------------------------------
# KPI 2: Median Household Size
# ---------------------------------------------------------------------------
resource "metabase_card" "households_median_size" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "Median Household Size"
    description         = "Median number of members per household"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native   = { query = "SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY household_size) AS \"Median Household Size\" FROM analytics.mart_households_dashboard;" }
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = {}
    parameters             = []
  })
}

# ---------------------------------------------------------------------------
# KPI 3: Median Household Assets
# ---------------------------------------------------------------------------
resource "metabase_card" "households_median_assets" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "Median Household Assets"
    description         = "Median household assets in dollars"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native   = { query = "SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY household_assets) AS \"Median Household Assets\" FROM analytics.mart_households_dashboard WHERE household_assets IS NOT NULL;" }
    }
    parameter_mappings = []
    display            = "scalar"
    visualization_settings = {
      "column_settings" = {
        "[\"name\",\"Median Household Assets\"]" = { "number_style" = "currency", "currency" = "USD", "currency_style" = "symbol", "decimals" = 0 }
      }
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# KPI 4: Median Annual Income
# ---------------------------------------------------------------------------
resource "metabase_card" "households_median_annual_income" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "Median Annual Income"
    description         = "Median annual household income"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native   = { query = "SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY annual_income) AS \"Median Annual Income\" FROM analytics.mart_households_dashboard WHERE annual_income IS NOT NULL;" }
    }
    parameter_mappings = []
    display            = "scalar"
    visualization_settings = {
      "column_settings" = {
        "[\"name\",\"Median Annual Income\"]" = { "number_style" = "currency", "currency" = "USD", "currency_style" = "symbol", "decimals" = 0 }
      }
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# KPI 5: Median Monthly Income
# ---------------------------------------------------------------------------
resource "metabase_card" "households_median_monthly_income" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "Median Monthly Income"
    description         = "Median monthly household income"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native   = { query = "SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY monthly_income) AS \"Median Monthly Income\" FROM analytics.mart_households_dashboard WHERE monthly_income IS NOT NULL;" }
    }
    parameter_mappings = []
    display            = "scalar"
    visualization_settings = {
      "column_settings" = {
        "[\"name\",\"Median Monthly Income\"]" = { "number_style" = "currency", "currency" = "USD", "currency_style" = "symbol", "decimals" = 0 }
      }
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# KPI 6: Median Monthly Expenses
# ---------------------------------------------------------------------------
resource "metabase_card" "households_median_monthly_expenses" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "Median Monthly Expenses"
    description         = "Median monthly household expenses"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native   = { query = "SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY monthly_expenses) AS \"Median Monthly Expenses\" FROM analytics.mart_households_dashboard WHERE monthly_expenses IS NOT NULL;" }
    }
    parameter_mappings = []
    display            = "scalar"
    visualization_settings = {
      "column_settings" = {
        "[\"name\",\"Median Monthly Expenses\"]" = { "number_style" = "currency", "currency" = "USD", "currency_style" = "symbol", "decimals" = 0 }
      }
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# Chart 7: Ages of Heads of Household (% bar chart)
# Census bins: 0-18, 19-24, 25-44, 45-64, 65+
# ---------------------------------------------------------------------------
resource "metabase_card" "households_head_age_distribution" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "What are the ages of the heads of household?"
    description         = "Age distribution of heads of household using Census Bureau bins"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native = { query = <<-SQL
          SELECT
            head_age_bin                                          AS "Age Group",
            head_age_bin_order                                    AS "Sort Order",
            count(*)                                             AS "Count",
            round(count(*) * 100.0 / sum(count(*)) OVER (), 1)  AS "Percentage"
          FROM analytics.mart_households_dashboard
          WHERE head_age_bin != 'Unknown'
          GROUP BY head_age_bin, head_age_bin_order
          ORDER BY head_age_bin_order;
        SQL
      }
    }
    parameter_mappings = []
    display            = "bar"
    visualization_settings = {
      "graph.dimensions"        = ["Age Group"]
      "graph.metrics"           = ["Percentage"]
      "graph.x_axis.title_text" = "Age Group"
      "graph.y_axis.title_text" = "% of Heads of Household"
      "graph.show_values"       = true
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# Chart 8: Ages of All Household Members (% bar chart)
# ---------------------------------------------------------------------------
resource "metabase_card" "households_all_member_age_distribution" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "What are the ages of all household members?"
    description         = "Age distribution across all household members using Census Bureau bins"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native = { query = <<-SQL
          WITH member_totals AS (
            SELECT sum(total_members) AS grand_total
            FROM analytics.mart_households_dashboard
          ),
          age_counts AS (
            SELECT
              '<5'    AS "Age Group", 1 AS sort_order, sum(members_age_lt5)    AS cnt FROM analytics.mart_households_dashboard
            UNION ALL
            SELECT '5-18',  2, sum(members_age_5_18)    FROM analytics.mart_households_dashboard
            UNION ALL
            SELECT '19-24', 3, sum(members_age_19_24)   FROM analytics.mart_households_dashboard
            UNION ALL
            SELECT '25-44', 4, sum(members_age_25_44)   FROM analytics.mart_households_dashboard
            UNION ALL
            SELECT '45-64', 5, sum(members_age_45_64)   FROM analytics.mart_households_dashboard
            UNION ALL
            SELECT '65+',   6, sum(members_age_65plus)  FROM analytics.mart_households_dashboard
          )
          SELECT
            ac."Age Group",
            ac.cnt              AS "Count",
            round(ac.cnt * 100.0 / mt.grand_total, 1) AS "Percentage"
          FROM age_counts ac, member_totals mt
          ORDER BY ac.sort_order;
        SQL
      }
    }
    parameter_mappings = []
    display            = "bar"
    visualization_settings = {
      "graph.dimensions"        = ["Age Group"]
      "graph.metrics"           = ["Percentage"]
      "graph.x_axis.title_text" = "Age Group"
      "graph.y_axis.title_text" = "% of All Members"
      "graph.show_values"       = true
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# Chart 9: Household Size Breakdown (% bar chart, 1–8+)
# ---------------------------------------------------------------------------
resource "metabase_card" "households_size_breakdown" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "What is the breakdown of household sizes?"
    description         = "Distribution of households by number of members"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native = { query = <<-SQL
          SELECT
            CASE WHEN household_size >= 8 THEN '8+' ELSE household_size::text END AS "Household Size",
            CASE WHEN household_size >= 8 THEN 8    ELSE household_size         END AS sort_order,
            count(*)                                                              AS "Count",
            round(count(*) * 100.0 / sum(count(*)) OVER (), 1)                  AS "Percentage"
          FROM analytics.mart_households_dashboard
          GROUP BY 1, 2
          ORDER BY sort_order;
        SQL
      }
    }
    parameter_mappings = []
    display            = "bar"
    visualization_settings = {
      "graph.dimensions"        = ["Household Size"]
      "graph.metrics"           = ["Percentage"]
      "graph.x_axis.title_text" = "Household Size"
      "graph.y_axis.title_text" = "% of Households"
      "graph.show_values"       = true
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# Chart 10: Household Income Breakdown (% bar chart)
# ---------------------------------------------------------------------------
resource "metabase_card" "households_income_breakdown" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "What is the breakdown of household income?"
    description         = "Distribution of households by annual income bracket"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native = { query = <<-SQL
          SELECT
            annual_income_bin                                     AS "Income Range",
            annual_income_bin_order                               AS sort_order,
            count(*)                                             AS "Count",
            round(count(*) * 100.0 / sum(count(*)) OVER (), 1)  AS "Percentage"
          FROM analytics.mart_households_dashboard
          WHERE annual_income_bin != 'Unknown'
          GROUP BY annual_income_bin, annual_income_bin_order
          ORDER BY annual_income_bin_order;
        SQL
      }
    }
    parameter_mappings = []
    display            = "bar"
    visualization_settings = {
      "graph.dimensions"        = ["Income Range"]
      "graph.metrics"           = ["Percentage"]
      "graph.x_axis.title_text" = "Annual Income"
      "graph.y_axis.title_text" = "% of Households"
      "graph.show_values"       = true
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# Chart 11: Household Assets Breakdown (% bar chart)
# ---------------------------------------------------------------------------
resource "metabase_card" "households_assets_breakdown" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "What is the breakdown of household assets?"
    description         = "Distribution of households by total assets bracket"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native = { query = <<-SQL
          SELECT
            assets_bin                                            AS "Assets Range",
            assets_bin_order                                      AS sort_order,
            count(*)                                             AS "Count",
            round(count(*) * 100.0 / sum(count(*)) OVER (), 1)  AS "Percentage"
          FROM analytics.mart_households_dashboard
          WHERE assets_bin != 'Unknown'
          GROUP BY assets_bin, assets_bin_order
          ORDER BY assets_bin_order;
        SQL
      }
    }
    parameter_mappings = []
    display            = "bar"
    visualization_settings = {
      "graph.dimensions"        = ["Assets Range"]
      "graph.metrics"           = ["Percentage"]
      "graph.x_axis.title_text" = "Household Assets"
      "graph.y_axis.title_text" = "% of Households"
      "graph.show_values"       = true
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# Chart 12: Languages Spoken (pie/donut chart)
# ---------------------------------------------------------------------------
resource "metabase_card" "households_languages" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "What languages are spoken in these households?"
    description         = "Distribution of households by language used during screening"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native = { query = <<-SQL
          SELECT
            coalesce(request_language_code, '(blank)') AS "Language",
            count(*)                                    AS "Count",
            round(count(*) * 100.0 / sum(count(*)) OVER (), 1) AS "Percentage"
          FROM analytics.mart_households_dashboard
          GROUP BY request_language_code
          ORDER BY "Count" DESC;
        SQL
      }
    }
    parameter_mappings = []
    display            = "pie"
    visualization_settings = {
      "pie.dimension" = "Language"
      "pie.metric"    = "Count"
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# Card 13: What income streams do households have?
# ---------------------------------------------------------------------------
resource "metabase_card" "households_income_streams" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "What income streams do households have?"
    description         = "Count of households reporting each type of income stream"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native = { query = <<-SQL
          SELECT
            i.type                          AS "Income Type",
            count(DISTINCT i.screener_id)   AS "Number of Households"
          FROM analytics.mart_income i
          INNER JOIN analytics.mart_households_dashboard m
            ON m.screener_id = i.screener_id
          GROUP BY i.type
          ORDER BY "Number of Households" DESC;
        SQL
      }
    }
    parameter_mappings = []
    display            = "pie"
    visualization_settings = {
      "pie.dimension"          = "Income Type"
      "pie.metric"             = "Number of Households"
      "pie.show_legend"        = true
      "pie.show_total"         = true
      "pie.percent_visibility" = "inside"
      "version"                = 2
      "column_settings" = {
        "[\"name\",\"wages\"]"          = { "color" = "#293457" }
        "[\"name\",\"selfEmployment\"]" = { "color" = "#B85A27" }
        "[\"name\",\"disability\"]"     = { "color" = "#F9D45C" }
        "[\"name\",\"unemployment\"]"   = { "color" = "#ED6E6E" }
        "[\"name\",\"pension\"]"        = { "color" = "#A989C5" }
        "[\"name\",\"socialSecurity\"]" = { "color" = "#4EAAB2" }
        "[\"name\",\"veteran\"]"        = { "color" = "#EF8C8C" }
        "[\"name\",\"alimony\"]"        = { "color" = "#98D9D9" }
        "[\"name\",\"childSupport\"]"   = { "color" = "#F2A86F" }
        "[\"name\",\"rental\"]"         = { "color" = "#7172AD" }
        "[\"name\",\"investment\"]"     = { "color" = "#6FCF97" }
        "[\"name\",\"other\"]"          = { "color" = "#BDBDBD" }
      }
    }
    parameters = []
  })
}

# ---------------------------------------------------------------------------
# Card 14: What are the most common expenses?
# ---------------------------------------------------------------------------
resource "metabase_card" "households_common_expenses" {
  for_each = var.tenants

  lifecycle { ignore_changes = [json] }

  json = jsonencode({
    name                = "What are the most common expenses?"
    description         = "Count of households reporting each type of expense"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      type     = "native"
      native = { query = <<-SQL
          SELECT
            e.type                          AS "Expense Type",
            count(DISTINCT e.screener_id)   AS "Number of Households"
          FROM analytics.mart_screener_expense e
          INNER JOIN analytics.mart_households_dashboard m
            ON m.screener_id = e.screener_id
          GROUP BY e.type
          ORDER BY "Number of Households" DESC;
        SQL
      }
    }
    parameter_mappings = []
    display            = "pie"
    visualization_settings = {
      "pie.dimension"          = "Expense Type"
      "pie.metric"             = "Number of Households"
      "pie.show_legend"        = true
      "pie.show_total"         = true
      "pie.percent_visibility" = "inside"
      "version"                = 2
      "column_settings" = {
        "[\"name\",\"rent\"]"         = { "color" = "#509EE3" }
        "[\"name\",\"childCare\"]"    = { "color" = "#84BB4C" }
        "[\"name\",\"childSupport\"]" = { "color" = "#F9D45C" }
        "[\"name\",\"internet\"]"     = { "color" = "#A989C5" }
        "[\"name\",\"telephone\"]"    = { "color" = "#F2A86F" }
        "[\"name\",\"utilities\"]"    = { "color" = "#4EAAB2" }
        "[\"name\",\"medical\"]"      = { "color" = "#ED6E6E" }
        "[\"name\",\"other\"]"        = { "color" = "#BDBDBD" }
      }
    }
    parameters = []
  })
}
