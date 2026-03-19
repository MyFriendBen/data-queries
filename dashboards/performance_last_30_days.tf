# --- LAST 30 DAYS KPI 1: Completed Screeners ---
resource "metabase_card" "performance_30d_completed_screeners" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Completed Screeners"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT count(*) AS \"Count\" FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '30 days';"
      }
    }
  }))
}

# --- LAST 30 DAYS KPI 2: Percent Qualified for Benefits ---
resource "metabase_card" "performance_30d_percent_qualified_benefits" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_percentage_card_config, {
    name          = "Qualified for Benefits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT ROUND(COUNT(CASE WHEN non_tax_credit_benefits_annual > 0 THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 1) AS \"Percentage\" FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '30 days';"
      }
    }
    visualization_settings = merge(local.tenant_percentage_card_config.visualization_settings, {
      "column_settings" = { "[\"name\",\"Percentage\"]" = { "suffix" = "%" } }
    })
  }))
}

# --- LAST 30 DAYS KPI 3: Median Annual Benefits ---
resource "metabase_card" "performance_30d_median_annual_benefits" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Annual Benefits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual) AS \"Median\" FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0 AND submission_date >= CURRENT_DATE - INTERVAL '30 days';"
      }
    }
    visualization_settings = {
      "column_settings" = { "[\"name\",\"Median\"]" = merge(local.currency_format_0, { "decimals" = 0 }) }
    }
  }))
}

# --- LAST 30 DAYS KPI 4: Median Monthly Benefits ---
resource "metabase_card" "performance_30d_median_monthly_benefits" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Monthly Benefits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_monthly) AS \"Median\" FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_monthly > 0 AND submission_date >= CURRENT_DATE - INTERVAL '30 days';"
      }
    }
    visualization_settings = {
      "column_settings" = { "[\"name\",\"Median\"]" = local.currency_format_0 }
    }
  }))
}

# --- LAST 30 DAYS KPI 5: Percent Qualified for Tax Credits ---
resource "metabase_card" "performance_30d_percent_qualified_tax_credits" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_percentage_card_config, {
    name          = "Qualified for Tax Credits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT ROUND(COUNT(CASE WHEN tax_credits_annual > 0 THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 1) AS \"Percentage\" FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '30 days';"
      }
    }
    visualization_settings = merge(local.tenant_percentage_card_config.visualization_settings, {
      "column_settings" = { "[\"name\",\"Percentage\"]" = { "suffix" = "%" } }
    })
  }))
}

# --- LAST 30 DAYS KPI 6: Median Annual Tax Credits ---
resource "metabase_card" "performance_30d_median_annual_tax_credits" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Annual Tax Credits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tax_credits_annual) AS \"Median\" FROM analytics.mart_screener_data WHERE tax_credits_annual > 0 AND submission_date >= CURRENT_DATE - INTERVAL '30 days';"
      }
    }
    visualization_settings = {
      "column_settings" = { "[\"name\",\"Median\"]" = local.currency_format_0 }
    }
  }))
}

# --- LAST 30 DAYS Trend 1: Daily Screener Trend ---
resource "metabase_card" "performance_30d_daily_trend" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "How many screeners were completed daily over the past 30 days?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT submission_date::date AS \"Date\", count(*) AS \"Count\" FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '30 days' GROUP BY 1 ORDER BY 1 ASC;"
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Date"]
      "graph.metrics"     = ["Count"]
      "graph.show_values" = true
    }
  }))
}

# --- LAST 30 DAYS Breakdown 1: Partner Distribution ---
resource "metabase_card" "performance_30d_partner_distribution" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "Which partners did the screeners come from?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT partner AS \"Top 10 Partners\", count(*) AS \"# of Screeners\", ROUND(count(*) * 100.0 / SUM(count(*)) OVER (), 2) AS \"% of Screeners\" FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '30 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 10;"
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "column_settings" = {
        "[\"name\",\"# of Screeners\"]" = local.show_minibar_true
        "[\"name\",\"% of Screeners\"]" = merge(local.show_minibar_true, { "suffix" = "%" })
      }
    })
  }))
}

# --- LAST 30 DAYS Breakdown 2: County Distribution ---
resource "metabase_card" "performance_30d_county_distribution" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "Which counties did the screeners come from?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = "SELECT county AS \"County\", count(*) AS \"# of Screeners\", ROUND(count(*) * 100.0 / SUM(count(*)) OVER (), 2) AS \"% of Screeners\" FROM analytics.mart_screener_data WHERE county IS NOT NULL AND submission_date >= CURRENT_DATE - INTERVAL '30 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 10;"
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "column_settings" = {
        "[\"name\",\"# of Screeners\"]" = local.show_minibar_true
        "[\"name\",\"% of Screeners\"]" = merge(local.show_minibar_true, { "suffix" = "%" })
      }
    })
  }))
}

locals {
  performance_30d_dashboard_cards = {
    for k, v in var.tenants : k => [
      # Row 0: Header (1 card, 24 wide x 2 tall)
      {
        card_id            = null
        dashboard_tab_id   = 3
        row                = 0
        col                = 0
        size_x             = 24
        size_y             = 2
        parameter_mappings = []
        series             = []
        visualization_settings = {
          virtual_card = {
            name                   = null
            dataset_query          = {}
            display                = "text"
            visualization_settings = {}
          }
          text = "# Live | Last 30 Days"
        }
      },
      # Row 2: KPI Scalars (6 cards)
      { card_id = tonumber(metabase_card.performance_30d_completed_screeners[k].id), dashboard_tab_id = 3, row = 2, col = 0, size_x = 4, size_y = 3, parameter_mappings = [], series = [], visualization_settings = {} },
      { card_id = tonumber(metabase_card.performance_30d_percent_qualified_benefits[k].id), dashboard_tab_id = 3, row = 2, col = 4, size_x = 4, size_y = 3, parameter_mappings = [], series = [], visualization_settings = {} },
      { card_id = tonumber(metabase_card.performance_30d_median_annual_benefits[k].id), dashboard_tab_id = 3, row = 2, col = 8, size_x = 4, size_y = 3, parameter_mappings = [], series = [], visualization_settings = {} },
      { card_id = tonumber(metabase_card.performance_30d_median_monthly_benefits[k].id), dashboard_tab_id = 3, row = 2, col = 12, size_x = 4, size_y = 3, parameter_mappings = [], series = [], visualization_settings = {} },
      { card_id = tonumber(metabase_card.performance_30d_percent_qualified_tax_credits[k].id), dashboard_tab_id = 3, row = 2, col = 16, size_x = 4, size_y = 3, parameter_mappings = [], series = [], visualization_settings = {} },
      { card_id = tonumber(metabase_card.performance_30d_median_annual_tax_credits[k].id), dashboard_tab_id = 3, row = 2, col = 20, size_x = 4, size_y = 3, parameter_mappings = [], series = [], visualization_settings = {} },

      # Row 5: Trend
      { card_id = tonumber(metabase_card.performance_30d_daily_trend[k].id), dashboard_tab_id = 3, row = 5, col = 0, size_x = 24, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },

      # Row 13: Breakdowns
      { card_id = tonumber(metabase_card.performance_30d_partner_distribution[k].id), dashboard_tab_id = 3, row = 13, col = 0, size_x = 12, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },
      { card_id = tonumber(metabase_card.performance_30d_county_distribution[k].id), dashboard_tab_id = 3, row = 13, col = 12, size_x = 12, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} }
    ]
  }
}
