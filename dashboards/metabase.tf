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
    service_account_key      = local.bigquery_key
    project_id               = var.gcp_project_id
    dataset_filters_type     = "all"
  }
}

resource "metabase_database" "postgres" {
  name = "MFB PostgreSQL Analytics"

  custom_details = {
    engine = "postgres"

    details_json = jsonencode({
      host     = var.database_host
      port     = var.database_port
      dbname   = var.database_name
      user     = var.global_db_credentials.username
      password = var.global_db_credentials.password
      ssl      = var.database_ssl
      tunnel-enabled    = false
      advanced-options  = false
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
      host     = var.database_host
      port     = var.database_port
      dbname   = var.database_name
      user     = var.tenant_db_credentials[each.key].username
      password = var.tenant_db_credentials[each.key].password
      ssl      = var.database_ssl
      tunnel-enabled    = false
      advanced-options  = false
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

  # Maps each tenant key to its state_code in GA4 URL patterns (extracted by int_ga4_page_views)
  # Update cesn / co_tax_calculator once their GA4 URL state codes are confirmed
  tenant_ga_state_codes = {
    nc                = "nc"
    co                = "co"
    tx                = "tx"
    il                = "il"
    ma                = "ma"
    cesn              = "co" # shares Colorado GA4 data; update if CESN gets its own state tracking
    co_tax_calculator = "co" # shares Colorado GA4 data; update if CO Tax Calculator gets its own state tracking
  }

  # Convenience prefix for BigQuery table references in native SQL
  # Usage: wrap the full table path in backticks at the call site: `${local.bq_dataset}.table_name`
  bq_dataset = "${var.gcp_project_id}.${var.bigquery_analytics_dataset}"
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

# Global analytics dashboard — BigQuery conversion funnel + PostgreSQL screen count
resource "metabase_dashboard" "analytics" {
  name          = "MFB Analytics Dashboard"
  collection_id = tonumber(metabase_collection.global.id)
  cards_json = jsonencode([
    {
      card_id            = tonumber(metabase_card.conversion_funnel.id)
      row                = 0
      col                = 0
      size_x             = 12
      size_y             = 8
      parameter_mappings = []
      series             = []
      visualization_settings = {}
    },
    {
      card_id            = tonumber(metabase_card.screen_count.id)
      row                = 8
      col                = 0
      size_x             = 6
      size_y             = 4
      parameter_mappings = []
      series             = []
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

  # Metabase returns cards sorted by dashboard_tab_id ascending.
  # Tab 1 (Google Analytics) cards must come before tab 2 (All-Time Performance) to avoid
  # the provider "inconsistent result" error on cards_json round-trip comparison.
  cards_json = jsonencode([
    # ── Google Analytics tab (ID 1) ──────────────────────────────────────────
    # Row 0: 4 KPI scalar cards side-by-side (each 6 wide × 3 tall)
    {
      card_id          = tonumber(metabase_card.ga_total_visitors[each.key].id)
      dashboard_tab_id = 1
      row              = 0
      col              = 0
      size_x           = 6
      size_y           = 3
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.ga_started_screener_pct[each.key].id)
      dashboard_tab_id = 1
      row              = 0
      col              = 6
      size_x           = 6
      size_y           = 3
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.ga_completed_to_click_rate[each.key].id)
      dashboard_tab_id = 1
      row              = 0
      col              = 12
      size_x           = 6
      size_y           = 3
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.ga_median_completion_time[each.key].id)
      dashboard_tab_id = 1
      row              = 0
      col              = 18
      size_x           = 6
      size_y           = 3
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },

    # Row 3: Conversion funnel bar chart (12 wide × 6 tall)
    {
      card_id          = tonumber(metabase_card.ga_conversion_funnel[each.key].id)
      dashboard_tab_id = 1
      row              = 3
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    # Row 3: Conversion funnel detail table (right, 12 wide)
    {
      card_id          = tonumber(metabase_card.ga_conversion_funnel_table[each.key].id)
      dashboard_tab_id = 1
      row              = 3
      col              = 12
      size_x           = 12
      size_y           = 6
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },

    # Row 9: Traffic Mediums — bar chart (left) + detail table (right)
    {
      card_id          = tonumber(metabase_card.ga_traffic_mediums_bar[each.key].id)
      dashboard_tab_id = 1
      row              = 9
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.ga_traffic_mediums_table[each.key].id)
      dashboard_tab_id = 1
      row              = 9
      col              = 12
      size_x           = 12
      size_y           = 6
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },

    # Row 15: Clicked Links — bar chart (left) + detail table (right)
    {
      card_id          = tonumber(metabase_card.ga_clicked_links_bar[each.key].id)
      dashboard_tab_id = 1
      row              = 15
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.ga_clicked_links_table[each.key].id)
      dashboard_tab_id = 1
      row              = 15
      col              = 12
      size_x           = 12
      size_y           = 6
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    },

    # ── All-Time Performance tab (ID 2) — must come after tab 1 cards ────────
    {
      card_id          = tonumber(metabase_card.tenant_screen_count[each.key].id)
      dashboard_tab_id = 2
      row              = 0
      col              = 0
      size_x           = 6
      size_y           = 4
      parameter_mappings     = []
      series                 = []
      visualization_settings = {}
    }
  ])
}