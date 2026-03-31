# Global card resources for the MFB Analytics Dashboard.
# Each card mirrors a tenant card but queries the unfiltered global database
# (metabase_database.postgres) and has no partner filter.

# =============================================================================
# Helper: strip the Metabase partner template-tag placeholder from SQL files
# =============================================================================
locals {
  # For SQL files: remove the partner filter clause
  _partner_clause     = " [[AND {{partner}}]]"
  _partner_clause_alt = "\n    [[AND {{partner}}]]"
  # submission_date clause — only in 30d files
  _submission_date_clause = " [[AND {{submission_date}}]]"

  # Base config for global cards (no template-tags, no partner filter)
  global_card_base_config = {
    description         = null
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      type = "native"
    }
    parameter_mappings     = []
    parameters             = []
    visualization_settings = {}
  }

  global_scorecard_config = merge(local.global_card_base_config, {
    display = "scalar"
  })

  global_percentage_card_config = merge(local.global_scorecard_config, {
    visualization_settings = {
      "column_settings" = {}
    }
  })

  global_table_card_config = merge(local.global_card_base_config, {
    display = "table"
    visualization_settings = {
      "table.column_widths" = []
      "column_settings"     = {}
    }
  })

  global_db_id  = tonumber(metabase_database.postgres.id)
  global_col_id = tonumber(metabase_collection.global.id)
}

# =============================================================================
# Tab 1: All-Time Performance — 9 cards
# =============================================================================

resource "metabase_card" "global_completed_screeners" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Completed Screeners"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT count(*) AS \"Completed Screeners\" FROM analytics.mart_screener_data WHERE 1=1"
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "global_qualified_for_benefits_pct" {
  json = jsonencode(merge(local.global_percentage_card_config, {
    name          = "Qualified for Benefits *"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE 1=1"
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "global_median_annual_benefits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Annual Benefits"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual) AS median FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_median_monthly_benefits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Monthly Benefits"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual / 12.0) AS median FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_qualified_for_tax_creds_pct" {
  json = jsonencode(merge(local.global_percentage_card_config, {
    name          = "Qualified for Tax Credits *"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT count(*) FILTER (WHERE tax_credits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE 1=1"
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "global_median_annual_tax_credits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Annual Tax Credits"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE tax_credits_annual > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_daily_screeners_7d" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "Daily Screeners (Last 7 Days)"
    collection_id = local.global_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT submission_date, count(*) AS screeners FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '6 days' GROUP BY submission_date ORDER BY submission_date"
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

resource "metabase_card" "global_top_partners" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "Which Partners Did The Screeners Come From?"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/top_partners.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
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

resource "metabase_card" "global_top_counties" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "Which Counties Did The Screeners Come From?"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/top_counties.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
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

# =============================================================================
# Tab 2: Last 30 Days Performance — 9 cards
# =============================================================================

resource "metabase_card" "global_completed_screeners_30d" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Completed Screeners (30d)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT count(*) FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '29 days'"
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "global_qualified_for_benefits_pct_30d" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Qualified for Benefits (30d)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '29 days'"
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "global_median_annual_benefits_30d" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Annual Benefits (30d)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual) AS median FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0 AND submission_date >= CURRENT_DATE - INTERVAL '29 days'"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_median_monthly_benefits_30d" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Monthly Benefits (30d)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual / 12.0) AS median FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0 AND submission_date >= CURRENT_DATE - INTERVAL '29 days'"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_qualified_for_tax_creds_pct_30d" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Qualified for Tax Credits (30d)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT count(*) FILTER (WHERE tax_credits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '29 days'"
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "global_median_annual_tax_credits_30d" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Annual Tax Credits (30d)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE tax_credits_annual > 0 AND submission_date >= CURRENT_DATE - INTERVAL '29 days'"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_daily_screeners_30d" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "Daily Screeners (Last 30 Days)"
    collection_id = local.global_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT submission_date, count(*) AS screeners FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '29 days' GROUP BY submission_date ORDER BY submission_date"
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

resource "metabase_card" "global_top_partners_30d" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "Top Partners (Last 30 Days)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/top_partners_30d.sql", {}),
            local._submission_date_clause, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
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

resource "metabase_card" "global_top_counties_30d" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "Top Counties (Last 30 Days)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/top_counties_30d.sql", {}),
            local._submission_date_clause, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
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

# =============================================================================
# Tab 3: Households — 13 cards (reuses global_completed_screeners from Tab 1)
# =============================================================================

resource "metabase_card" "global_median_household_size" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Household Size (Median)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY household_size) AS median FROM analytics.mart_screener_data WHERE 1=1"
      }
    }
    visualization_settings = { "scalar.field" = "median" }
  }))
}

