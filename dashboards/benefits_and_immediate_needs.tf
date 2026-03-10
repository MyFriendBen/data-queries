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
    SUM(count) as "# of Screeners",
    SUM(count)::float / NULLIF(MAX(t.total_count), 0) as "% of Screeners"
FROM analytics.mart_current_benefits
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
        "[\"name\",\"% of Screeners\"]" = { "number_style" = "percent", "show_mini_bar" = true, "color" = "#DF7F44" }
      }
    }
    parameters = []
  })
}

locals {
  tenant_tab_5_cards = {
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
