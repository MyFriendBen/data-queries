# Tenant-specific cards for "Households" (Tab 4)

# --- Scorecards ---

resource "metabase_card" "tenant_median_household_size" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Household Size (Median)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY household_size) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = { "scalar.field" = "median" }
  }))
}

resource "metabase_card" "tenant_median_household_assets" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Household Assets (Median)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY household_assets) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "tenant_median_annual_income" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Annual Income (Median)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_income * 12) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "tenant_median_monthly_income" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Monthly Income (Median)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_income) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "tenant_median_monthly_expenses" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Monthly Expenses (Median)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_expenses) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

# --- Age distribution bar charts ---

resource "metabase_card" "tenant_head_of_household_ages" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "What are the ages of the heads of household?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/household_head_ages.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Age Group"]
  }))
}

resource "metabase_card" "tenant_household_member_ages" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "What are the ages of all household members?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/household_member_ages.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Age Group"]
  }))
}

# --- Household size + languages ---

resource "metabase_card" "tenant_household_sizes" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "What is the breakdown of household sizes?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/household_sizes.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Household Size"]
  }))
}

resource "metabase_card" "tenant_household_languages" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "What languages are spoken in these households?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "pie"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/household_languages.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
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

# --- Income + assets distribution ---

resource "metabase_card" "tenant_household_income_distribution" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "What is the breakdown of household income?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/household_income_distribution.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Income Range"]
  }))
}

resource "metabase_card" "tenant_household_assets_distribution" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "What is the breakdown of household assets?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/household_assets_distribution.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.households_pct_bar_chart_settings["Asset Range"]
  }))
}

# --- Income streams + expenses tables ---

resource "metabase_card" "tenant_income_streams" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "What income streams do households have?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/income_streams.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "column_settings" = local.households_table_column_settings
    })
  }))
}

resource "metabase_card" "tenant_common_expenses" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "What are the most common expenses?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/common_expenses.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "column_settings" = local.households_table_column_settings
    })
  }))
}

# --- Shared locals ---

