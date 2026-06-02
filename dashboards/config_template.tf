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

  # Hierarchy note rendered next to the summary metric cards.
  summary_metrics_note = "**Total Benefits** equals the sum of **Tax Benefits** and **Non-Tax Benefits**."

  # Per-tenant feature flags — controls which cards appear on shared dashboard tabs.
  # Add a new tenant here instead of scattering tenant-key conditionals across layout files.
  tenant_features = {
    nc                = { has_tax_credits = true, has_immediate_needs = true, has_assets = true, has_expenses = true, has_partners = true, has_summary_metrics = true, has_utm_filters = true }
    co                = { has_tax_credits = true, has_immediate_needs = true, has_assets = true, has_expenses = true, has_partners = true, has_summary_metrics = false, has_utm_filters = false }
    tx                = { has_tax_credits = true, has_immediate_needs = true, has_assets = true, has_expenses = true, has_partners = true, has_summary_metrics = false, has_utm_filters = false }
    il                = { has_tax_credits = true, has_immediate_needs = true, has_assets = true, has_expenses = true, has_partners = true, has_summary_metrics = false, has_utm_filters = false }
    ma                = { has_tax_credits = true, has_immediate_needs = true, has_assets = true, has_expenses = true, has_partners = true, has_summary_metrics = false, has_utm_filters = false }
    cesn              = { has_tax_credits = false, has_immediate_needs = false, has_assets = false, has_expenses = false, has_partners = false, has_summary_metrics = false, has_utm_filters = false }
    co_tax_calculator = { has_tax_credits = true, has_immediate_needs = true, has_assets = true, has_expenses = true, has_partners = true, has_summary_metrics = false, has_utm_filters = false }
  }

  # All available dashboard tabs with fixed IDs — per tenant so names can vary
  # IDs are foreign keys used by dashboard_tab_id in layout blocks — do not renumber
  all_tabs = {
    for k, v in var.tenants : k => {
      google_analytics           = { id = 1, name = "Google Analytics" }
      all_time                   = { id = 2, name = "Overall Performance" }
      households                 = { id = 4, name = "Households" }
      benefits_needs             = { id = 5, name = local.tenant_features[k].has_immediate_needs ? "Benefits & Immediate Needs" : "Benefits" }
      cesn_homeowners_vs_renters = { id = 6, name = "Homeowners vs Renters" }
    }
  }

  # Per-tenant tab selection — order determines tab display order
  tenant_tabs = {
    nc                = ["all_time", "households", "benefits_needs", "google_analytics"]
    co                = ["all_time", "households", "benefits_needs", "google_analytics"]
    tx                = ["all_time", "households", "benefits_needs", "google_analytics"]
    il                = ["all_time", "households", "benefits_needs", "google_analytics"]
    ma                = ["all_time", "households", "benefits_needs", "google_analytics"]
    cesn              = ["all_time", "households", "benefits_needs", "cesn_homeowners_vs_renters", "google_analytics"]
    co_tax_calculator = ["all_time", "households", "benefits_needs"]
  }

  # Helper: quick lookup — local.tenant_has_tab["co"]["households"] → true
  tenant_has_tab = {
    for key, tabs in local.tenant_tabs : key => {
      for tab_key in keys(local.all_tabs[key]) : tab_key => contains(tabs, tab_key)
    }
  }

  # Per-tenant template-tags for partner and date filter (dimension type enables multi-select)
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
      submission_date = {
        id             = "date_range_filter"
        name           = "submission_date"
        "display-name" = "Submission Date"
        type           = "dimension"
        dimension      = ["field", tonumber(data.metabase_table.tenant_screen_summary_tables[k].fields["submission_date"]), null]
        "widget-type"  = "date/all-options"
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

  # Per-tenant template-tags for UTM filters (defined for all tenants to avoid Metabase validation errors on shared SQL)
  utm_template_tags = {
    for k, v in var.tenants : k => {
      utm_campaign = {
        id             = "utm_campaign_filter"
        name           = "utm_campaign"
        "display-name" = "UTM Campaign"
        type           = "dimension"
        dimension      = ["field", tonumber(data.external.filter_field_ids.result["${k}__utm_campaign"]), null]
        "widget-type"  = "string/="
      }
      utm_medium = {
        id             = "utm_medium_filter"
        name           = "utm_medium"
        "display-name" = "UTM Medium"
        type           = "dimension"
        dimension      = ["field", tonumber(data.external.filter_field_ids.result["${k}__utm_medium"]), null]
        "widget-type"  = "string/="
      }
      utm_source = {
        id             = "utm_source_filter"
        name           = "utm_source"
        "display-name" = "UTM Source"
        type           = "dimension"
        dimension      = ["field", tonumber(data.external.filter_field_ids.result["${k}__utm_source"]), null]
        "widget-type"  = "string/="
      }
    }
  }

  # Merged template-tags: partner + county + UTM
  filter_template_tags = {
    for k, v in var.tenants : k => merge(
      local.partner_template_tags[k],
      local.county_template_tags[k],
      local.utm_template_tags[k],
    )
  }
}
