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
        query           = <<-SQL
            SELECT count(*) AS count FROM analytics.mart_screener_data WHERE 1=1
              [[AND {{submission_date}}]]
              [[AND {{partner}}]]
              [[AND {{county}}]]
          SQL
        "template-tags" = local.filter_template_tags[each.key]
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
        query           = <<-SQL
            SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) AS pct
            FROM analytics.mart_screener_data WHERE 1=1
              [[AND {{submission_date}}]]
              [[AND {{partner}}]]
              [[AND {{county}}]]
          SQL
        "template-tags" = local.filter_template_tags[each.key]
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
        query           = <<-SQL
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual) AS median
            FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0
              [[AND {{submission_date}}]]
              [[AND {{partner}}]]
              [[AND {{county}}]]
          SQL
        "template-tags" = local.filter_template_tags[each.key]
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
        query           = <<-SQL
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual / 12.0) AS median
            FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0
              [[AND {{submission_date}}]]
              [[AND {{partner}}]]
              [[AND {{county}}]]
          SQL
        "template-tags" = local.filter_template_tags[each.key]
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
        query           = <<-SQL
            SELECT count(*) FILTER (WHERE tax_credits_annual > 0)::float / NULLIF(count(*), 0) AS pct
            FROM analytics.mart_screener_data WHERE 1=1
              [[AND {{submission_date}}]]
              [[AND {{partner}}]]
              [[AND {{county}}]]
          SQL
        "template-tags" = local.filter_template_tags[each.key]
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
        query           = <<-SQL
            SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tax_credits_annual) AS median
            FROM analytics.mart_screener_data WHERE tax_credits_annual > 0
              [[AND {{submission_date}}]]
              [[AND {{partner}}]]
              [[AND {{county}}]]
          SQL
        "template-tags" = local.filter_template_tags[each.key]
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
        query           = <<-SQL
            SELECT submission_date, count(*) AS screeners FROM analytics.mart_screener_data WHERE 1=1
              [[AND {{submission_date}}]]
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY submission_date ORDER BY submission_date
          SQL
        "template-tags" = local.filter_template_tags[each.key]
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
        "template-tags" = local.filter_template_tags[each.key]
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
        "template-tags" = local.filter_template_tags[each.key]
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
  # Scorecard counts for Last 30 Days top row — same structure as All-Time:
  # with tax credits: 6 scorecards (4 cols each); without: 4 scorecards (6 cols each)
  last30_scorecard_count = { for k, v in var.tenants : k => local.tenant_features[k].has_tax_credits ? 6 : 4 }
  last30_scorecard_width = { for k, v in var.tenants : k => 24 / local.last30_scorecard_count[k] }

  tenant_dashboard_last_30_days_layout = {
    for k, v in var.tenants : k => flatten(concat(
      # Row 0: base scorecards — width auto-calculated so cards always fill the full row
      [{
        card_id          = tonumber(metabase_card.tenant_completed_screeners_30d[k].id)
        dashboard_tab_id = 3
        row              = 0
        col              = 0
        size_x           = local.last30_scorecard_width[k]
        size_y           = 4
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_completed_screeners_30d[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "date_range_filter"
            card_id      = tonumber(metabase_card.tenant_completed_screeners_30d[k].id)
            target       = ["dimension", ["template-tag", "submission_date"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_completed_screeners_30d[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.tenant_qualified_for_benefits_pct_30d[k].id)
          dashboard_tab_id = 3
          row              = 0
          col              = local.last30_scorecard_width[k] * 1
          size_x           = local.last30_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_benefits_pct_30d[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "date_range_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_benefits_pct_30d[k].id)
              target       = ["dimension", ["template-tag", "submission_date"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_benefits_pct_30d[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.tenant_median_annual_benefits_30d[k].id)
          dashboard_tab_id = 3
          row              = 0
          col              = local.last30_scorecard_width[k] * 2
          size_x           = local.last30_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_benefits_30d[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "date_range_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_benefits_30d[k].id)
              target       = ["dimension", ["template-tag", "submission_date"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_benefits_30d[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.tenant_median_monthly_benefits_30d[k].id)
          dashboard_tab_id = 3
          row              = 0
          col              = local.last30_scorecard_width[k] * 3
          size_x           = local.last30_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_benefits_30d[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "date_range_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_benefits_30d[k].id)
              target       = ["dimension", ["template-tag", "submission_date"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_benefits_30d[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
      }],
      # Tax credit cards — hidden for tenants that don't collect tax credit data
      local.tenant_features[k].has_tax_credits ? [
        {
          card_id          = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct_30d[k].id)
          dashboard_tab_id = 3
          row              = 0
          col              = local.last30_scorecard_width[k] * 4
          size_x           = local.last30_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct_30d[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "date_range_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct_30d[k].id)
              target       = ["dimension", ["template-tag", "submission_date"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct_30d[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      local.tenant_features[k].has_tax_credits ? [
        {
          card_id          = tonumber(metabase_card.tenant_median_annual_tax_credits_30d[k].id)
          dashboard_tab_id = 3
          row              = 0
          col              = local.last30_scorecard_width[k] * 5
          size_x           = local.last30_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_tax_credits_30d[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "date_range_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_tax_credits_30d[k].id)
              target       = ["dimension", ["template-tag", "submission_date"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_tax_credits_30d[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      # Row 4: Bar chart
      [{
        card_id          = tonumber(metabase_card.tenant_daily_screeners_30d[k].id)
        dashboard_tab_id = 3
        row              = 4
        col              = 0
        size_x           = 24
        size_y           = 6
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_daily_screeners_30d[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "date_range_filter"
            card_id      = tonumber(metabase_card.tenant_daily_screeners_30d[k].id)
            target       = ["dimension", ["template-tag", "submission_date"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_daily_screeners_30d[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      }],
      # Row 10: Tables — Top Partners hidden for tenants that don't track partners
      local.tenant_features[k].has_partners ? [
        {
          card_id          = tonumber(metabase_card.tenant_top_partners_30d[k].id)
          dashboard_tab_id = 3
          row              = 10
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_top_partners_30d[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "date_range_filter"
              card_id      = tonumber(metabase_card.tenant_top_partners_30d[k].id)
              target       = ["dimension", ["template-tag", "submission_date"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_top_partners_30d[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      [
        {
          card_id          = tonumber(metabase_card.tenant_top_counties_30d[k].id)
          dashboard_tab_id = 3
          row              = 10
          col              = local.tenant_features[k].has_partners ? 12 : 0
          size_x           = local.tenant_features[k].has_partners ? 12 : 24
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_top_counties_30d[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "date_range_filter"
              card_id      = tonumber(metabase_card.tenant_top_counties_30d[k].id)
              target       = ["dimension", ["template-tag", "submission_date"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_top_counties_30d[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ],
    ))
  }
}
