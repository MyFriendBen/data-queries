# =============================================================================
# CU Denver referrer dashboard
# =============================================================================
# CU Denver is the `cudenver` referrer inside the CO white label — NOT a tenant.
# These cards query the CO tenant connection (so white-label RLS limits rows to
# CO) and additionally hard-code `referrer_code = 'cudenver'`, giving two-layer
# scoping. The filter is baked into each query (no editable parameter), and the
# CU Denver viewer group has collection-read only + no ad-hoc DB query access
# (see permissions.tf), so viewers cannot broaden the scope.
#
# Aggregate / de-identified only — no PII. Scope: completed screeners only
# (excludes started-but-incomplete) and no cross-partner/global comparison.

locals {
  cudenver_db_id  = tonumber(metabase_database.tenant_postgres["co"].id)
  cudenver_col_id = tonumber(metabase_collection.cu_denver.id)

  # Referrer-locked variants of the shared table SQLs: strip the optional
  # [[...]] clauses (as the global cards do) then inject the referrer predicate
  # onto every "WHERE 1 = 1" anchor (the filtered_screens CTE and the
  # denominator subquery both need it for correct percentages).
  cudenver_qualified_benefits_sql = replace(
    replace(templatefile("${path.module}/sql/qualified_benefits.sql", {}), local._optional_clause_regex, ""),
    "WHERE 1 = 1",
    "WHERE 1 = 1 AND referrer_code = 'cudenver'"
  )
  cudenver_immediate_needs_sql = replace(
    replace(templatefile("${path.module}/sql/immediate_needs.sql", {}), local._optional_clause_regex, ""),
    "WHERE 1 = 1",
    "WHERE 1 = 1 AND referrer_code = 'cudenver'"
  )
}

# -----------------------------------------------------------------------------
# Totals scorecards
# -----------------------------------------------------------------------------

resource "metabase_card" "cudenver_completed_screeners" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Completed Screeners"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT count(*) AS \"Completed Screeners\" FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver'"
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "cudenver_total_annual_benefits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Total Annual Benefits Surfaced"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT COALESCE(SUM(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS total FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver'"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cudenver_median_annual_benefits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Annual Benefits / Household"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual + tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver' AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cudenver_median_monthly_benefits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Monthly Benefits / Household"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (non_tax_credit_benefits_annual + tax_credits_annual) / 12.0) AS median FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver' AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cudenver_avg_programs_matched" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Avg # Programs Matched"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT ROUND(AVG(programs_matched)::numeric, 1) AS avg_programs FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver'"
      }
    }
    visualization_settings = { "scalar.field" = "avg_programs" }
  }))
}

# -----------------------------------------------------------------------------
# Students breakout scorecards (any household member is a student)
# -----------------------------------------------------------------------------

resource "metabase_card" "cudenver_student_completed_screeners" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Students: Completed Screeners"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT count(*) AS \"Completed Screeners\" FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver' AND has_student = TRUE"
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "cudenver_student_total_annual_benefits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Students: Total Annual Benefits Surfaced"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT COALESCE(SUM(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS total FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver' AND has_student = TRUE"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cudenver_student_median_annual_benefits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Students: Median Annual Benefits / Household"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual + tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver' AND has_student = TRUE AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cudenver_student_avg_programs_matched" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Students: Avg # Programs Matched"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT ROUND(AVG(programs_matched)::numeric, 1) AS avg_programs FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver' AND has_student = TRUE"
      }
    }
    visualization_settings = { "scalar.field" = "avg_programs" }
  }))
}

# -----------------------------------------------------------------------------
# Monthly trend
# -----------------------------------------------------------------------------

resource "metabase_card" "cudenver_monthly_screeners" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "Completed Screeners by Month"
    collection_id = local.cudenver_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = "SELECT DATE_TRUNC('month', submission_date)::date AS month, count(*) AS screeners FROM analytics.mart_screener_data WHERE referrer_code = 'cudenver' GROUP BY 1 ORDER BY 1"
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

# -----------------------------------------------------------------------------
# Tables: most common benefits matched + immediate needs
# -----------------------------------------------------------------------------

resource "metabase_card" "cudenver_qualified_benefits_table" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What benefits did people qualify for?"
    description   = "Most common benefits matched for CU Denver completed screeners."
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = local.cudenver_qualified_benefits_sql
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

resource "metabase_card" "cudenver_immediate_needs_table" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What immediate needs did people flag?"
    collection_id = local.cudenver_col_id
    dataset_query = {
      type     = "native"
      database = local.cudenver_db_id
      native = {
        query = local.cudenver_immediate_needs_sql
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "table.column_widths" = [
        { "name" = "Need Category", "width" = 300 },
        { "name" = "# of Screeners", "width" = 120 },
        { "name" = "% of Screeners", "width" = 120 },
      ]
      "column_settings" = local.benefits_column_settings
    })
  }))
}

# -----------------------------------------------------------------------------
# Dashboard
# -----------------------------------------------------------------------------

resource "metabase_dashboard" "cu_denver" {
  name                = "CU Denver Screener Impact"
  description         = "Aggregate impact of the MyFriendBen screener reached via the CU Denver link (referrer=cudenver). Completed screeners only; no personal data."
  collection_id       = local.cudenver_col_id
  collection_position = 1

  tabs_json = jsonencode([
    { id = 1, name = "Overview" },
  ])

  cards_json = jsonencode([
    # Row 0 — totals scorecards
    { card_id = tonumber(metabase_card.cudenver_completed_screeners.id), dashboard_tab_id = 1, row = 0, col = 0, size_x = 5, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cudenver_total_annual_benefits.id), dashboard_tab_id = 1, row = 0, col = 5, size_x = 5, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cudenver_median_annual_benefits.id), dashboard_tab_id = 1, row = 0, col = 10, size_x = 5, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cudenver_median_monthly_benefits.id), dashboard_tab_id = 1, row = 0, col = 15, size_x = 5, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cudenver_avg_programs_matched.id), dashboard_tab_id = 1, row = 0, col = 20, size_x = 4, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 4 — students breakout scorecards
    { card_id = tonumber(metabase_card.cudenver_student_completed_screeners.id), dashboard_tab_id = 1, row = 4, col = 0, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cudenver_student_total_annual_benefits.id), dashboard_tab_id = 1, row = 4, col = 6, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cudenver_student_median_annual_benefits.id), dashboard_tab_id = 1, row = 4, col = 12, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cudenver_student_avg_programs_matched.id), dashboard_tab_id = 1, row = 4, col = 18, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 8 — monthly trend (full width)
    { card_id = tonumber(metabase_card.cudenver_monthly_screeners.id), dashboard_tab_id = 1, row = 8, col = 0, size_x = 24, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 14 — tables side by side
    { card_id = tonumber(metabase_card.cudenver_qualified_benefits_table.id), dashboard_tab_id = 1, row = 14, col = 0, size_x = 12, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cudenver_immediate_needs_table.id), dashboard_tab_id = 1, row = 14, col = 12, size_x = 12, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },
  ])
}
