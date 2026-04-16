# Metabase provider - only configure if Metabase is already set up
provider "metabase" {
  endpoint = "${var.metabase_url}/api"
  username = var.metabase_admin_email
  password = var.metabase_admin_password
}

resource "metabase_database" "bigquery" {
  count = var.bigquery_enabled ? 1 : 0

  name = "MFB BigQuery Analytics"
  bigquery_details = {
    service_account_key  = local.bigquery_key
    project_id           = var.gcp_project_id
    dataset_filters_type = "all"
    dataset_id           = var.bigquery_analytics_dataset
  }
}

resource "metabase_database" "postgres" {
  name = "MFB PostgreSQL Analytics"

  custom_details = {
    engine = "postgres"

    details_json = jsonencode({
      host             = var.database_host
      port             = var.database_port
      dbname           = var.database_name
      user             = var.global_db_credentials.username
      password         = var.global_db_credentials.password
      ssl              = var.database_ssl
      tunnel-enabled   = false
      advanced-options = false
    })

    redacted_attributes = [
      "password",
    ]
  }
}

# Tenant-specific PostgreSQL data sources (RLS filtered access)
resource "metabase_database" "tenant_postgres" {
  for_each = var.tenants

  name = "MFB PostgreSQL ${each.value.display_name}"

  custom_details = {
    engine = "postgres"

    details_json = jsonencode({
      host             = var.database_host
      port             = var.database_port
      dbname           = var.database_name
      user             = local.tenant_credentials[each.key].username
      password         = local.tenant_credentials[each.key].password
      ssl              = var.database_ssl
      tunnel-enabled   = false
      advanced-options = false
    })

    redacted_attributes = [
      "password",
    ]
  }
}

# Wait for Metabase to sync database schemas before creating cards/dashboards
#
# NOTE: This only sleeps on initial creation. When enabling a NEW data source
# (e.g. BigQuery for the first time), the sleep already exists in state and
# won't re-trigger, so Metabase won't have time to discover the new tables.
# The first apply will fail on the table lookup; just re-run the workflow and
# the second apply will succeed once Metabase has finished syncing.
resource "time_sleep" "wait_for_database_sync" {
  depends_on = [
    metabase_database.bigquery,
    metabase_database.postgres,
    metabase_database.tenant_postgres,
  ]

  create_duration = "${var.database_sync_wait_seconds}s"
}

# Get the table reference from PostgreSQL
data "metabase_table" "screen_summary_table" {
  depends_on = [time_sleep.wait_for_database_sync]

  name   = "mart_screener_data"
  schema = "analytics"
  db_id  = tonumber(metabase_database.postgres.id)
}

# Get tenant-specific table references from PostgreSQL
data "metabase_table" "tenant_screen_summary_tables" {
  for_each = var.tenants

  depends_on = [time_sleep.wait_for_database_sync]

  name   = "mart_screener_data"
  schema = "analytics"
  db_id  = tonumber(metabase_database.tenant_postgres[each.key].id)
}

# Look up Metabase field IDs for filter columns (needed for field filter multi-select).
# Field IDs are environment-specific; this script queries the Metabase API at plan time.
data "external" "filter_field_ids" {
  depends_on = [time_sleep.wait_for_database_sync]

  program = ["python3", "${path.module}/scripts/get_field_ids.py"]

  query = {
    metabase_url = var.metabase_url
    username     = var.metabase_admin_email
    password     = var.metabase_admin_password
    database_ids = jsonencode({
      for k, v in var.tenants : k => metabase_database.tenant_postgres[k].id
    })
    field_names = jsonencode(["partner", "county"])
  }
}

# Global collection for admin-level analytics
resource "metabase_collection" "global" {
  depends_on = [time_sleep.wait_for_database_sync]

  name = "Global"
}

