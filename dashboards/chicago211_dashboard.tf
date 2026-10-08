# =============================================================================
# 211 Metro Chicago dashboard — MFB-1884
# =============================================================================
# 211 Metro Chicago is the `211chicago` referrer inside the IL white label —
# NOT a tenant. Same pattern as cpal_dashboard.tf and cu_denver_dashboard.tf:
# cards query the IL tenant connection (so white-label RLS limits rows to
# white_label_id = 39) and additionally apply a scope predicate baked into each
# query. There are no editable parameters, and the viewer group has
# collection-read only with no ad-hoc DB query access (see permissions.tf), so
# a viewer sees exactly what is defined here and cannot broaden it.
#
# Card set deliberately mirrors CPAL's rather than the full Illinois tenant
# dashboard: partner-facing referrer dashboards are the compact shape, and
# 211 Metro Chicago has not launched, so there is no usage yet to tell us which
# of the tenant dashboard's ~80 cards they would actually want. Grow it once
# they are live.
#
# -----------------------------------------------------------------------------
# Three layers of scoping, only the first enforced below Metabase:
#
#   1. Postgres RLS pins rows to white_label_id = 39 on the IL connection.
#      RLS understands white label and NOTHING else (see
#      dbt/macros/row_level_security.sql), so the Cook and referrer limits
#      below are presentation-layer guarantees, not database ones.
#   2. The predicate baked into every card here: referrer, Cook, launch date.
#   3. create_queries = "no" on every database for the viewer group.
#
# Test and incomplete screens never reach these cards regardless:
# int_complete_screener_data already filters completed = TRUE, is_test = FALSE,
# is_test_data = FALSE and partner IS DISTINCT FROM 'Test'.
# =============================================================================

locals {
  chicago211_db_id  = tonumber(metabase_database.tenant_postgres["il"].id)
  chicago211_col_id = tonumber(metabase_collection.chicago211.id)

  # Scoped to traffic that arrived through their link.
  #
  # NOTE for when they launch: this keys on `referrer_code`, which counts only
  # screens carrying ?referrer=211chicago. CPAL instead keys on the mart's
  # `partner` column, which is derived from referrer_code OR the user-selected
  # referral_source — for CPAL that second path is 21 of 100 screeners. The
  # Referrer row currently has show_in_dropdown = False, so there is no second
  # path to miss yet; switch this to `partner = '211 Metro Chicago'` at the same
  # time that flag is flipped, or dropdown-attributed screens silently vanish.
  chicago211_referrer_predicate = "referrer_code = '211chicago'"

  # Cook County. Normalized both sides because county text arrives as either
  # "Cook" or "Cook County" depending on where it was set — the same normalizer
  # mart_screener_household_attributes.sql uses for its region join.
  #
  # This is the one line to change if 211 Metro Chicago defines Cook County as a
  # ZIP allowlist rather than the county field. The two are NOT equivalent in
  # Illinois: counties_by_zipcode maps some ZIPs to more than one county (e.g.
  # 60007 -> Cook or DuPage) and the county is then the user's own selection.
  # See MFB-1885 §4.
  chicago211_county_predicate = "lower(regexp_replace(trim(county), '\\s+county$', '', 'i')) = 'cook'"

  # Only applied once a launch date is set (see variables.tf). Until then the
  # referrer predicate alone already excludes every pre-launch screener, because
  # no screen can carry the referrer code before the link exists — the date is a
  # guard against a stray pre-launch test link, not the thing doing the work.
  chicago211_date_predicate = (
    var.chicago211_launch_date == null
    ? ""
    : " AND submission_date >= '${var.chicago211_launch_date}'"
  )

  chicago211_predicate = join("", [
    local.chicago211_referrer_predicate,
    " AND ",
    local.chicago211_county_predicate,
    local.chicago211_date_predicate,
  ])

  # Scoped variant of the shared qualified-benefits table SQL: strip the
  # optional [[...]] filter clauses, then inject the scope predicate onto every
  # "WHERE 1 = 1" anchor (the CTE and the denominator subquery both need it for
  # correct percentages).
  chicago211_qualified_benefits_sql = replace(
    replace(templatefile("${path.module}/sql/qualified_benefits.sql", {}), local._optional_clause_regex, ""),
    "WHERE 1 = 1",
    "WHERE 1 = 1 AND ${local.chicago211_predicate}"
  )
}

# -----------------------------------------------------------------------------
# Raw totals scorecards
# -----------------------------------------------------------------------------

resource "metabase_card" "chicago211_completed_screeners" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Respondents (Completed Screeners)"
    collection_id = local.chicago211_col_id
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "SELECT count(*) AS \"Respondents\" FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate}"
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "chicago211_total_benefits_dollars" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Total Annual Benefits $ Identified"
    collection_id = local.chicago211_col_id
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "SELECT COALESCE(SUM(non_tax_credit_benefits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "chicago211_total_tax_credits" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Total Potential Tax Credits $"
    collection_id = local.chicago211_col_id
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "SELECT COALESCE(SUM(tax_credits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "chicago211_total_combined" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Total Annual Value Identified (Benefits + Tax Credits)"
    collection_id = local.chicago211_col_id
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "SELECT COALESCE(SUM(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

