# Metabase provider - only configure if Metabase is already set up
provider "metabase" {
  endpoint = "${var.metabase_url}/api"
  username = var.metabase_admin_email
  password = var.metabase_admin_password
}

# Shared configuration template for screen count cards
locals {
  screen_count_card_config = {
    name                = "Number of Screens"
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
    service_account_key      = file(var.bigquery_service_account_path)
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

# Get the table reference from BigQuery
data "metabase_table" "conversion_funnel_table" {
  name  = "mart_screener_conversion_funnel"
  db_id = tonumber(metabase_database.bigquery.id)
}

# Get the table reference from PostgreSQL
data "metabase_table" "screen_summary_table" {
  name   = "mart_screen_eligibility_summary"
  schema = "analytics"
  db_id  = tonumber(metabase_database.postgres.id)
}

# Get tenant-specific table references from PostgreSQL
data "metabase_table" "tenant_screen_summary_tables" {
  for_each = var.tenants
  
  depends_on = [metabase_database.tenant_postgres]
  
  name   = "mart_screen_eligibility_summary"
  schema = "analytics"
  db_id  = tonumber(metabase_database.tenant_postgres[each.key].id)
}

# Tenant-specific collections for organization
resource "metabase_collection" "tenant_collections" {
  for_each = var.tenants
  
  name = "${each.value.display_name} Analytics"
}

# Card following GitHub example exactly but with our BigQuery table
resource "metabase_card" "conversion_funnel" {
  json = jsonencode({
    name                = "💡 Conversion Funnel Insights"
    description         = "📖 Analytics from BigQuery conversion funnel data"
    collection_id       = null
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
    name                = "Number of Screens"
    description         = "Total count of completed screens from PostgreSQL"
    collection_id       = null
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
    collection_id = metabase_collection.tenant_collections[each.key].id
    dataset_query = merge(local.screen_count_card_config.dataset_query, {
      database = data.metabase_table.tenant_screen_summary_tables[each.key].db_id
      query = merge(local.screen_count_card_config.dataset_query.query, {
        source-table = data.metabase_table.tenant_screen_summary_tables[each.key].id
      })
    })
  }))

  lifecycle {
    ignore_changes = [json]
  }
}

# Dashboard that shows BigQuery data
resource "metabase_dashboard" "analytics" {
  name       = "MFB Analytics Dashboard"
  cards_json = jsonencode([
    {
      card_id = metabase_card.conversion_funnel.id
      row = 0
      col = 0
      size_x = 12
      size_y = 8
      parameter_mappings = []
      series = []
      visualization_settings = {}
    },
    {
      card_id = metabase_card.screen_count.id
      row = 8
      col = 0
      size_x = 6
      size_y = 4
      parameter_mappings = []
      series = []
      visualization_settings = {}
    }
  ])

  lifecycle {
    ignore_changes = [cards_json]
  }
}

# Tenant-specific dashboards
resource "metabase_dashboard" "tenant_analytics" {
  for_each = var.tenants

  name       = "${each.value.display_name} Analytics Dashboard"
  collection_id = metabase_collection.tenant_collections[each.key].id

  cards_json = jsonencode([
    {
      card_id = metabase_card.tenant_screen_count[each.key].id
      row = 0
      col = 0
      size_x = 6
      size_y = 4
      parameter_mappings = []
      series = []
      visualization_settings = {}
    }
  ])

  lifecycle {
    ignore_changes = [cards_json]
  }
}