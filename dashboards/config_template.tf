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

  # Per-tenant template-tags for partner field filter (dimension type enables multi-select)
  partner_template_tags = {
    for k, v in var.tenants : k => {
      partner = {
        id             = "partner_filter"
        name           = "partner"
        "display-name" = "Partner"
        type           = "dimension"
        dimension      = ["field", tonumber(data.external.partner_field_ids.result[k]), null]
        "widget-type"  = "string/="
      }
    }
  }
}