# Tenant collections - created sequentially to avoid Metabase race condition
# When adding new tenants, add a new resource and chain it to the previous one
#
# NOTE: Ideally we'd use for_each here, but Metabase has a race condition when
# creating multiple collections concurrently (duplicate key error in
# collection_permission_graph_revision). Tested with provider v0.14.0 and
# the issue persists. If fixed in a future version, replace with:
#
#   resource "metabase_collection" "tenant_collection" {
#     for_each   = var.tenants
#     name       = each.value.display_name
#     depends_on = [metabase_collection.global]
#   }
#   locals { tenant_collection_map = metabase_collection.tenant_collection }

resource "metabase_collection" "tenant_collection_nc" {
  name       = "North Carolina"
  depends_on = [metabase_collection.global]
}

resource "metabase_collection" "tenant_collection_co" {
  name       = "Colorado"
  depends_on = [metabase_collection.tenant_collection_nc]
}

resource "metabase_collection" "tenant_collection_tx" {
  name       = "Texas"
  depends_on = [metabase_collection.tenant_collection_co]
}

resource "metabase_collection" "tenant_collection_il" {
  name       = "Illinois"
  depends_on = [metabase_collection.tenant_collection_tx]
}

resource "metabase_collection" "tenant_collection_ma" {
  name       = "Massachusetts"
  depends_on = [metabase_collection.tenant_collection_il]
}

resource "metabase_collection" "tenant_collection_cesn" {
  name       = "CESN"
  depends_on = [metabase_collection.tenant_collection_ma]
}

resource "metabase_collection" "tenant_collection_co_tax_calculator" {
  name       = "CO Tax Calculator"
  depends_on = [metabase_collection.tenant_collection_cesn]
}

# Map for other resources to reference tenant collections by key
locals {
  tenant_collection_map = {
    nc                = metabase_collection.tenant_collection_nc
    co                = metabase_collection.tenant_collection_co
    tx                = metabase_collection.tenant_collection_tx
    il                = metabase_collection.tenant_collection_il
    ma                = metabase_collection.tenant_collection_ma
    cesn              = metabase_collection.tenant_collection_cesn
    co_tax_calculator = metabase_collection.tenant_collection_co_tax_calculator
  }

  # Scorecard counts for All-Time / Last 30 Days top row:
  # non-CESN: Completed Screeners, Qualified for Benefits %, Median Annual Benefits,
  #           Median Monthly Benefits, Qualified for Tax Credits %, Median Annual Tax Credits = 6
  # CESN: first 4 only (no tax credit programs)
  alltime_scorecard_count = { for k, v in var.tenants : k => k != "cesn" ? 6 : 4 }
  alltime_scorecard_width = { for k, v in var.tenants : k => 24 / local.alltime_scorecard_count[k] }
}


# Screen count card using PostgreSQL data
resource "metabase_card" "screen_count" {
  json = jsonencode({
    name                = "Completed Screens"
    description         = "Total count of completed screens from PostgreSQL"
    collection_id       = tonumber(metabase_collection.global.id)
    collection_position = null
    cache_ttl           = null
    query_type          = "query"
    dataset_query = {
      database = data.metabase_table.screen_summary_table.db_id
      query = {
        source-table = data.metabase_table.screen_summary_table.id
        aggregation = [
          ["count"]
        ]
      }
      type = "query"
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = {}
    parameters             = []
  })
}

# Tenant-specific screen count cards using shared template
resource "metabase_card" "tenant_screen_count" {
  for_each = var.tenants

  json = jsonencode(merge(local.screen_count_card_config, {
    # Override just the tenant-specific parts
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = merge(local.screen_count_card_config.dataset_query, {
      database = tonumber(data.metabase_table.tenant_screen_summary_tables[each.key].db_id)
      query = merge(local.screen_count_card_config.dataset_query.query, {
        source-table = tonumber(data.metabase_table.tenant_screen_summary_tables[each.key].id)
      })
    })
  }))
}

# Tenant-specific median annual benefits scorecard
resource "metabase_card" "tenant_median_annual_benefits" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Median Annual Benefits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual) AS median FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

# Tenant-specific median monthly benefits scorecard
resource "metabase_card" "tenant_median_monthly_benefits" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Median Monthly Benefits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual / 12.0) AS median FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

