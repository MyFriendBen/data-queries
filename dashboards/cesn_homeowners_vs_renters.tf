# CESN-only tab: Homeowners vs Renters (Tab 6)
# All cards use for_each = var.tenants to keep Terraform happy, but are only
# placed on the dashboard for the "cesn" tenant (see metabase.tf cards_json).

locals {
  # Reusable bar chart settings for yes/no boolean questions
  cesn_boolean_bar_settings = {
    "graph.dimensions"  = ["Answer"]
    "graph.metrics"     = ["# of Screeners"]
    "graph.show_values" = true
    "series_settings" = {
      "# of Screeners" = { color = "#509EE3" }
    }
  }

  # Reusable bar chart settings for provider breakdowns
  cesn_provider_bar_settings = {
    "graph.dimensions"  = ["Provider"]
    "graph.metrics"     = ["# of Screeners"]
    "graph.show_values" = true
    "series_settings" = {
      "# of Screeners" = { color = "#509EE3" }
    }
  }
}

# --- Scorecards ---

resource "metabase_card" "cesn_homeowners_completed" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Homeowners – Completed Screeners"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) AS count FROM analytics.mart_screener_data WHERE is_home_owner = true [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "cesn_homeowners_qualified_pct" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_percentage_card_config, {
    name          = "Homeowners – Qualified for Benefits *"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) AS pct FROM analytics.mart_screener_data WHERE is_home_owner = true [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

resource "metabase_card" "cesn_renters_completed" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_scorecard_config, {
    name          = "Renters – Completed Screeners"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) AS count FROM analytics.mart_screener_data WHERE is_renter = true [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "cesn_renters_qualified_pct" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_percentage_card_config, {
    name          = "Renters – Qualified for Benefits *"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) AS pct FROM analytics.mart_screener_data WHERE is_renter = true [[AND {{partner}}]] [[AND {{county}}]]"
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.benefits_pct_visualization_settings
  }))
}

# --- Daily screeners bar charts ---

resource "metabase_card" "cesn_homeowners_daily_screeners" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Daily Screeners (Past Week)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT submission_date, count(*) AS "Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND submission_date >= current_date - interval '7 days'
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY submission_date ORDER BY submission_date
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "graph.dimensions"        = ["SUBMISSION_DATE"]
      "graph.metrics"           = ["Screeners"]
      "graph.x_axis.title_text" = "Date"
      "graph.y_axis.title_text" = "Screeners Completed"
      "graph.show_values"       = true
    }
  }))
}

resource "metabase_card" "cesn_renters_daily_screeners" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Renters – Daily Screeners (Past Week)"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT submission_date, count(*) AS "Screeners"
            FROM analytics.mart_screener_data
            WHERE is_renter = true
              AND submission_date >= current_date - interval '7 days'
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY submission_date ORDER BY submission_date
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = {
      "graph.dimensions"        = ["SUBMISSION_DATE"]
      "graph.metrics"           = ["Screeners"]
      "graph.x_axis.title_text" = "Date"
      "graph.y_axis.title_text" = "Screeners Completed"
      "graph.show_values"       = true
    }
  }))
}

# --- Electricity provider ---

resource "metabase_card" "cesn_homeowners_electric_provider" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Who is your electricity provider?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              COALESCE(electric_provider_name, electric_provider, '(Unknown)') AS "Provider",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND electric_provider IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 2 DESC
            LIMIT 20
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_provider_bar_settings
  }))
}

resource "metabase_card" "cesn_renters_electric_provider" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Renters – Who is your electricity provider?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              COALESCE(electric_provider_name, electric_provider, '(Unknown)') AS "Provider",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_renter = true
              AND electric_provider IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 2 DESC
            LIMIT 20
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_provider_bar_settings
  }))
}

# --- Gas/heating provider ---

resource "metabase_card" "cesn_homeowners_gas_provider" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Who is your gas/heating provider?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              COALESCE(gas_heat_provider_name, gas_heat_provider, '(Unknown)') AS "Provider",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND gas_heat_provider IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 2 DESC
            LIMIT 20
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_provider_bar_settings
  }))
}

