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
    SELECT 'MA Mass Health Limited', count(*) FROM analytics.mart_screener_data WHERE ma_mass_health_limited_annual > 0 UNION ALL
    SELECT 'NC Emergency Medicaid', count(*) FROM analytics.mart_screener_data WHERE nc_emergency_medicaid_annual > 0 UNION ALL
    SELECT 'Emergency Medicaid', count(*) FROM analytics.mart_screener_data WHERE emergency_medicaid_annual > 0 UNION ALL
    SELECT 'AWD Medicaid', count(*) FROM analytics.mart_screener_data WHERE awd_medicaid_annual > 0 UNION ALL
    SELECT 'CWD Medicaid', count(*) FROM analytics.mart_screener_data WHERE cwd_medicaid_annual > 0 UNION ALL
    SELECT 'Medicare Savings', count(*) FROM analytics.mart_screener_data WHERE medicare_savings_annual > 0 UNION ALL
    SELECT 'NC SCCA', count(*) FROM analytics.mart_screener_data WHERE nc_scca_annual > 0 UNION ALL
    SELECT 'NC LIEAP', count(*) FROM analytics.mart_screener_data WHERE nc_lieap_annual > 0 UNION ALL
    SELECT 'NCCIP', count(*) FROM analytics.mart_screener_data WHERE nccip_annual > 0 UNION ALL
    SELECT 'NC ACA', count(*) FROM analytics.mart_screener_data WHERE nc_aca_annual > 0 UNION ALL
    SELECT 'NC WAP', count(*) FROM analytics.mart_screener_data WHERE ncwap_annual > 0 UNION ALL
    SELECT 'SSI', count(*) FROM analytics.mart_screener_data WHERE ssi_annual > 0 UNION ALL
    SELECT 'SSDI', count(*) FROM analytics.mart_screener_data WHERE ssdi_annual > 0 UNION ALL
    SELECT 'NSLP', count(*) FROM analytics.mart_screener_data WHERE nslp_annual > 0 UNION ALL
    SELECT 'IL NSLP', count(*) FROM analytics.mart_screener_data WHERE il_nslp_annual > 0 UNION ALL
    SELECT 'EITC', count(*) FROM analytics.mart_screener_data WHERE eitc_annual > 0 UNION ALL
    SELECT 'CO EITC', count(*) FROM analytics.mart_screener_data WHERE coeitc_annual > 0 UNION ALL
    SELECT 'IL EITC', count(*) FROM analytics.mart_screener_data WHERE il_eitc_annual > 0 UNION ALL
    SELECT 'MA EITC', count(*) FROM analytics.mart_screener_data WHERE ma_maeitc_annual > 0 UNION ALL
    SELECT 'CTC', count(*) FROM analytics.mart_screener_data WHERE ctc_annual > 0 UNION ALL
    SELECT 'CO CTC', count(*) FROM analytics.mart_screener_data WHERE coctc_annual > 0 UNION ALL
    SELECT 'IL CTC', count(*) FROM analytics.mart_screener_data WHERE il_ctc_annual > 0 UNION ALL
    SELECT 'FATC', count(*) FROM analytics.mart_screener_data WHERE fatc_annual > 0 UNION ALL
    SELECT 'SHITC', count(*) FROM analytics.mart_screener_data WHERE shitc_annual > 0 UNION ALL
    SELECT 'TABOR', count(*) FROM analytics.mart_screener_data WHERE tabor_annual > 0 UNION ALL
    SELECT 'OAP', count(*) FROM analytics.mart_screener_data WHERE oap_annual > 0 UNION ALL
    SELECT 'Sunbucks', count(*) FROM analytics.mart_screener_data WHERE sunbucks_annual > 0 UNION ALL
    SELECT 'LEAP', count(*) FROM analytics.mart_screener_data WHERE leap_annual > 0 UNION ALL
    SELECT 'ACP', count(*) FROM analytics.mart_screener_data WHERE acp_annual > 0 UNION ALL
    SELECT 'CCAP', count(*) FROM analytics.mart_screener_data WHERE ccap_annual > 0 UNION ALL
    SELECT 'Pell Grant', count(*) FROM analytics.mart_screener_data WHERE pell_grant_annual > 0 UNION ALL
    SELECT 'ERAP', count(*) FROM analytics.mart_screener_data WHERE erap_annual > 0 UNION ALL
    SELECT 'ANDCS', count(*) FROM analytics.mart_screener_data WHERE andcs_annual > 0 UNION ALL
    SELECT 'BCA', count(*) FROM analytics.mart_screener_data WHERE bca_annual > 0 UNION ALL
    SELECT 'CDHCS', count(*) FROM analytics.mart_screener_data WHERE cdhcs_annual > 0 UNION ALL
    SELECT 'CFHC', count(*) FROM analytics.mart_screener_data WHERE cfhc_annual > 0 UNION ALL
    SELECT 'CHP', count(*) FROM analytics.mart_screener_data WHERE chp_annual > 0 UNION ALL
    SELECT 'CHS', count(*) FROM analytics.mart_screener_data WHERE chs_annual > 0 UNION ALL
    SELECT 'CO CB', count(*) FROM analytics.mart_screener_data WHERE cocb_annual > 0 UNION ALL
    SELECT 'CO WAP', count(*) FROM analytics.mart_screener_data WHERE cowap_annual > 0 UNION ALL
    SELECT 'CPCR', count(*) FROM analytics.mart_screener_data WHERE cpcr_annual > 0 UNION ALL
    SELECT 'DPP', count(*) FROM analytics.mart_screener_data WHERE dpp_annual > 0 UNION ALL
    SELECT 'DPTR', count(*) FROM analytics.mart_screener_data WHERE dptr_annual > 0 UNION ALL
    SELECT 'DSR', count(*) FROM analytics.mart_screener_data WHERE dsr_annual > 0 UNION ALL
    SELECT 'DTR', count(*) FROM analytics.mart_screener_data WHERE dtr_annual > 0 UNION ALL
    SELECT 'EDE', count(*) FROM analytics.mart_screener_data WHERE ede_annual > 0 UNION ALL
    SELECT 'ERC', count(*) FROM analytics.mart_screener_data WHERE erc_annual > 0 UNION ALL
    SELECT 'FPS', count(*) FROM analytics.mart_screener_data WHERE fps_annual > 0 UNION ALL
    SELECT 'LWCR', count(*) FROM analytics.mart_screener_data WHERE lwcr_annual > 0 UNION ALL
    SELECT 'MA ACA', count(*) FROM analytics.mart_screener_data WHERE ma_aca_annual > 0 UNION ALL
    SELECT 'MA CCDF', count(*) FROM analytics.mart_screener_data WHERE ma_ccdf_annual > 0 UNION ALL
    SELECT 'MA CFC', count(*) FROM analytics.mart_screener_data WHERE ma_cfc_annual > 0 UNION ALL
    SELECT 'MA EAEDC', count(*) FROM analytics.mart_screener_data WHERE ma_eaedc_annual > 0 UNION ALL
    SELECT 'MA MBTA', count(*) FROM analytics.mart_screener_data WHERE ma_mbta_annual > 0 UNION ALL
    SELECT 'MA SSP', count(*) FROM analytics.mart_screener_data WHERE ma_ssp_annual > 0 UNION ALL
    SELECT 'My Denver', count(*) FROM analytics.mart_screener_data WHERE mydenver_annual > 0 UNION ALL
    SELECT 'My Spark', count(*) FROM analytics.mart_screener_data WHERE myspark_annual > 0 UNION ALL
    SELECT 'NF', count(*) FROM analytics.mart_screener_data WHERE nf_annual > 0 UNION ALL
    SELECT 'NFP', count(*) FROM analytics.mart_screener_data WHERE nfp_annual > 0 UNION ALL
    SELECT 'Omnisalud', count(*) FROM analytics.mart_screener_data WHERE omnisalud_annual > 0 UNION ALL
    SELECT 'RAG', count(*) FROM analytics.mart_screener_data WHERE rag_annual > 0 UNION ALL
    SELECT 'RHC', count(*) FROM analytics.mart_screener_data WHERE rhc_annual > 0 UNION ALL
    SELECT 'RTD Live', count(*) FROM analytics.mart_screener_data WHERE rtdlive_annual > 0 UNION ALL
    SELECT 'TRUA', count(*) FROM analytics.mart_screener_data WHERE trua_annual > 0 UNION ALL
    SELECT 'UBP', count(*) FROM analytics.mart_screener_data WHERE ubp_annual > 0 UNION ALL
    SELECT 'UPK', count(*) FROM analytics.mart_screener_data WHERE upk_annual > 0 UNION ALL
    SELECT 'IL AABD', count(*) FROM analytics.mart_screener_data WHERE il_aabd_annual > 0 UNION ALL
    SELECT 'IL ACA', count(*) FROM analytics.mart_screener_data WHERE il_aca_annual > 0 UNION ALL
    SELECT 'IL ACA Adults', count(*) FROM analytics.mart_screener_data WHERE il_aca_adults_annual > 0 UNION ALL
    SELECT 'IL All Kids', count(*) FROM analytics.mart_screener_data WHERE il_all_kids_annual > 0 UNION ALL
    SELECT 'IL BAP', count(*) FROM analytics.mart_screener_data WHERE il_bap_annual > 0 UNION ALL
    SELECT 'IL Family Care', count(*) FROM analytics.mart_screener_data WHERE il_family_care_annual > 0 UNION ALL
    SELECT 'IL LIHEAP', count(*) FROM analytics.mart_screener_data WHERE il_liheap_annual > 0 UNION ALL
    SELECT 'IL Moms and Babies', count(*) FROM analytics.mart_screener_data WHERE il_moms_and_babies_annual > 0 UNION ALL
    SELECT 'IL Transit Reduced Fare', count(*) FROM analytics.mart_screener_data WHERE il_transit_reduced_fare_annual > 0 UNION ALL
    SELECT 'CO BHEAP', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_bheap_annual > 0 UNION ALL
    SELECT 'CO BHGAP', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_bhgap_annual > 0 UNION ALL
    SELECT 'CO CARE', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_care_annual > 0 UNION ALL
    SELECT 'CO CNGBA', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_cngba_annual > 0 UNION ALL
    SELECT 'CO WAP (Energy)', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_cowap_annual > 0 UNION ALL
    SELECT 'CO CPCR (Energy)', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_cpcr_annual > 0 UNION ALL
    SELECT 'CO EA', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_ea_annual > 0 UNION ALL
    SELECT 'CO Energy EBT', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_energy_ebt_annual > 0 UNION ALL
    SELECT 'CO EOC', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_eoc_annual > 0 UNION ALL
    SELECT 'CO EOCCIP', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_eoccip_annual > 0 UNION ALL
    SELECT 'CO EOCS', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_eocs_annual > 0 UNION ALL
    SELECT 'CO LEAP (Energy)', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_leap_annual > 0 UNION ALL
    SELECT 'CO POIPP', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_poipp_annual > 0 UNION ALL
    SELECT 'CO UBP (Energy)', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_ubp_annual > 0 UNION ALL
    SELECT 'CO XCELEAP', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_xceleap_annual > 0 UNION ALL
    SELECT 'CO XCELGAP', count(*) FROM analytics.mart_screener_data WHERE co_energy_calculator_xcelgap_annual > 0
)
SELECT 
    benefit as "Benefit Name",
    count as "# of Screeners",
    count::float / NULLIF(t.total_count, 0) as "% of Screeners"
FROM qualified_benefits, totals t
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