# -----------------------------------------------------------------------------
# High / median / low benefits access per household
# -----------------------------------------------------------------------------

resource "metabase_card" "chicago211_highest_household_value" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Highest Annual Value / Household"
    collection_id = local.chicago211_col_id
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "SELECT COALESCE(MAX(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS highest FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "highest"
      "column_settings" = { "[\"name\",\"highest\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "chicago211_median_household_value" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Median Annual Value / Household (of those matched)"
    collection_id = local.chicago211_col_id
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual + tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate} AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "chicago211_lowest_household_value" {
  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "Lowest Annual Value / Household (of those matched)"
    collection_id = local.chicago211_col_id
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "SELECT COALESCE(MIN(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS lowest FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate} AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "lowest"
      "column_settings" = { "[\"name\",\"lowest\"]" = local.currency_format_0 }
    }
  }))
}

# -----------------------------------------------------------------------------
# Distribution, trend, program mix
# -----------------------------------------------------------------------------

resource "metabase_card" "chicago211_value_distribution" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "Annual Value per Household — Distribution"
    description   = "How much annual benefit value each Cook County household reaching the screener through 211 Metro Chicago could access, bucketed."
    collection_id = local.chicago211_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "WITH vals AS (SELECT non_tax_credit_benefits_annual + tax_credits_annual AS v FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate}) SELECT CASE WHEN v = 0 THEN '$0' WHEN v < 5000 THEN '$1-$4,999' WHEN v < 10000 THEN '$5,000-$9,999' WHEN v < 20000 THEN '$10,000-$19,999' WHEN v < 40000 THEN '$20,000-$39,999' ELSE '$40,000+' END AS bucket, count(*) AS households FROM vals GROUP BY 1 ORDER BY MIN(CASE WHEN v = 0 THEN 0 WHEN v < 5000 THEN 1 WHEN v < 10000 THEN 2 WHEN v < 20000 THEN 3 WHEN v < 40000 THEN 4 ELSE 5 END)"
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

resource "metabase_card" "chicago211_monthly_screeners" {
  json = jsonencode(merge(local.global_card_base_config, {
    name          = "Completed Screeners by Month"
    collection_id = local.chicago211_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = "SELECT DATE_TRUNC('month', submission_date)::date AS month, count(*) AS screeners FROM analytics.mart_screener_data WHERE ${local.chicago211_predicate} GROUP BY 1 ORDER BY 1"
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

resource "metabase_card" "chicago211_qualified_benefits_table" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "What benefits did people qualify for?"
    description   = "Most common benefits matched for completed screeners from Cook County households reaching MyFriendBen through 211 Metro Chicago."
    collection_id = local.chicago211_col_id
    dataset_query = {
      type     = "native"
      database = local.chicago211_db_id
      native = {
        query = local.chicago211_qualified_benefits_sql
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
# Dashboard
# -----------------------------------------------------------------------------

resource "metabase_dashboard" "chicago211" {
  name                = "211 Metro Chicago Screener Impact"
  description         = "Aggregate impact of the MyFriendBen screener for Cook County households reaching it through 211 Metro Chicago. Completed screeners only; no personal data."
  collection_id       = local.chicago211_col_id
  collection_position = 1

  # Single tab, declared explicitly — the same shape cu_denver uses. A second
  # tab is how a Cook-wide context view would be added (CPAL's pattern) if that
  # is the direction taken in MFB-1885 §3.
  tabs_json = jsonencode([
    { id = 1, name = "Overview" },
  ])

  # The provider fails an apply with "inconsistent result" unless cards_json is
  # in the order Metabase returns it: dashboard_tab_id, then row, then col.
  # Keep every block below in that order when editing.
  cards_json = jsonencode([
    # Row 0 — raw totals scorecards
    { card_id = tonumber(metabase_card.chicago211_completed_screeners.id), dashboard_tab_id = 1, row = 0, col = 0, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.chicago211_total_benefits_dollars.id), dashboard_tab_id = 1, row = 0, col = 6, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.chicago211_total_tax_credits.id), dashboard_tab_id = 1, row = 0, col = 12, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.chicago211_total_combined.id), dashboard_tab_id = 1, row = 0, col = 18, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 4 — high/median/low scorecards
    { card_id = tonumber(metabase_card.chicago211_highest_household_value.id), dashboard_tab_id = 1, row = 4, col = 0, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.chicago211_median_household_value.id), dashboard_tab_id = 1, row = 4, col = 8, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.chicago211_lowest_household_value.id), dashboard_tab_id = 1, row = 4, col = 16, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 8 — value distribution + monthly trend
    { card_id = tonumber(metabase_card.chicago211_value_distribution.id), dashboard_tab_id = 1, row = 8, col = 0, size_x = 12, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.chicago211_monthly_screeners.id), dashboard_tab_id = 1, row = 8, col = 12, size_x = 12, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 14 — program mix table
    { card_id = tonumber(metabase_card.chicago211_qualified_benefits_table.id), dashboard_tab_id = 1, row = 14, col = 0, size_x = 24, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },
  ])
}
