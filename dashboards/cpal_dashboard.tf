# =============================================================================
# CPAL (Child Poverty Action Lab) dashboard — MFB-1198
# =============================================================================
# CPAL is a partner (referrer) inside the TX white label — NOT a tenant. Same
# pattern as cu_denver_dashboard.tf: cards query the TX tenant connection (so
# white-label RLS limits rows to TX) and additionally hard-code the CPAL
# referrer predicate, giving two-layer scoping. Filters are baked into each
# query (no editable parameters), and the CPAL viewer group has
# collection-read only + no ad-hoc DB query access (see permissions.tf), so
# viewers cannot broaden the scope.
#
# Layout maps 1:1 to CPAL's four requests (see MFB-1198):
#   1. Quick raw totals        → Overview tab, row 0 scorecards
#   2. High/low benefits access → Overview tab, row 4 scorecards
#   3. Contact data export      → "Contact Export" tab (PII — see note below)
#   4. Partner toggling         → the CPAL collection + "CPAL Viewers" group
#      (partner sees exactly their own scoped dashboard after login)
#
# PII NOTE: unlike other referrer dashboards, the Contact Export tab surfaces
# names/emails/phones from analytics.mart_contact_info (consenting users
# only). Keep "CPAL Viewers" membership limited to approved CPAL staff.

locals {
  cpal_db_id  = tonumber(metabase_database.tenant_postgres["tx"].id)
  cpal_col_id = tonumber(metabase_collection.cpal.id)

  # Confirmed against production programs_referrer (2026-08-11): the TX white
  # label (id 40) has referrer_code 'cpal' → "Child Poverty Action Lab (CPAL)",
  # is_partner = true. As CPAL outreach efforts get their own unique URLs
  # (per MFB-1198), add each new referrer_code to this list.
  cpal_referrer_codes = ["cpal"]

  cpal_referrer_predicate = format(
    "referrer_code IN (%s)",
    join(", ", [for c in local.cpal_referrer_codes : format("'%s'", c)])
  )

  # Referrer-locked variant of the shared qualified-benefits table SQL: strip
  # the optional [[...]] filter clauses, then inject the CPAL predicate onto
  # every "WHERE 1 = 1" anchor (CTE + denominator subquery).
  cpal_qualified_benefits_sql = replace(
    replace(templatefile("${path.module}/sql/qualified_benefits.sql", {}), local._optional_clause_regex, ""),
    "WHERE 1 = 1",
    "WHERE 1 = 1 AND ${local.cpal_referrer_predicate}"
  )
}

# -----------------------------------------------------------------------------
# Request 1 — quick raw totals ("X respondents, Y benefits dollars, Z tax credits")
# -----------------------------------------------------------------------------

resource "metabase_card" "cpal_completed_screeners" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Respondents (Completed Screeners)"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT count(*) AS \"Respondents\" FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate}"
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "cpal_total_benefits_dollars" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Total Annual Benefits $ Identified"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(SUM(non_tax_credit_benefits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_total_tax_credits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Total Potential Tax Credits $"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(SUM(tax_credits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_total_combined" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Total Annual Value Identified (Benefits + Tax Credits)"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(SUM(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

# -----------------------------------------------------------------------------
# Request 2 — high / low benefits access per household
# -----------------------------------------------------------------------------

resource "metabase_card" "cpal_highest_household_value" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Highest Annual Value / Household"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(MAX(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS highest FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "highest"
      "column_settings" = { "[\"name\",\"highest\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_lowest_household_value" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Lowest Annual Value / Household (of those matched)"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(MIN(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS lowest FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate} AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "lowest"
      "column_settings" = { "[\"name\",\"lowest\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_median_household_value" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Annual Value / Household"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual + tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate} AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_value_distribution" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "Annual Value per Household — Distribution"
    description   = "How much annual benefit value each CPAL household could access, bucketed."
    collection_id = local.cpal_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "WITH vals AS (SELECT non_tax_credit_benefits_annual + tax_credits_annual AS v FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate}) SELECT CASE WHEN v = 0 THEN '$0' WHEN v < 5000 THEN '$1-$4,999' WHEN v < 10000 THEN '$5,000-$9,999' WHEN v < 20000 THEN '$10,000-$19,999' WHEN v < 40000 THEN '$20,000-$39,999' ELSE '$40,000+' END AS bucket, count(*) AS households FROM vals GROUP BY 1 ORDER BY MIN(CASE WHEN v = 0 THEN 0 WHEN v < 5000 THEN 1 WHEN v < 10000 THEN 2 WHEN v < 20000 THEN 3 WHEN v < 40000 THEN 4 ELSE 5 END)"
      }
    }
    visualization_settings = {
      "graph.dimensions"        = ["BUCKET"]
      "graph.metrics"           = ["HOUSEHOLDS"]
      "graph.x_axis.title_text" = "Annual Value Identified"
      "graph.y_axis.title_text" = "Households"
      "graph.show_values"       = true
    }
  }))
}

