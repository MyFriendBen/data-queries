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
      native   = { query = "SELECT count(*) FILTER (WHERE has_benefits = 'true')::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data" }
      type     = "native"
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = { "scalar.field" = "pct", "column_settings" = { "[\"name\",\"pct\"]" = { "number_style" = "percent", "decimals" = 0 } } }
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
      native   = { query = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data" }
      type     = "native"
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = { "scalar.field" = "pct", "column_settings" = { "[\"name\",\"pct\"]" = { "number_style" = "percent", "decimals" = 0 } } }
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
      native   = { query = "SELECT count(*) FILTER (WHERE tax_credits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data" }
      type     = "native"
    }
    parameter_mappings     = []
    display                = "scalar"
    visualization_settings = { "scalar.field" = "pct", "column_settings" = { "[\"name\",\"pct\"]" = { "number_style" = "percent", "decimals" = 0 } } }
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
    SUM(count) as "# of Screeners",
    SUM(count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_current_benefits
CROSS JOIN totals t
GROUP BY benefit
HAVING SUM(count) > 0
ORDER BY SUM(count) DESC
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
        "[\"name\",\"% of Screeners\"]" = { "number_style" = "percent", "show_mini_bar" = true, "color" = "#DF7F44", "decimals" = 0 }
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
WITH totals AS (
    SELECT count(*) as total_count FROM analytics.mart_screener_data
)
SELECT 
    qb.benefit as "Benefit Name",
    SUM(qb.count) as "# of Screeners",
    SUM(qb.count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_qualified_benefits qb
CROSS JOIN totals t
GROUP BY qb.benefit
ORDER BY SUM(qb.count) DESC
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
        "[\"name\",\"% of Screeners\"]" = { "number_style" = "percent", "show_mini_bar" = true, "color" = "#DF7F44", "decimals" = 0 }
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
    SUM(count) as "# of Screeners",
    SUM(count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_immediate_needs
CROSS JOIN totals t
GROUP BY benefit
ORDER BY SUM(count) DESC
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
        "[\"name\",\"% of Screeners\"]" = { "number_style" = "percent", "show_mini_bar" = true, "color" = "#DF7F44", "decimals" = 0 }
      }
    }
    parameters = []
  })
}

locals {
  tenant_dashboard_benefits_needs_layout = {
    for k, v in var.tenants : k => [
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
        card_id                = tonumber(metabase_card.tenant_completed_screeners[k].id)
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
        card_id                = tonumber(metabase_card.tenant_already_had_benefits_pct[k].id)
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
        card_id                = tonumber(metabase_card.tenant_qualified_for_benefits_pct[k].id)
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
        card_id                = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[k].id)
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
        card_id                = tonumber(metabase_card.tenant_current_benefits_table[k].id)
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
        card_id                = tonumber(metabase_card.tenant_qualified_benefits_table[k].id)
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
        card_id                = tonumber(metabase_card.tenant_immediate_needs_table[k].id)
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
  }
}
