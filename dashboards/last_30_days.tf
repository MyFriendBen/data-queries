# Tenant-specific cards for "Last 30 Days Performance" (Tab 3)

# --- Scorecards ---

resource "metabase_card" "tenant_completed_screeners_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Completed Screeners (30d)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '29 days' [[AND {{partner}}]]"
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "tenant_qualified_for_benefits_pct_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Qualified for Benefits (30d)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '29 days' [[AND {{partner}}]]"
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "tenant_median_annual_benefits_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Median Annual Benefits (30d)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual) AS median FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0 AND submission_date >= CURRENT_DATE - INTERVAL '29 days' [[AND {{partner}}]]"
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "tenant_median_monthly_benefits_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Median Monthly Benefits (30d)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual / 12.0) AS median FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0 AND submission_date >= CURRENT_DATE - INTERVAL '29 days' [[AND {{partner}}]]"
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "tenant_qualified_for_tax_creds_pct_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Qualified for Tax Credits (30d)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) FILTER (WHERE tax_credits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '29 days' [[AND {{partner}}]]"
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "tenant_median_annual_tax_credits_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Median Annual Tax Credits (30d)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE tax_credits_annual > 0 AND submission_date >= CURRENT_DATE - INTERVAL '29 days' [[AND {{partner}}]]"
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

# --- Bar chart ---

resource "metabase_card" "tenant_daily_screeners_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Daily Screeners (Last 30 Days)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT submission_date, count(*) AS screeners FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '29 days' [[AND {{partner}}]] GROUP BY submission_date ORDER BY submission_date"
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = {
      "graph.dimensions"        = ["SUBMISSION_DATE"]
      "graph.metrics"           = ["SCREENERS"]
      "graph.x_axis.title_text" = "Date"
      "graph.y_axis.title_text" = "Screeners Completed"
      "graph.show_values"       = true
    }
  }))
}

# --- Tables ---

resource "metabase_card" "tenant_top_partners_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "Top Partners (Last 30 Days)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/top_partners_30d.sql", {})
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "column_settings" = {
        "[\"name\",\"#\"]" = local.show_minibar_true
        "[\"name\",\"%\"]" = merge(
          local.show_minibar_true,
          local.number_format_percent_0
        )
      }
    })
  }))
}

resource "metabase_card" "tenant_top_counties_30d" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "Top Counties (Last 30 Days)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/top_counties_30d.sql", {})
        "template-tags" = local.partner_template_tags[each.key]
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "column_settings" = {
        "[\"name\",\"#\"]" = local.show_minibar_true
        "[\"name\",\"%\"]" = merge(
          local.show_minibar_true,
          local.number_format_percent_0
        )
      }
    })
  }))
}

# --- Dashboard layout for Tab 3 ---

locals {
  tenant_dashboard_last_30_days_layout = {
    for k, v in var.tenants : k => [
      # Row 0: 6 scorecards
      {
        card_id          = tonumber(metabase_card.tenant_completed_screeners_30d[k].id)
        dashboard_tab_id = 3
        row              = 0
        col              = 0
        size_x           = 4
        size_y           = 4
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_completed_screeners_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_qualified_for_benefits_pct_30d[k].id)
        dashboard_tab_id = 3
        row              = 0
        col              = 4
        size_x           = 4
        size_y           = 4
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_qualified_for_benefits_pct_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_median_annual_benefits_30d[k].id)
        dashboard_tab_id = 3
        row              = 0
        col              = 8
        size_x           = 4
        size_y           = 4
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_median_annual_benefits_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_median_monthly_benefits_30d[k].id)
        dashboard_tab_id = 3
        row              = 0
        col              = 12
        size_x           = 4
        size_y           = 4
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_median_monthly_benefits_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct_30d[k].id)
        dashboard_tab_id = 3
        row              = 0
        col              = 16
        size_x           = 4
        size_y           = 4
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_median_annual_tax_credits_30d[k].id)
        dashboard_tab_id = 3
        row              = 0
        col              = 20
        size_x           = 4
        size_y           = 4
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_median_annual_tax_credits_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
      # Row 4: Bar chart
      {
        card_id          = tonumber(metabase_card.tenant_daily_screeners_30d[k].id)
        dashboard_tab_id = 3
        row              = 4
        col              = 0
        size_x           = 24
        size_y           = 6
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_daily_screeners_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
      # Row 10: Two tables side-by-side
      {
        card_id          = tonumber(metabase_card.tenant_top_partners_30d[k].id)
        dashboard_tab_id = 3
        row              = 10
        col              = 0
        size_x           = 12
        size_y           = 8
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_top_partners_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_top_counties_30d[k].id)
        dashboard_tab_id = 3
        row              = 10
        col              = 12
        size_x           = 12
        size_y           = 8
        parameter_mappings = [{
          parameter_id = "partner_filter"
          card_id      = tonumber(metabase_card.tenant_top_counties_30d[k].id)
          target       = ["dimension", ["template-tag", "partner"]]
        }]
        series                 = []
        visualization_settings = {}
      },
    ]
  }
}