# -----------------------------------------------------------------------------
# Trend + program mix
# -----------------------------------------------------------------------------

resource "metabase_card" "cpal_monthly_screeners" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "Completed Screeners by Month"
    collection_id = local.cpal_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT DATE_TRUNC('month', submission_date)::date AS month, count(*) AS screeners FROM analytics.mart_screener_data WHERE ${local.cpal_referrer_predicate} GROUP BY 1 ORDER BY 1"
      }
    }
    visualization_settings = {
      "graph.dimensions"        = ["MONTH"]
      "graph.metrics"           = ["SCREENERS"]
      "graph.x_axis.title_text" = "Month"
      "graph.y_axis.title_text" = "Completed Screeners"
      "graph.show_values"       = true
    }
  }))
}

resource "metabase_card" "cpal_qualified_benefits_table" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What benefits did people qualify for?"
    description   = "Most common benefits matched for CPAL completed screeners."
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = local.cpal_qualified_benefits_sql
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "table.column_widths" = [
        { "name" = "Benefit Name", "width" = 300 },
        { "name" = "# of Screeners", "width" = 120 },
        { "name" = "% of Screeners", "width" = 120 },
      ]
      "column_settings" = local.benefits_column_settings
    })
  }))
}

# -----------------------------------------------------------------------------
# Request 3 — contact data export (PII — consenting users only)
# -----------------------------------------------------------------------------

resource "metabase_card" "cpal_contact_export" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "Contact Info Export — Consenting Respondents"
    description   = "Respondents who opted in to follow-up contact, newest first. Use the download button to export. Contains PII — handle per data-sharing agreement."
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT first_name AS \"First Name\", last_name AS \"Last Name\", email AS \"Email\", phone AS \"Phone\", preferred_language AS \"Preferred Language\", county AS \"County\", referrer_code AS \"Referrer Code\", submission_timestamp AS \"Completed At\" FROM analytics.mart_contact_info WHERE ${local.cpal_referrer_predicate} ORDER BY submission_timestamp DESC"
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "table.column_widths" = [
        { "name" = "First Name", "width" = 120 },
        { "name" = "Last Name", "width" = 120 },
        { "name" = "Email", "width" = 220 },
        { "name" = "Phone", "width" = 140 },
        { "name" = "Preferred Language", "width" = 140 },
        { "name" = "County", "width" = 140 },
        { "name" = "Referrer Code", "width" = 120 },
        { "name" = "Completed At", "width" = 160 },
      ]
    })
  }))
}

# -----------------------------------------------------------------------------
# Dashboard
# -----------------------------------------------------------------------------

resource "metabase_dashboard" "cpal" {
  name                = "CPAL Screener Impact"
  description         = "Impact of the MyFriendBen screener for CPAL (Child Poverty Action Lab) partner traffic in Texas. Overview tab is aggregate; Contact Export tab lists consenting respondents only."
  collection_id       = local.cpal_col_id
  collection_position = 1

  tabs_json = jsonencode([
    { id = 1, name = "Overview" },
    { id = 2, name = "Contact Export" },
  ])

  cards_json = jsonencode([
    # --- Tab 1: Overview -----------------------------------------------------
    # Row 0 — raw totals scorecards (Request 1)
    { card_id = tonumber(metabase_card.cpal_completed_screeners.id), dashboard_tab_id = 1, row = 0, col = 0, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_benefits_dollars.id), dashboard_tab_id = 1, row = 0, col = 6, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_tax_credits.id), dashboard_tab_id = 1, row = 0, col = 12, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_combined.id), dashboard_tab_id = 1, row = 0, col = 18, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 4 — high/low/median scorecards (Request 2)
    { card_id = tonumber(metabase_card.cpal_highest_household_value.id), dashboard_tab_id = 1, row = 4, col = 0, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_median_household_value.id), dashboard_tab_id = 1, row = 4, col = 8, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_lowest_household_value.id), dashboard_tab_id = 1, row = 4, col = 16, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 8 — value distribution (Request 2, context)
    { card_id = tonumber(metabase_card.cpal_value_distribution.id), dashboard_tab_id = 1, row = 8, col = 0, size_x = 12, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },
    # Row 8 — monthly trend
    { card_id = tonumber(metabase_card.cpal_monthly_screeners.id), dashboard_tab_id = 1, row = 8, col = 12, size_x = 12, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 14 — program mix table
    { card_id = tonumber(metabase_card.cpal_qualified_benefits_table.id), dashboard_tab_id = 1, row = 14, col = 0, size_x = 24, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },

    # --- Tab 2: Contact Export (Request 3) -----------------------------------
    { card_id = tonumber(metabase_card.cpal_contact_export.id), dashboard_tab_id = 2, row = 0, col = 0, size_x = 24, size_y = 12, parameter_mappings = [], series = [], visualization_settings = {} },
  ])
}