locals {
  # Reusable bar chart visualization settings for percentage metrics
  households_pct_bar_chart_settings = {
    for dim in ["Age Group", "Household Size", "Income Range", "Asset Range"] : dim => {
      "graph.dimensions"        = [dim]
      "graph.metrics"           = ["% of Total"]
      "graph.x_axis.title_text" = dim
      "graph.y_axis.title_text" = "% of Total"
      "graph.show_values"       = true
      "series_settings" = {
        "% of Total" = { color = "#509EE3" }
      }
      "column_settings" = {
        "[\"name\",\"% of Total\"]" = local.number_format_percent_0
      }
    }
  }

  # Shared column settings for income streams / expenses table cards
  households_table_column_settings = {
    "[\"name\",\"% of Screeners\"]" = merge(
      local.show_minibar_true,
      local.number_format_percent_0
    )
    "[\"name\",\"Median Amount\"]" = merge(
      local.show_minibar_true,
      local.currency_format_0
    )
  }

  # Dashboard layout for Tab 4: Households (CO only)
  # Text blocks are interleaved at their correct visual positions (sorted by row/col)
  # so the order matches what Metabase returns after saving. The mixed
  # visualization_settings types (empty {} vs {virtual_card, text}) create a tuple,
  # so metabase.tf wraps this in jsondecode(jsonencode()) for conditional compatibility.

  # Scorecard counts per tenant for the Households top row:
  # non-CESN: Completed Screeners, HH Size, Assets, Annual Income, Monthly Income, Expenses = 6
  # CESN: Completed Screeners, HH Size, Annual Income, Monthly Income = 4 (no assets/expenses)
  households_scorecard_count = { for k, v in var.tenants : k => k != "cesn" ? 6 : 4 }
  households_scorecard_width = { for k, v in var.tenants : k => 24 / local.households_scorecard_count[k] }

  tenant_dashboard_households_data_layout = {
    for k, v in var.tenants : k => flatten(concat(
      # Row 0: scorecards — width auto-calculated so cards always fill the full row
      [
        {
          card_id          = tonumber(metabase_card.tenant_completed_screeners[k].id)
          dashboard_tab_id = 4
          row              = 0
          col              = 0
          size_x           = local.households_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_completed_screeners[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_completed_screeners[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.tenant_median_household_size[k].id)
          dashboard_tab_id = 4
          row              = 0
          col              = local.households_scorecard_width[k] * 1
          size_x           = local.households_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_household_size[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_household_size[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ],
      # Assets scorecard — hidden for CESN (not collected)
      k != "cesn" ? [
        {
          card_id          = tonumber(metabase_card.tenant_median_household_assets[k].id)
          dashboard_tab_id = 4
          row              = 0
          col              = local.households_scorecard_width[k] * 2
          size_x           = local.households_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_household_assets[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_household_assets[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      [
        {
          card_id          = tonumber(metabase_card.tenant_median_annual_income[k].id)
          dashboard_tab_id = 4
          row              = 0
          col              = k != "cesn" ? local.households_scorecard_width[k] * 3 : local.households_scorecard_width[k] * 2
          size_x           = local.households_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_income[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_income[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.tenant_median_monthly_income[k].id)
          dashboard_tab_id = 4
          row              = 0
          col              = k != "cesn" ? local.households_scorecard_width[k] * 4 : local.households_scorecard_width[k] * 3
          size_x           = local.households_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_income[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_income[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ],
      # Expenses scorecard — hidden for CESN (not collected)
      k != "cesn" ? [
        {
          card_id          = tonumber(metabase_card.tenant_median_monthly_expenses[k].id)
          dashboard_tab_id = 4
          row              = 0
          col              = local.households_scorecard_width[k] * 5
          size_x           = local.households_scorecard_width[k]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_expenses[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_expenses[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      # Row 4: Text block + 2 age distribution charts
      [{
        card_id            = null
        dashboard_tab_id   = 4
        row                = 4
        col                = 0
        size_x             = 6
        size_y             = 8
        parameter_mappings = []
        series             = []
        visualization_settings = {
          virtual_card = {
            name                   = null
            dataset_query          = {}
            display                = "text"
            visualization_settings = {}
          }
          text = "### Heads of Household\nThe head of household is the person who filled out the screener. If there is more than one adult in the household, the head of household is the oldest adult.\n\n### Age Groups\nAge bins follow U.S. Census Bureau conventions.\n\n**Head of Household:** 0-18, 19-24, 25-44, 45-64, 65+\n**All Members:** <5, 5-18, 19-24, 25-44, 45-64, 65+"
        }
      },
      {
        card_id          = tonumber(metabase_card.tenant_head_of_household_ages[k].id)
        dashboard_tab_id = 4
        row              = 4
        col              = 6
        size_x           = 9
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_head_of_household_ages[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_head_of_household_ages[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_household_member_ages[k].id)
        dashboard_tab_id = 4
        row              = 4
        col              = 15
        size_x           = 9
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_household_member_ages[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_household_member_ages[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 12: Household sizes + languages
      {
        card_id          = tonumber(metabase_card.tenant_household_sizes[k].id)
        dashboard_tab_id = 4
        row              = 12
        col              = 0
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_household_sizes[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_household_sizes[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_household_languages[k].id)
        dashboard_tab_id = 4
        row              = 12
        col              = 12
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_household_languages[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_household_languages[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      }],
      # Row 20: Text block + income/assets distributions
      # Text block — hidden for CESN
      k != "cesn" ? [
        {
          card_id            = null
          dashboard_tab_id   = 4
          row                = 20
          col                = 0
          size_x             = 6
          size_y             = 8
          parameter_mappings = []
          series             = []
          visualization_settings = {
            virtual_card = {
              name                   = null
              dataset_query          = {}
              display                = "text"
              visualization_settings = {}
            }
            text = "### Household Assets & Income\nAssets include savings, checking, and investment accounts.\n\nHouseholds reporting **$50,000+** in assets are likely homeowners (home equity included)."
          }
        },
      ] : [],
      # Income distribution chart — hidden for CESN
      k != "cesn" ? [
        {
          card_id          = tonumber(metabase_card.tenant_household_income_distribution[k].id)
          dashboard_tab_id = 4
          row              = 20
          col              = 6
          size_x           = 9
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_household_income_distribution[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_household_income_distribution[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      # Assets distribution chart — hidden for CESN
      k != "cesn" ? [
        {
          card_id          = tonumber(metabase_card.tenant_household_assets_distribution[k].id)
          dashboard_tab_id = 4
          row              = 20
          col              = 15
          size_x           = 9
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_household_assets_distribution[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_household_assets_distribution[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      # Row 28: Income streams table (always shown) + expenses table (hidden for CESN)
      [
        {
          card_id          = tonumber(metabase_card.tenant_income_streams[k].id)
          dashboard_tab_id = 4
          row              = 28
          col              = 0
          size_x           = k != "cesn" ? 12 : 24
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_income_streams[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_income_streams[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ],
      k != "cesn" ? [
        {
          card_id          = tonumber(metabase_card.tenant_common_expenses[k].id)
          dashboard_tab_id = 4
          row              = 28
          col              = 12
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_common_expenses[k].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_common_expenses[k].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
    ))
  }

}
