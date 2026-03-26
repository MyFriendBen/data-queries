# Cards for "Google Analytics" (Tab 1)

resource "metabase_card" "tenant_monthly_active_users" {
  for_each = var.bigquery_enabled ? var.tenants : {}

  json = jsonencode({
    name                   = "What is the monthly active users (MAU) trend?"
    description            = "Distinct GA4 users per month from BigQuery page view events"
    collection_id          = tonumber(local.tenant_collection_map[each.key].id)
    collection_position    = null
    cache_ttl              = null
    query_type             = "native"
    display                = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.bigquery[0].id)
      native = {
        query = templatefile("${path.module}/sql/monthly_active_users.sql", {
          state_code = each.key
        })
      }
    }
    visualization_settings = {
      "graph.dimensions"        = ["month"]
      "graph.metrics"           = ["active_users"]
      "graph.x_axis.title_text" = ""
      "graph.y_axis.title_text" = ""
      "graph.show_values"       = true
      "series_settings" = {
        "active_users" = { color = "#509EE3" }
      }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# --- Layout ---

locals {
  tenant_dashboard_ga_layout = {
    for key, tenant in var.tenants : key => var.bigquery_enabled ? [
      {
        card_id                = tonumber(metabase_card.tenant_monthly_active_users[key].id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 0
        size_x                 = 24
        size_y                 = 8
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      }
    ] : []
  }
}