resource "metabase_card" "cesn_renters_gas_provider" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Renters – Who is your gas/heating provider?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              COALESCE(gas_heat_provider_name, gas_heat_provider, '(Unknown)') AS "Provider",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_renter = true
              AND gas_heat_provider IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 2 DESC
            LIMIT 20
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_provider_bar_settings
  }))
}

# --- Electricity/gas/heating disconnected ---

resource "metabase_card" "cesn_homeowners_disconnected" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Is your electricity, gas, or heating currently disconnected?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN electricity_is_disconnected THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND electricity_is_disconnected IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

resource "metabase_card" "cesn_renters_disconnected" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Renters – Is your electricity, gas, or heating currently disconnected?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN electricity_is_disconnected THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_renter = true
              AND electricity_is_disconnected IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

# --- Past due energy bills ---

resource "metabase_card" "cesn_homeowners_past_due" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Do you have past due electricity, gas, or heating bills?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN has_past_due_energy_bills THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND has_past_due_energy_bills IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

resource "metabase_card" "cesn_renters_past_due" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Renters – Do you have past due electricity, gas, or heating bills?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN has_past_due_energy_bills THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_renter = true
              AND has_past_due_energy_bills IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

# --- Old vehicle (12+ years or failed emissions) ---

resource "metabase_card" "cesn_homeowners_old_car" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Do you have a vehicle 12+ years old or has failed an emissions test?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN has_old_car THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND has_old_car IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

resource "metabase_card" "cesn_renters_old_car" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Renters – Do you have a vehicle 12+ years old or has failed an emissions test?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN has_old_car THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_renter = true
              AND has_old_car IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

# --- Appliance needs (homeowners only per PDF) ---

resource "metabase_card" "cesn_needs_stove" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Do you have a stove/range that is in need of repair or replacement?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN needs_stove THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND needs_stove IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

resource "metabase_card" "cesn_needs_water_heater" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Do you have a water heater that is in need of repair or replacement?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN needs_water_heater THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND needs_water_heater IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

resource "metabase_card" "cesn_needs_hvac" {
  for_each = var.tenants
  json = jsonencode(merge(local.tenant_card_base_config, {
    name          = "Homeowners – Do you have heating/cooling/ventilation that is in need of repair or replacement?"
    collection_id = tonumber(local.tenant_collection_map[each.key].id)
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.tenant_postgres[each.key].id)
      native = {
        query           = <<-SQL
            SELECT
              CASE WHEN needs_hvac THEN 'Yes' ELSE 'No' END AS "Answer",
              count(*) AS "# of Screeners"
            FROM analytics.mart_screener_data
            WHERE is_home_owner = true
              AND needs_hvac IS NOT NULL
              [[AND {{partner}}]]
              [[AND {{county}}]]
            GROUP BY 1
            ORDER BY 1
          SQL
        "template-tags" = local.filter_template_tags[each.key]
      }
    }
    visualization_settings = local.cesn_boolean_bar_settings
  }))
}

# --- Dashboard layout ---
# Two-column layout: Homeowners (col 0–11) | Renters (col 12–23)
# Appliance questions are homeowners-only (col 0, size 12)

