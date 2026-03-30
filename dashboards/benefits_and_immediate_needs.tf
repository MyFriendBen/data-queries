# Tenant-specific scorecard metrics for "Benefits & Immediate Needs"
resource "metabase_card" "tenant_completed_screeners" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Completed Screeners"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) AS \"Completed Screeners\" FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "tenant_already_had_benefits_pct" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_percentage_card_config, {
    name          = "Already Had Benefits"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) FILTER (WHERE has_benefits = 'true')::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "tenant_qualified_for_benefits_pct" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_percentage_card_config, {
    name          = "Qualified for Benefits *"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "tenant_qualified_for_tax_creds_pct" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_percentage_card_config, {
    name          = "Qualified for Tax Credits *"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) FILTER (WHERE tax_credits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE 1=1 [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}


# Table: What percentage of users said they already had certain benefits?
resource "metabase_card" "tenant_current_benefits_table" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "What percentage of users said they already had certain benefits?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/current_benefits.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "table.column_widths" = [{ "name" = "Benefit Name", "width" = 300 }]
      "column_settings"     = local.benefits_column_settings
    })
  }))
}

# Table: What percentage of completed screeners qualified for benefits?
resource "metabase_card" "tenant_qualified_benefits_table" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "What percentage of completed screeners qualified for benefits?"
    description   = "Aggregated benefit eligibility data. RLS automatically filters to tenant white_label."
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/qualified_benefits.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "table.column_widths" = [{ "name" = "Benefit Name", "width" = 300 }]
      "column_settings"     = local.benefits_column_settings
    })
  }))
}

# Table: What percentage of users sought each immediate need?
resource "metabase_card" "tenant_immediate_needs_table" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_table_card_config, {
    name          = "What percentage of users sought each immediate need?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = templatefile("${path.module}/sql/immediate_needs.sql", {})
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "table.column_widths" = [{ "name" = "Need Category", "width" = 300 }]
      "column_settings"     = local.benefits_column_settings
    })
  }))
}

locals {
  # Shared column settings for benefits/needs table cards
  benefits_column_settings = {
    "[\"name\",\"# of Screeners\"]" = local.show_minibar_true
    "[\"name\",\"% of Screeners\"]" = merge(
      local.show_minibar_true,
      local.number_format_percent_0
    )
  }

  # Shared visualization settings for percentage scorecard cards
  benefits_pct_visualization_settings = {
    "scalar.field" = "pct"
    "column_settings" = {
      "[\"name\",\"pct\"]" = local.number_format_percent_0
    }
  }

  tenant_dashboard_benefits_needs_layout = {
    for k, v in var.tenants : k => [
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
      {
        card_id          = tonumber(metabase_card.tenant_completed_screeners[k].id)
        dashboard_tab_id = 5
        row              = 2
        col              = 0
        size_x           = 6
        size_y           = 4
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_completed_screeners[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_completed_screeners[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_already_had_benefits_pct[k].id)
        dashboard_tab_id = 5
        row              = 2
        col              = 6
        size_x           = 6
        size_y           = 4
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_already_had_benefits_pct[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_already_had_benefits_pct[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_qualified_for_benefits_pct[k].id)
        dashboard_tab_id = 5
        row              = 2
        col              = 12
        size_x           = 6
        size_y           = 4
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_qualified_for_benefits_pct[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_qualified_for_benefits_pct[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[k].id)
        dashboard_tab_id = 5
        row              = 2
        col              = 18
        size_x           = 6
        size_y           = 4
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_current_benefits_table[k].id)
        dashboard_tab_id = 5
        row              = 6
        col              = 0
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_current_benefits_table[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_current_benefits_table[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_qualified_benefits_table[k].id)
        dashboard_tab_id = 5
        row              = 6
        col              = 12
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_qualified_benefits_table[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_qualified_benefits_table[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.tenant_immediate_needs_table[k].id)
        dashboard_tab_id = 5
        row              = 14
        col              = 0
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = "partner_filter"
            card_id      = tonumber(metabase_card.tenant_immediate_needs_table[k].id)
            target       = ["dimension", ["template-tag", "partner"]]
          },
          {
            parameter_id = "county_filter"
            card_id      = tonumber(metabase_card.tenant_immediate_needs_table[k].id)
            target       = ["dimension", ["template-tag", "county"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      }
    ]
  }
}
