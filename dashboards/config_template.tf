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

  # Shared templates for tenant cards (reusable across all dashboard tabs)
  tenant_card_base_config = {
    description         = null
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      type = "native"
    }
    parameter_mappings     = []
    parameters             = []
    visualization_settings = {}
  }

  # Template for scalar scorecards (simple counts)
  tenant_scorecard_config = merge(local.tenant_card_base_config, {
    display = "scalar"
  })

  # Template for percentage cards
  tenant_percentage_card_config = merge(local.tenant_scorecard_config, {
    visualization_settings = {
      "column_settings" = {}
    }
  })

  # Template for table cards with mini bars (flexible)
  tenant_table_card_config = merge(local.tenant_card_base_config, {
    display = "table"
    visualization_settings = {
      "table.column_widths" = []
      "column_settings"     = {}
    }
  })

  # Reusable number and format presets
  number_format_percent_0 = {
    "number_style" = "percent"
    "decimals"     = 0
  }

  currency_format_0 = {
    "number_style"   = "currency"
    "currency"       = "USD"
    "currency_style" = "symbol"
    "decimals"       = 0
  }

  show_minibar_true = {
    "show_mini_bar" = true
  }

  # All available dashboard tabs with fixed IDs
  # IDs are foreign keys used by dashboard_tab_id in layout blocks — do not renumber
  all_tabs = {
    google_analytics = { id = 1, name = "Google Analytics" }
    all_time         = { id = 2, name = "All-Time Performance" }
    last_30_days     = { id = 3, name = "Last 30 Days Performance" }
    households       = { id = 4, name = "Households" }
    benefits_needs   = { id = 5, name = "Benefits & Immediate Needs" }
  }

  # Per-tenant tab selection — order determines tab display order
  tenant_tabs = {
    nc                = ["all_time", "last_30_days", "households", "benefits_needs", "google_analytics"]
    co                = ["all_time", "last_30_days", "households", "benefits_needs", "google_analytics"]
    tx                = ["all_time", "last_30_days", "households", "benefits_needs", "google_analytics"]
    il                = ["all_time", "last_30_days", "households", "benefits_needs", "google_analytics"]
    ma                = ["all_time", "last_30_days", "households", "benefits_needs", "google_analytics"]
    cesn              = ["all_time", "last_30_days", "households", "benefits_needs", "google_analytics"]
    co_tax_calculator = ["all_time", "last_30_days", "households", "benefits_needs"]
  }

  # Helper: quick lookup — local.tenant_has_tab["co"]["households"] → true
  tenant_has_tab = {
    for key, tabs in local.tenant_tabs : key => {
      for tab_key in keys(local.all_tabs) : tab_key => contains(tabs, tab_key)
    }
  }

  # Per-tenant template-tags for partner field filter (dimension type enables multi-select)
  partner_template_tags = {
    for k, v in var.tenants : k => {
      partner = {
        id             = "partner_filter"
        name           = "partner"
        "display-name" = "Partner"
        type           = "dimension"
        dimension      = ["field", tonumber(data.external.filter_field_ids.result["${k}__partner"]), null]
        "widget-type"  = "string/="
      }
    }
  }

  # Per-tenant template-tags for county field filter
  county_template_tags = {
    for k, v in var.tenants : k => {
      county = {
        id             = "county_filter"
        name           = "county"
        "display-name" = "County"
        type           = "dimension"
        dimension      = ["field", tonumber(data.external.filter_field_ids.result["${k}__county"]), null]
        "widget-type"  = "string/="
      }
    }
  }

  # Merged template-tags: partner + county (used by all cards that support both filters)
  filter_template_tags = {
    for k, v in var.tenants : k => merge(
      local.partner_template_tags[k],
      local.county_template_tags[k],
    )
  }
}