# Tenant-specific median annual tax credits scorecard
resource "metabase_card" "tenant_median_annual_tax_credits" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Median Annual Tax Credits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE tax_credits_annual > 0 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

# Tenant-specific daily screeners bar chart (last 7 days)
resource "metabase_card" "tenant_daily_screeners_7d" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Daily Screeners (Last 7 Days)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT submission_date, count(*) AS screeners FROM analytics.mart_screener_data WHERE submission_date >= CURRENT_DATE - INTERVAL '6 days' [[AND {{partner}}]] [[AND {{county}}]] GROUP BY submission_date ORDER BY submission_date"
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

# Tenant-specific top 10 partners table
resource "metabase_card" "tenant_top_partners" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "Which Partners Did The Screeners Come From?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/top_partners.sql", {})
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

# Tenant-specific top 10 counties table
resource "metabase_card" "tenant_top_counties" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "Which Counties Did The Screeners Come From?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/top_counties.sql", {})
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

# Helper card for partner filter dropdown values.
# The inner subquery (WHERE is_partner = false) excludes generic options (Friend, Google, etc.)
# from the partner filter. Although it looks unscoped, each Metabase instance connects to a
# tenant-specific DB with RLS applied, so mart_referrer_codes only contains that WL's rows at
# query time. No cross-WL contamination is possible.
resource "metabase_card" "tenant_partner_values" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Partner Values (Filter Helper)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "table"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native   = { query = "SELECT DISTINCT partner FROM analytics.mart_screener_data WHERE partner IS NOT NULL AND partner NOT IN (SELECT partner FROM analytics.mart_referrer_codes WHERE is_partner = false AND partner IS NOT NULL) UNION SELECT DISTINCT partner FROM analytics.mart_referrer_codes WHERE is_partner = true AND partner IS NOT NULL ORDER BY partner" }
    }
  }))
}

# Helper card for county filter dropdown values
resource "metabase_card" "tenant_county_values" {
  for_each = var.tenants

  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "County Values (Filter Helper)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "table"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native   = { query = "SELECT DISTINCT county FROM analytics.mart_screener_data WHERE county IS NOT NULL AND county <> '' ORDER BY county" }
    }
  }))
}

