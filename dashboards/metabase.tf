# Metabase provider - only configure if Metabase is already set up
provider "metabase" {
  endpoint = "${var.metabase_url}/api"
  username = var.metabase_admin_email
  password = var.metabase_admin_password
}

# Shared configuration template for screen count cards
locals {
  screen_count_card_config = {
    name                = "Completed Screens"
    description         = "Total count of completed screens from PostgreSQL"
    collection_position = null
    cache_ttl           = null
    query_type          = "query"
    dataset_query = {
      query = {
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
  }
}

resource "metabase_database" "bigquery" {
  name = "MFB BigQuery Analytics"
  bigquery_details = {
    service_account_key  = local.bigquery_key
    project_id           = var.gcp_project_id
    dataset_filters_type = "all"
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
      user             = var.tenant_db_credentials[each.key].username
      password         = var.tenant_db_credentials[each.key].password
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
resource "time_sleep" "wait_for_database_sync" {
  depends_on = [
    metabase_database.bigquery,
    metabase_database.postgres,
    metabase_database.tenant_postgres
  ]

  create_duration = "${var.database_sync_wait_seconds}s"
}

# Get the table reference from BigQuery
data "metabase_table" "conversion_funnel_table" {
  depends_on = [time_sleep.wait_for_database_sync]

  name  = "mart_screener_conversion_funnel"
  db_id = tonumber(metabase_database.bigquery.id)
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
}

# Card following GitHub example exactly but with our BigQuery table
resource "metabase_card" "conversion_funnel" {
  json = jsonencode({
    name                = "Conversion Funnel Insights"
    description         = "Analytics from BigQuery conversion funnel data"
    collection_id       = tonumber(metabase_collection.global.id)
    collection_position = null
    cache_ttl           = null
    query_type          = "query"
    dataset_query = {
      database = data.metabase_table.conversion_funnel_table.db_id
      query = {
        source-table = data.metabase_table.conversion_funnel_table.id
        aggregation = [
          ["count"]
        ]
      }
      type = "query"
    }
    parameter_mappings     = []
    display                = "table"
    visualization_settings = {}
    parameters             = []
  })
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

# Tenant-specific scorecard metrics for "Benefits & Immediate Needs"
resource "metabase_card" "tenant_completed_screeners" {
  for_each = var.tenants
  json = jsonencode({
    name                = "Completed Screeners"
    description         = null
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native   = { query = "SELECT count(*) FROM analytics.mart_screener_data" }
      type     = "native"
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = { "scalar.field" = "count" }
    parameters             = []
  })
}

resource "metabase_card" "tenant_already_had_benefits_pct" {
  for_each = var.tenants
  json = jsonencode({
    name                = "Already Had Benefits"
    description         = null
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native   = { query = "SELECT (SELECT count(*) FROM analytics.mart_screener_data WHERE has_benefits = 'true')::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data" }
      type     = "native"
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = { "scalar.field" = "pct", "column_settings" = { "[\"name\",\"pct\"]" = { "number_style" = "percent" } } }
    parameters             = []
  })
}

resource "metabase_card" "tenant_qualified_for_benefits_pct" {
  for_each = var.tenants
  json = jsonencode({
    name                = "Qualified for Benefits *"
    description         = null
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native   = { query = "SELECT (SELECT count(*) FROM analytics.mart_screener_data WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data" }
      type     = "native"
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = { "scalar.field" = "pct", "column_settings" = { "[\"name\",\"pct\"]" = { "number_style" = "percent" } } }
    parameters             = []
  })
}

resource "metabase_card" "tenant_qualified_for_tax_creds_pct" {
  for_each = var.tenants
  json = jsonencode({
    name                = "Qualified for Tax Credits *"
    description         = null
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native   = { query = "SELECT (SELECT count(*) FROM analytics.mart_screener_data WHERE tax_credits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data" }
      type     = "native"
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = { "scalar.field" = "pct", "column_settings" = { "[\"name\",\"pct\"]" = { "number_style" = "percent" } } }
    parameters             = []
  })
}

# Table: What percentage of users said they already had certain benefits?
resource "metabase_card" "tenant_current_benefits_table" {
  for_each = var.tenants
  json = jsonencode({
    name                = "What percentage of users said they already had certain benefits?"
    description         = null
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = <<EOF
WITH totals AS (SELECT count(*) as total_count FROM analytics.mart_screener_data)
SELECT 
    benefit as "Benefit Name",
    count as "# of Screeners",
    count::float / NULLIF(t.total_count, 0) as "% of Screeners"
FROM analytics.mart_current_benefits, totals t
ORDER BY count DESC
EOF
      }
      type = "native"
    }
    parameter_mappings = []
    display            = "table"
    visualization_settings = {
      "table.column_widths" = [{ "name" = "Benefit Name", "width" = 300 }]
      "column_settings" = {
        "[\"name\",\"# of Screeners\"]" = { "show_mini_bar" = true, "color" = "#293458" }
        "[\"name\",\"% of Screeners\"]" = { "number_style" = "percent", "show_mini_bar" = true, "color" = "#DF7F44" }
      }
    }
    parameters = []
  })
}

# Table: What percentage of completed screeners qualified for benefits?

resource "metabase_card" "tenant_qualified_benefits_table" {
  for_each = var.tenants
  json = jsonencode({
    name                = "What percentage of completed screeners qualified for benefits?"
    description         = "Aggregated benefit eligibility data. RLS automatically filters to tenant white_label."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = <<EOF
-- Query mart_screener_data directly. RLS policy automatically filters to the tenant's white_label_id.
-- Each benefit eligibility column (*_annual) is counted where > 0, showing state-specific benefits for the tenant.
WITH totals AS (
    SELECT count(*) as total_count FROM analytics.mart_screener_data
),
qualified_benefits AS (
    SELECT 'Lifeline' as benefit, count(*) as count FROM analytics.mart_screener_data WHERE lifeline_annual > 0 UNION ALL
    SELECT 'SNAP', count(*) FROM analytics.mart_screener_data WHERE snap_annual > 0 UNION ALL
    SELECT 'CO SNAP', count(*) FROM analytics.mart_screener_data WHERE co_snap_annual > 0 UNION ALL
    SELECT 'NC SNAP', count(*) FROM analytics.mart_screener_data WHERE nc_snap_annual > 0 UNION ALL
    SELECT 'IL SNAP', count(*) FROM analytics.mart_screener_data WHERE il_snap_annual > 0 UNION ALL
    SELECT 'MA SNAP', count(*) FROM analytics.mart_screener_data WHERE ma_snap_annual > 0 UNION ALL
    SELECT 'WIC', count(*) FROM analytics.mart_screener_data WHERE wic_annual > 0 UNION ALL
    SELECT 'CO WIC', count(*) FROM analytics.mart_screener_data WHERE co_wic_annual > 0 UNION ALL
    SELECT 'NC WIC', count(*) FROM analytics.mart_screener_data WHERE nc_wic_annual > 0 UNION ALL
    SELECT 'IL WIC', count(*) FROM analytics.mart_screener_data WHERE il_wic_annual > 0 UNION ALL
    SELECT 'MA WIC', count(*) FROM analytics.mart_screener_data WHERE ma_wic_annual > 0 UNION ALL
    SELECT 'TANF', count(*) FROM analytics.mart_screener_data WHERE tanf_annual > 0 UNION ALL
    SELECT 'CO TANF', count(*) FROM analytics.mart_screener_data WHERE co_tanf_annual > 0 UNION ALL
    SELECT 'NC TANF', count(*) FROM analytics.mart_screener_data WHERE nc_tanf_annual > 0 UNION ALL
    SELECT 'IL TANF', count(*) FROM analytics.mart_screener_data WHERE il_tanf_annual > 0 UNION ALL
    SELECT 'MA TAFDC', count(*) FROM analytics.mart_screener_data WHERE ma_tafdc_annual > 0 UNION ALL
    SELECT 'Medicaid', count(*) FROM analytics.mart_screener_data WHERE medicaid_annual > 0 UNION ALL
    SELECT 'CO Medicaid', count(*) FROM analytics.mart_screener_data WHERE co_medicaid_annual > 0 UNION ALL
    SELECT 'NC Medicaid', count(*) FROM analytics.mart_screener_data WHERE nc_medicaid_annual > 0 UNION ALL
    SELECT 'IL Medicaid', count(*) FROM analytics.mart_screener_data WHERE il_medicaid_annual > 0 UNION ALL
    SELECT 'MA Mass Health', count(*) FROM analytics.mart_screener_data WHERE ma_mass_health_annual > 0 UNION ALL
    SELECT 'NC Emergency Medicaid', count(*) FROM analytics.mart_screener_data WHERE nc_emergency_medicaid_annual > 0 UNION ALL
    SELECT 'Emergency Medicaid', count(*) FROM analytics.mart_screener_data WHERE emergency_medicaid_annual > 0 UNION ALL
    SELECT 'NC SCCA', count(*) FROM analytics.mart_screener_data WHERE nc_scca_annual > 0 UNION ALL
    SELECT 'NC LIEAP', count(*) FROM analytics.mart_screener_data WHERE nc_lieap_annual > 0 UNION ALL
    SELECT 'NCCIP', count(*) FROM analytics.mart_screener_data WHERE nccip_annual > 0 UNION ALL
    SELECT 'SSI', count(*) FROM analytics.mart_screener_data WHERE ssi_annual > 0 UNION ALL
    SELECT 'NSLP', count(*) FROM analytics.mart_screener_data WHERE nslp_annual > 0 UNION ALL
    SELECT 'IL NSLP', count(*) FROM analytics.mart_screener_data WHERE il_nslp_annual > 0 UNION ALL
    SELECT 'EITC', count(*) FROM analytics.mart_screener_data WHERE eitc_annual > 0 UNION ALL
    SELECT 'CO EITC', count(*) FROM analytics.mart_screener_data WHERE coeitc_annual > 0 UNION ALL
    SELECT 'IL EITC', count(*) FROM analytics.mart_screener_data WHERE il_eitc_annual > 0 UNION ALL
    SELECT 'MA EITC', count(*) FROM analytics.mart_screener_data WHERE ma_maeitc_annual > 0 UNION ALL
    SELECT 'CTC', count(*) FROM analytics.mart_screener_data WHERE ctc_annual > 0 UNION ALL
    SELECT 'CO CTC', count(*) FROM analytics.mart_screener_data WHERE coctc_annual > 0 UNION ALL
    SELECT 'IL CTC', count(*) FROM analytics.mart_screener_data WHERE il_ctc_annual > 0 UNION ALL
    SELECT 'OAP', count(*) FROM analytics.mart_screener_data WHERE oap_annual > 0 UNION ALL
    SELECT 'Sunbucks', count(*) FROM analytics.mart_screener_data WHERE sunbucks_annual > 0 UNION ALL
    SELECT 'LEAP', count(*) FROM analytics.mart_screener_data WHERE leap_annual > 0 UNION ALL
    SELECT 'ACP', count(*) FROM analytics.mart_screener_data WHERE acp_annual > 0 UNION ALL
    SELECT 'CCAP', count(*) FROM analytics.mart_screener_data WHERE ccap_annual > 0 UNION ALL
    SELECT 'Pell Grant', count(*) FROM analytics.mart_screener_data WHERE pell_grant_annual > 0 UNION ALL
    SELECT 'ERAP', count(*) FROM analytics.mart_screener_data WHERE erap_annual > 0
)
SELECT 
    benefit as "Benefit Name",
    count as "# of Screeners",
    count::float / NULLIF(t.total_count, 0) as "% of Screeners"
FROM qualified_benefits, totals t
WHERE count > 0
ORDER BY count DESC
EOF
      }
      type = "native"
    }
    parameter_mappings = []
    display            = "table"
    visualization_settings = {
      "table.column_widths" = [{ "name" = "Benefit Name", "width" = 300 }]
      "column_settings" = {
        "[\"name\",\"# of Screeners\"]" = { "show_mini_bar" = true, "color" = "#293458" }
        "[\"name\",\"% of Screeners\"]" = { "number_style" = "percent", "show_mini_bar" = true, "color" = "#DF7F44" }
      }
    }
    parameters = []
  })
}

# Table: What percentage of users sought each immediate need?
resource "metabase_card" "tenant_immediate_needs_table" {
  for_each = var.tenants
  json = jsonencode({
    name                = "What percentage of users sought each immediate need?"
    description         = null
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query = <<EOF
WITH totals AS (SELECT count(*) as total_count FROM analytics.mart_screener_data)
SELECT 
    benefit as "Need Category",
    count as "# of Screeners",
    count::float / NULLIF(t.total_count, 0) as "% of Screeners"
FROM analytics.mart_immediate_needs, totals t
ORDER BY count DESC
EOF
      }
      type = "native"
    }
    parameter_mappings = []
    display            = "table"
    visualization_settings = {
      "table.column_widths" = [{ "name" = "Need Category", "width" = 300 }]
      "column_settings" = {
        "[\"name\",\"# of Screeners\"]" = { "show_mini_bar" = true, "color" = "#293458" }
        "[\"name\",\"% of Screeners\"]" = { "number_style" = "percent", "show_mini_bar" = true, "color" = "#DF7F44" }
      }
    }
    parameters = []
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

# Dashboard that shows BigQuery data
resource "metabase_dashboard" "analytics" {
  name          = "MFB Analytics Dashboard"
  collection_id = tonumber(metabase_collection.global.id)
  cards_json = jsonencode([
    {
      card_id                = tonumber(metabase_card.conversion_funnel.id)
      row                    = 0
      col                    = 0
      size_x                 = 12
      size_y                 = 8
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    {
      card_id                = tonumber(metabase_card.screen_count.id)
      row                    = 8
      col                    = 0
      size_x                 = 6
      size_y                 = 4
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    }
  ])
}

# Tenant-specific dashboards
resource "metabase_dashboard" "tenant_analytics" {
  for_each = var.tenants

  name          = "${each.value.display_name} Dashboard"
  collection_id = tonumber(local.tenant_collection_map[each.key].id)

  tabs_json = jsonencode([
    { id = 1, name = "Google Analytics" },
    { id = 2, name = "All-Time Performance" },
    { id = 3, name = "Last 30 Days Performance" },
    { id = 4, name = "Households" },
    { id = 5, name = "Benefits & Immediate Needs" }
  ])

  cards_json = jsonencode(concat(
    # Tab 2: All-Time Performance
    [
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
    # Tab 5: Benefits & Immediate Needs
    [
      # Header Text Card
      {
        card_id            = null
        dashboard_tab_id   = 5
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
      # Scorecards Row 1
      {
        card_id                = tonumber(metabase_card.tenant_completed_screeners[each.key].id)
        dashboard_tab_id       = 5
        row                    = 2
        col                    = 0
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.tenant_already_had_benefits_pct[each.key].id)
        dashboard_tab_id       = 5
        row                    = 2
        col                    = 6
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.tenant_qualified_for_benefits_pct[each.key].id)
        dashboard_tab_id       = 5
        row                    = 2
        col                    = 12
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[each.key].id)
        dashboard_tab_id       = 5
        row                    = 2
        col                    = 18
        size_x                 = 6
        size_y                 = 4
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Tables Row 2
      {
        card_id                = tonumber(metabase_card.tenant_current_benefits_table[each.key].id)
        dashboard_tab_id       = 5
        row                    = 6
        col                    = 0
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.tenant_qualified_benefits_table[each.key].id)
        dashboard_tab_id       = 5
        row                    = 6
        col                    = 12
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      # Table Row 3
      {
        card_id                = tonumber(metabase_card.tenant_immediate_needs_table[each.key].id)
        dashboard_tab_id       = 5
        row                    = 14
        col                    = 0
        size_x                 = 12
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      }
    ]
  ))
}