locals {
  tenant_dashboard_cesn_hvr_layout = [
    # Row 0: text header
    {
      card_id            = null
      dashboard_tab_id   = 6
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
        text = "## Homeowners vs Renters\n* Non-Tax Credit benefits"
      }
    },
    # Row 2: scorecards — homeowners
    {
      card_id          = tonumber(metabase_card.cesn_homeowners_completed["cesn"].id)
      dashboard_tab_id = 6
      row              = 2
      col              = 0
      size_x           = 6
      size_y           = 4
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_homeowners_completed["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_homeowners_completed["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_homeowners_qualified_pct["cesn"].id)
      dashboard_tab_id = 6
      row              = 2
      col              = 6
      size_x           = 6
      size_y           = 4
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_homeowners_qualified_pct["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_homeowners_qualified_pct["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    # Row 2: scorecards — renters
    {
      card_id          = tonumber(metabase_card.cesn_renters_completed["cesn"].id)
      dashboard_tab_id = 6
      row              = 2
      col              = 12
      size_x           = 6
      size_y           = 4
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_renters_completed["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_renters_completed["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_renters_qualified_pct["cesn"].id)
      dashboard_tab_id = 6
      row              = 2
      col              = 18
      size_x           = 6
      size_y           = 4
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_renters_qualified_pct["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_renters_qualified_pct["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    # Row 6: daily screeners bar charts
    {
      card_id          = tonumber(metabase_card.cesn_homeowners_daily_screeners["cesn"].id)
      dashboard_tab_id = 6
      row              = 6
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_homeowners_daily_screeners["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_homeowners_daily_screeners["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_renters_daily_screeners["cesn"].id)
      dashboard_tab_id = 6
      row              = 6
      col              = 12
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_renters_daily_screeners["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_renters_daily_screeners["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    # Row 12: electricity provider
    {
      card_id          = tonumber(metabase_card.cesn_homeowners_electric_provider["cesn"].id)
      dashboard_tab_id = 6
      row              = 12
      col              = 0
      size_x           = 12
      size_y           = 8
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_homeowners_electric_provider["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_homeowners_electric_provider["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_renters_electric_provider["cesn"].id)
      dashboard_tab_id = 6
      row              = 12
      col              = 12
      size_x           = 12
      size_y           = 8
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_renters_electric_provider["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_renters_electric_provider["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    # Row 20: gas/heating provider
    {
      card_id          = tonumber(metabase_card.cesn_homeowners_gas_provider["cesn"].id)
      dashboard_tab_id = 6
      row              = 20
      col              = 0
      size_x           = 12
      size_y           = 8
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_homeowners_gas_provider["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_homeowners_gas_provider["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_renters_gas_provider["cesn"].id)
      dashboard_tab_id = 6
      row              = 20
      col              = 12
      size_x           = 12
      size_y           = 8
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_renters_gas_provider["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_renters_gas_provider["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    # Row 28: disconnected
    {
      card_id          = tonumber(metabase_card.cesn_homeowners_disconnected["cesn"].id)
      dashboard_tab_id = 6
      row              = 28
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_homeowners_disconnected["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_homeowners_disconnected["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_renters_disconnected["cesn"].id)
      dashboard_tab_id = 6
      row              = 28
      col              = 12
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_renters_disconnected["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_renters_disconnected["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    # Row 34: past due bills
    {
      card_id          = tonumber(metabase_card.cesn_homeowners_past_due["cesn"].id)
      dashboard_tab_id = 6
      row              = 34
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_homeowners_past_due["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_homeowners_past_due["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_renters_past_due["cesn"].id)
      dashboard_tab_id = 6
      row              = 34
      col              = 12
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_renters_past_due["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_renters_past_due["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    # Row 40: old vehicle (both sides)
    {
      card_id          = tonumber(metabase_card.cesn_homeowners_old_car["cesn"].id)
      dashboard_tab_id = 6
      row              = 40
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_homeowners_old_car["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_homeowners_old_car["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_renters_old_car["cesn"].id)
      dashboard_tab_id = 6
      row              = 40
      col              = 12
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_renters_old_car["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_renters_old_car["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    # Row 46: appliance needs — homeowners only (col 0, size 12)
    {
      card_id          = tonumber(metabase_card.cesn_needs_stove["cesn"].id)
      dashboard_tab_id = 6
      row              = 46
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_needs_stove["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_needs_stove["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_needs_water_heater["cesn"].id)
      dashboard_tab_id = 6
      row              = 52
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_needs_water_heater["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_needs_water_heater["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
    {
      card_id          = tonumber(metabase_card.cesn_needs_hvac["cesn"].id)
      dashboard_tab_id = 6
      row              = 58
      col              = 0
      size_x           = 12
      size_y           = 6
      parameter_mappings = [
        { parameter_id = "partner_filter", card_id = tonumber(metabase_card.cesn_needs_hvac["cesn"].id), target = ["dimension", ["template-tag", "partner"]] },
        { parameter_id = "county_filter", card_id = tonumber(metabase_card.cesn_needs_hvac["cesn"].id), target = ["dimension", ["template-tag", "county"]] }
      ]
      series                 = []
      visualization_settings = {}
    },
  ]
}