# Dashboard that shows analytics data (global aggregate across all tenants)
resource "metabase_dashboard" "analytics" {
  name                = "MFB Analytics Dashboard"
  description         = "Aggregate analytics across all white labels"
  collection_id       = tonumber(metabase_collection.global.id)
  collection_position = 1

  tabs_json = jsonencode([
    { id = 1, name = "All-Time Performance" },
    { id = 2, name = "Last 30 Days Performance" },
    { id = 3, name = "Households" },
    { id = 4, name = "Benefits & Immediate Needs" },
  ])

  cards_json = jsonencode(concat(
    # -------------------------------------------------------------------------
    # Tab 1: All-Time Performance
    # -------------------------------------------------------------------------
    [
      # Row 0: 6 scorecards (4 cols each = 24 total)
      {
        card_id                = tonumber(metabase_card.global_completed_screeners.id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 0
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_qualified_for_benefits_pct.id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 4
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_annual_benefits.id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 8
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_monthly_benefits.id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 12
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_qualified_for_tax_creds_pct.id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 16
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_annual_tax_credits.id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 20
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Row 4: Daily screeners bar chart (full width)
      {
        card_id                = tonumber(metabase_card.global_daily_screeners_7d.id)
        dashboard_tab_id       = 1
        row                    = 4
        col                    = 0
        size_x                 = 24
        size_y                 = 6
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Row 10: Top partners + top counties side-by-side
      {
        card_id                = tonumber(metabase_card.global_top_partners.id)
        dashboard_tab_id       = 1
        row                    = 10
        col                    = 0
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_top_counties.id)
        dashboard_tab_id       = 1
        row                    = 10
        col                    = 12
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
    ],
    # -------------------------------------------------------------------------
    # Tab 2: Last 30 Days Performance
    # -------------------------------------------------------------------------
    [
      # Row 0: 6 scorecards
      {
        card_id                = tonumber(metabase_card.global_completed_screeners_30d.id)
        dashboard_tab_id       = 2
        row                    = 0
        col                    = 0
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_qualified_for_benefits_pct_30d.id)
        dashboard_tab_id       = 2
        row                    = 0
        col                    = 4
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_annual_benefits_30d.id)
        dashboard_tab_id       = 2
        row                    = 0
        col                    = 8
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_monthly_benefits_30d.id)
        dashboard_tab_id       = 2
        row                    = 0
        col                    = 12
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_qualified_for_tax_creds_pct_30d.id)
        dashboard_tab_id       = 2
        row                    = 0
        col                    = 16
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_annual_tax_credits_30d.id)
        dashboard_tab_id       = 2
        row                    = 0
        col                    = 20
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Row 4: Bar chart
      {
        card_id                = tonumber(metabase_card.global_daily_screeners_30d.id)
        dashboard_tab_id       = 2
        row                    = 4
        col                    = 0
        size_x                 = 24
        size_y                 = 6
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Row 10: Two tables side-by-side
      {
        card_id                = tonumber(metabase_card.global_top_partners_30d.id)
        dashboard_tab_id       = 2
        row                    = 10
        col                    = 0
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_top_counties_30d.id)
        dashboard_tab_id       = 2
        row                    = 10
        col                    = 12
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
    ],
    # -------------------------------------------------------------------------
    # Tab 3: Households
    # -------------------------------------------------------------------------
    [
      # Row 0: 6 scorecards
      {
        card_id                = tonumber(metabase_card.global_completed_screeners.id)
        dashboard_tab_id       = 3
        row                    = 0
        col                    = 0
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_household_size.id)
        dashboard_tab_id       = 3
        row                    = 0
        col                    = 4
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_household_assets.id)
        dashboard_tab_id       = 3
        row                    = 0
        col                    = 8
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_annual_income.id)
        dashboard_tab_id       = 3
        row                    = 0
        col                    = 12
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_monthly_income.id)
        dashboard_tab_id       = 3
        row                    = 0
        col                    = 16
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_median_monthly_expenses.id)
        dashboard_tab_id       = 3
        row                    = 0
        col                    = 20
        size_x                 = 4
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Row 4: Text block + age distribution charts
      {
        card_id            = null
        dashboard_tab_id   = 3
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
        card_id                = tonumber(metabase_card.global_head_of_household_ages.id)
        dashboard_tab_id       = 3
        row                    = 4
        col                    = 6
        size_x                 = 9
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_household_member_ages.id)
        dashboard_tab_id       = 3
        row                    = 4
        col                    = 15
        size_x                 = 9
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Row 12: Household sizes + languages
      {
        card_id                = tonumber(metabase_card.global_household_sizes.id)
        dashboard_tab_id       = 3
        row                    = 12
        col                    = 0
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_household_languages.id)
        dashboard_tab_id       = 3
        row                    = 12
        col                    = 12
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Row 20: Text block + income/assets distributions
      {
        card_id            = null
        dashboard_tab_id   = 3
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
      {
        card_id                = tonumber(metabase_card.global_household_income_distribution.id)
        dashboard_tab_id       = 3
        row                    = 20
        col                    = 6
        size_x                 = 9
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_household_assets_distribution.id)
        dashboard_tab_id       = 3
        row                    = 20
        col                    = 15
        size_x                 = 9
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Row 28: Income streams + expenses tables
      {
        card_id                = tonumber(metabase_card.global_income_streams.id)
        dashboard_tab_id       = 3
        row                    = 28
        col                    = 0
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_common_expenses.id)
        dashboard_tab_id       = 3
        row                    = 28
        col                    = 12
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
    ],
    # -------------------------------------------------------------------------
    # Tab 4: Benefits & Immediate Needs
    # -------------------------------------------------------------------------
    [
      {
        card_id            = null
        dashboard_tab_id   = 4
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
          text = "# Live | Benefits & Immediate Needs"
        }
      },
      {
        card_id                = tonumber(metabase_card.global_completed_screeners.id)
        dashboard_tab_id       = 4
        row                    = 2
        col                    = 0
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_already_had_benefits_pct.id)
        dashboard_tab_id       = 4
        row                    = 2
        col                    = 6
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_qualified_for_benefits_pct.id)
        dashboard_tab_id       = 4
        row                    = 2
        col                    = 12
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_qualified_for_tax_creds_pct.id)
        dashboard_tab_id       = 4
        row                    = 2
        col                    = 18
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_current_benefits_table.id)
        dashboard_tab_id       = 4
        row                    = 6
        col                    = 0
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_qualified_benefits_table.id)
        dashboard_tab_id       = 4
        row                    = 6
        col                    = 12
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.global_immediate_needs_table.id)
        dashboard_tab_id       = 4
        row                    = 14
        col                    = 0
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
    ],
  ))
}

