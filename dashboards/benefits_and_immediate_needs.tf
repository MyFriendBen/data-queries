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
    visualization_settings = local.tenant_benefits_table_card_config.visualization_settings
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
    visualization_settings = local.tenant_benefits_table_card_config.visualization_settings
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
    visualization_settings = local.tenant_benefits_table_card_config.visualization_settings
  }))
}

locals {
  # 1. Specialized column settings (the "style" for the tables)
  benefits_column_settings = {
    "[\"name\",\"# of Screeners\"]" = local.show_minibar_true
    "[\"name\",\"% of Screeners\"]" = merge(
      local.show_minibar_true,
      local.number_format_percent_0
    )
  }

  # 2. Reusable template for the tables themselves
  tenant_benefits_table_card_config = merge(local.tenant_table_card_config, {
    visualization_settings = merge(local.tenant_table_card_config.visualization_settings, {
      "table.row_index" = true
      "column_settings" = local.benefits_column_settings
    })
  })

  # 3. Reusable template for the percentage scorecards
  benefits_pct_visualization_settings = {
    "scalar.field" = "pct"
    "column_settings" = {
      "[\"name\",\"pct\"]" = local.number_format_percent_0
    }
  }

  # Scorecard counts per tenant for the Benefits & Immediate Needs top row:
  # with tax credits: Completed Screeners, Already Had Benefits, Qualified for Benefits, Qualified for Tax Credits = 4
  # without tax credits: first 3 only
  benefits_scorecard_count = { for k, v in var.tenants : k => local.tenant_features[k].has_tax_credits ? 4 : 3 }
  benefits_scorecard_width = { for k, v in var.tenants : k => 24 / local.benefits_scorecard_count[k] }

  tenant_dashboard_benefits_needs_layout = {
    for k, v in var.tenants : k => flatten(concat(
      [{
        card_id          = tonumber(metabase_card.tenant_completed_screeners[k].id)
        dashboard_tab_id = 5
        row              = 0
        col              = 0
        size_x           = local.benefits_scorecard_width[k]
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
      }],
      [{
        card_id          = tonumber(metabase_card.tenant_already_had_benefits_pct[k].id)
        dashboard_tab_id = 5
        row              = 0
        col              = local.benefits_scorecard_width[k] * 1
        size_x           = local.benefits_scorecard_width[k]
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
      }],
      [{
        card_id          = tonumber(metabase_card.tenant_qualified_for_benefits_pct[k].id)
        dashboard_tab_id = 5
        row              = 0
        col              = local.benefits_scorecard_width[k] * 2
        size_x           = local.benefits_scorecard_width[k]
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
      }],
      local.tenant_features[k].has_tax_credits ? [{
        card_id          = tonumber(metabase_card.tenant_qualified_for_tax_creds_pct[k].id)
        dashboard_tab_id = 5
        row              = 0
        col              = local.benefits_scorecard_width[k] * 3
        size_x           = local.benefits_scorecard_width[k]
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
      }] : [],
      [{
        card_id          = tonumber(metabase_card.tenant_current_benefits_table[k].id)
        dashboard_tab_id = 5
        row              = 4
        col              = 0
        size_x           = 12
        size_y           = 10
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
      }],
      [{
        card_id          = tonumber(metabase_card.tenant_qualified_benefits_table[k].id)
        dashboard_tab_id = 5
        row              = 4
        col              = 12
        size_x           = 12
        size_y           = 10
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
      }],
      local.tenant_features[k].has_immediate_needs ? [{
        card_id          = tonumber(metabase_card.tenant_immediate_needs_table[k].id)
        dashboard_tab_id = 5
        row              = 12
        col              = 0
        size_x           = 12
        size_y           = 10
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
      }] : []
    ))
  }
}
