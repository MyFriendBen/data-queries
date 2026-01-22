# Metabase provider - only configure if Metabase is already set up
provider "metabase" {
  endpoint = "${var.metabase_url}/api"
  username = var.metabase_admin_email
  password = var.metabase_admin_password
}

# Shared configuration template for completed screens cards
locals {
  completed_screens_card_config = {
    name                = "Completed Screens"
    description         = "Total count of completed screens from mart_screener_data"
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
      ssl      = false
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
      ssl      = false
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

  create_duration = "120s"
}

# Get the table reference from BigQuery
data "metabase_table" "conversion_funnel_table" {
  depends_on = [time_sleep.wait_for_database_sync]

  name  = "mart_screener_conversion_funnel"
  db_id = tonumber(metabase_database.bigquery.id)
}

# Get the table reference from PostgreSQL
data "metabase_table" "screener_data_table" {
  depends_on = [time_sleep.wait_for_database_sync]

  name   = "mart_screener_data"
  schema = "analytics"
  db_id  = tonumber(metabase_database.postgres.id)
}

# Get tenant-specific table references from PostgreSQL
data "metabase_table" "tenant_screener_data_tables" {
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

resource "metabase_collection" "tenant_collection_nc" {
  name       = "North Carolina"
  depends_on = [metabase_collection.global]
}

resource "metabase_collection" "tenant_collection_co" {
  name       = "Colorado"
  depends_on = [metabase_collection.tenant_collection_nc]
}

# Map for other resources to reference tenant collections by key
locals {
  tenant_collection_map = {
    nc = metabase_collection.tenant_collection_nc
    co = metabase_collection.tenant_collection_co
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

# Completed screens card using PostgreSQL mart_screener_data
resource "metabase_card" "completed_screens" {
  json = jsonencode({
    name                = "Completed Screens"
    description         = "Total count of completed screens from mart_screener_data"
    collection_id       = tonumber(metabase_collection.global.id)
    collection_position = null
    cache_ttl           = null
    query_type          = "query"
    dataset_query = {
      database = data.metabase_table.screener_data_table.db_id
      query = {
        source-table = data.metabase_table.screener_data_table.id
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

# Individuals screened card using PostgreSQL mart_screener_data
resource "metabase_card" "individuals_screened" {
  json = jsonencode({
    name                = "Individuals Screened"
    description         = "Total sum of household_size from mart_screener_data"
    collection_id       = tonumber(metabase_collection.global.id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = data.metabase_table.screener_data_table.db_id
      type     = "native"
      native = {
        query = "SELECT SUM(household_size) FROM analytics.mart_screener_data"
      }
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = {}
    parameters             = []
  })
}

# Tenant-specific completed screens cards using shared template
resource "metabase_card" "tenant_completed_screens" {
  for_each = var.tenants

  json = jsonencode(merge(local.completed_screens_card_config, {
    # Override just the tenant-specific parts
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = merge(local.completed_screens_card_config.dataset_query, {
      database = tonumber(data.metabase_table.tenant_screener_data_tables[each.key].db_id)
      query = merge(local.completed_screens_card_config.dataset_query.query, {
        source-table = tonumber(data.metabase_table.tenant_screener_data_tables[each.key].id)
      })
    })
  }))
}

# Tenant-specific individuals screened cards
resource "metabase_card" "tenant_individuals_screened" {
  for_each = var.tenants

  json = jsonencode({
    name                = "Individuals Screened"
    description         = "Total sum of household_size from mart_screener_data"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(data.metabase_table.tenant_screener_data_tables[each.key].db_id)
      type     = "native"
      native = {
        query = "SELECT SUM(household_size) FROM analytics.mart_screener_data"
      }
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = {}
    parameters             = []
  })
}

# Dashboard that shows BigQuery data
resource "metabase_dashboard" "analytics" {
  name          = "MFB Analytics Dashboard"
  collection_id = tonumber(metabase_collection.global.id)
  cards_json = jsonencode([
    {
      card_id = tonumber(metabase_card.conversion_funnel.id)
      row = 0
      col = 0
      size_x = 12
      size_y = 8
      parameter_mappings = []
      series = []
      visualization_settings = {}
    },
    {
      card_id = tonumber(metabase_card.completed_screens.id)
      row = 8
      col = 0
      size_x = 6
      size_y = 4
      parameter_mappings = []
      series = []
      visualization_settings = {}
    },
    {
      card_id = tonumber(metabase_card.individuals_screened.id)
      row = 8
      col = 6
      size_x = 6
      size_y = 4
      parameter_mappings = []
      series = []
      visualization_settings = {}
    }
  ])
}

# Tenant-specific dashboards
resource "metabase_dashboard" "tenant_analytics" {
  for_each = var.tenants

  name       = "${each.value.display_name} Dashboard"
  collection_id = tonumber(local.tenant_collection_map[each.key].id)

  cards_json = jsonencode([
    {
      card_id = tonumber(metabase_card.tenant_completed_screens[each.key].id)
      row = 0
      col = 0
      size_x = 6
      size_y = 4
      parameter_mappings = []
      series = []
      visualization_settings = {}
    },
    {
      card_id = tonumber(metabase_card.tenant_individuals_screened[each.key].id)
      row = 0
      col = 6
      size_x = 6
      size_y = 4
      parameter_mappings = []
      series = []
      visualization_settings = {}
    }
  ])
}