resource "metabase_card" "global_median_household_assets" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Household Assets (Median)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY household_assets) AS median FROM analytics.mart_screener_data WHERE 1=1"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_median_annual_income" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Annual Income (Median)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_income * 12) AS median FROM analytics.mart_screener_data WHERE 1=1"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_median_monthly_income" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Monthly Income (Median)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_income) AS median FROM analytics.mart_screener_data WHERE 1=1"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_median_monthly_expenses" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Monthly Expenses (Median)"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_expenses) AS median FROM analytics.mart_screener_data WHERE 1=1"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "global_head_of_household_ages" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "What are the ages of the heads of household?"
    collection_id = local.global_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/household_head_ages.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Age Group"]
  }))
}

resource "metabase_card" "global_household_member_ages" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "What are the ages of all household members?"
    collection_id = local.global_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/household_member_ages.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Age Group"]
  }))
}

resource "metabase_card" "global_household_sizes" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "What is the breakdown of household sizes?"
    collection_id = local.global_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/household_sizes.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Household Size"]
  }))
}

resource "metabase_card" "global_household_languages" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "What languages are spoken in these households?"
    collection_id = local.global_col_id
    display       = "pie"
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/household_languages.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = {
      "pie.dimension" = "Language"
      "pie.metric"    = "% of Total"
      "column_settings" = {
        "[\"name\",\"% of Total\"]" = local.number_format_percent_0
      }
    }
  }))
}

resource "metabase_card" "global_household_income_distribution" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "What is the breakdown of household income?"
    collection_id = local.global_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/household_income_distribution.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Income Range"]
  }))
}

resource "metabase_card" "global_household_assets_distribution" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "What is the breakdown of household assets?"
    collection_id = local.global_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/household_assets_distribution.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Asset Range"]
  }))
}

resource "metabase_card" "global_income_streams" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What income streams do households have?"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/income_streams.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "column_settings" = local.households_table_column_settings
    })
  }))
}

resource "metabase_card" "global_common_expenses" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What are the most common expenses?"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          replace(
            templatefile("${path.module}/sql/common_expenses.sql", {}),
            local._partner_clause_alt, ""
          ),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "column_settings" = local.households_table_column_settings
    })
  }))
}

# =============================================================================
# Tab 4: Benefits & Immediate Needs — 4 new cards
# (reuses global_completed_screeners, global_qualified_for_benefits_pct,
#  global_qualified_for_tax_creds_pct from Tab 1)
# =============================================================================

resource "metabase_card" "global_already_had_benefits_pct" {
  json = jsonencode(merge(local.global_percentage_card_config, {
    name          = "Already Had Benefits"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = "SELECT count(*) FILTER (WHERE has_benefits = 'true')::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data"
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "global_current_benefits_table" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What percentage of users said they already had certain benefits?"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          templatefile("${path.module}/sql/current_benefits.sql", {}),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "table.column_widths" = [{ "name" = "Benefit Name", "width" = 300 }]
      "column_settings"     = local.benefits_column_settings
    })
  }))
}

resource "metabase_card" "global_qualified_benefits_table" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What percentage of completed screeners qualified for benefits?"
    description   = "Aggregated benefit eligibility data across all tenants."
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          templatefile("${path.module}/sql/qualified_benefits.sql", {}),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "table.column_widths" = [{ "name" = "Benefit Name", "width" = 300 }]
      "column_settings"     = local.benefits_column_settings
    })
  }))
}

resource "metabase_card" "global_immediate_needs_table" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What percentage of users sought each immediate need?"
    collection_id = local.global_col_id
    dataset_query = {
      type     = "native"
      database = local.global_db_id
      native = {
        query = replace(
          templatefile("${path.module}/sql/immediate_needs.sql", {}),
          local._partner_clause, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "table.column_widths" = [{ "name" = "Need Category", "width" = 300 }]
      "column_settings"     = local.benefits_column_settings
    })
  }))
}