# Tenant-specific dashboards
resource "metabase_dashboard" "tenant_analytics" {
  for_each = var.tenants

  name                = "${each.value.display_name} Dashboard"
  description         = "Main ${each.value.display_name} white label dashboard"
  collection_id       = tonumber(local.tenant_collection_map[each.key].id)
  collection_position = 1

  parameters_json = jsonencode(concat(
    (
      local.tenant_has_tab[each.key]["households"] ||
      local.tenant_has_tab[each.key]["last_30_days"] ||
      local.tenant_has_tab[each.key]["benefits_needs"]
      ) ? [
      {
        id                 = "partner_filter"
        name               = "Partner"
        slug               = "partner"
        type               = "string/="
        sectionId          = "string"
        values_query_type  = "list"
        values_source_type = "card"
        values_source_config = {
          card_id     = tonumber(metabase_card.tenant_partner_values[each.key].id)
          value_field = ["field", "partner", { "base-type" = "type/Text" }]
        }
      },
      {
        id                 = "county_filter"
        name               = "County"
        slug               = "county"
        type               = "string/="
        sectionId          = "string"
        values_query_type  = "list"
        values_source_type = "card"
        values_source_config = {
          card_id     = tonumber(metabase_card.tenant_county_values[each.key].id)
          value_field = ["field", "county", { "base-type" = "type/Text" }]
        }
      }
    ] : [],
    (local.tenant_has_tab[each.key]["last_30_days"]) ? [
      {
        id        = "date_range_filter"
        name      = "Date Range"
        slug      = "date_range"
        type      = "date/all-options"
        sectionId = "date"
        default   = "past30days"
      }
    ] : [],

    # Start/End date filters — shown for tenants with a Google Analytics tab.
    # Using plain date variables instead of field filters to avoid the Metabase BigQuery
    # driver bug that generates `schema.table`.column references BigQuery can't parse.
    local.tenant_has_tab[each.key]["google_analytics"] && var.bigquery_enabled ? [
      {
        id        = "ga_start_date_filter"
        name      = "Start Date"
        slug      = "start_date"
        type      = "date/single"
        sectionId = "date"
      },
      {
        id        = "ga_end_date_filter"
        name      = "End Date"
        slug      = "end_date"
        type      = "date/single"
        sectionId = "date"
      }
    ] : []
  ))

  tabs_json = jsonencode([
    for tab_key in local.tenant_tabs[each.key] : local.all_tabs[each.key][tab_key]
  ])

  cards_json = jsonencode(concat(
    # Tab 1: Google Analytics
    local.tenant_has_tab[each.key]["google_analytics"] ? local.tenant_dashboard_ga_layout[each.key] : [],
    # Tab 2: All-Time Performance (full layout with partner filter, or simple screen count)
    # Tab 2: All-Time Performance
    # flatten(concat(...)) lets us conditionally include CESN-excluded cards
    local.tenant_has_tab[each.key]["households"] ? flatten(concat(
      [
        {
          card_id          = tonumber(metabase_card.tenant_completed_screeners[each.key].id)
          dashboard_tab_id = 2
          row              = 0
          col              = 0
          size_x           = local.alltime_scorecard_width[each.key]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_completed_screeners[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_completed_screeners[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.tenant_qualified_for_benefits_pct[each.key].id)
          dashboard_tab_id = 2
          row              = 0
          col              = local.alltime_scorecard_width[each.key] * 1
          size_x           = local.alltime_scorecard_width[each.key]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_benefits_pct[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_benefits_pct[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.tenant_median_annual_benefits[each.key].id)
          dashboard_tab_id = 2
          row              = 0
          col              = local.alltime_scorecard_width[each.key] * 2
          size_x           = local.alltime_scorecard_width[each.key]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_benefits[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_benefits[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.tenant_median_monthly_benefits[each.key].id)
          dashboard_tab_id = 2
          row              = 0
          col              = local.alltime_scorecard_width[each.key] * 3
          size_x           = local.alltime_scorecard_width[each.key]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_benefits[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_monthly_benefits[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ],
      # Tax credit cards — hidden for CESN (no tax credit programs)
      each.key != "cesn" ? [
        {
          card_id          = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[each.key].id)
          dashboard_tab_id = 2
          row              = 0
          col              = local.alltime_scorecard_width[each.key] * 4
          size_x           = local.alltime_scorecard_width[each.key]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      each.key != "cesn" ? [
        {
          card_id          = tonumber(metabase_card.tenant_median_annual_tax_credits[each.key].id)
          dashboard_tab_id = 2
          row              = 0
          col              = local.alltime_scorecard_width[each.key] * 5
          size_x           = local.alltime_scorecard_width[each.key]
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_tax_credits[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_median_annual_tax_credits[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      [
        {
          card_id          = tonumber(metabase_card.tenant_daily_screeners_7d[each.key].id)
          dashboard_tab_id = 2
          row              = 4
          col              = 0
          size_x           = 24
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_daily_screeners_7d[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_daily_screeners_7d[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ],
      # Top Partners chart — hidden for CESN (no partner tracking)
      each.key != "cesn" ? [
        {
          card_id          = tonumber(metabase_card.tenant_top_partners[each.key].id)
          dashboard_tab_id = 2
          row              = 10
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_top_partners[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_top_partners[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : [],
      [
        {
          card_id          = tonumber(metabase_card.tenant_top_counties[each.key].id)
          dashboard_tab_id = 2
          row              = 10
          col              = each.key != "cesn" ? 12 : 0
          size_x           = each.key != "cesn" ? 12 : 24
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = "partner_filter"
              card_id      = tonumber(metabase_card.tenant_top_counties[each.key].id)
              target       = ["dimension", ["template-tag", "partner"]]
            },
            {
              parameter_id = "county_filter"
              card_id      = tonumber(metabase_card.tenant_top_counties[each.key].id)
              target       = ["dimension", ["template-tag", "county"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ],
    )) : [
      {
        card_id                = tonumber(metabase_card.tenant_screen_count[each.key].id)
        dashboard_tab_id       = 2
        row                    = 0
        col                    = 0
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      }
    ],
    # Tab 3: Last 30 Days Performance
    local.tenant_has_tab[each.key]["last_30_days"] ? local.tenant_dashboard_last_30_days_layout[each.key] : [],
    # Tab 4: Households (flatten+for avoids the conditional type mismatch
    # between the mixed text/data tuple and an empty list)
    flatten([for k in [each.key] : local.tenant_dashboard_households_data_layout[k] if local.tenant_has_tab[k]["households"]]),
    # Tab 5: Benefits & Immediate Needs (all tenants)
    local.tenant_dashboard_benefits_needs_layout[each.key],
    # Tab 6: Homeowners vs Renters (CESN only)
    flatten([for k in [each.key] : local.tenant_dashboard_cesn_hvr_layout if local.tenant_has_tab[k]["cesn_homeowners_vs_renters"]]),
  ))
}
