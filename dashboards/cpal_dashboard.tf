# =============================================================================
# CPAL (Child Poverty Action Lab) dashboard — MFB-1198, MFB-1713
# =============================================================================
# CPAL is a partner (referrer) inside the TX white label — NOT a tenant. Same
# pattern as cu_denver_dashboard.tf: cards query the TX tenant connection (so
# white-label RLS limits rows to TX) and additionally apply a CPAL partner
# predicate. Filters are baked into each query (no editable parameters) and the
# CPAL viewer group has collection-read only + no ad-hoc DB query access (see
# permissions.tf), so viewers see exactly the two views defined here.
#
# Two scopes → two tabs (MFB-1713, requested by John Hill at CPAL):
#   Tab 1 "CPAL"       — CPAL-attributed traffic only
#   Tab 2 "All Texas"  — every TX completed screener, all partners
# Every card is generated once per scope from local.cpal_scopes, so a metric
# can't drift between the two tabs. The tab bar IS the toggle; deliberately no
# editable parameter, so a viewer can't land the dashboard in an error state.
#
# NOTE on scope: the All Texas tab is a considered exception to the "no
# cross-partner comparison" line cu_denver_dashboard.tf draws. CPAL asked for
# TX-wide context and MFB agreed (MFB-1713). Everything shown is still
# aggregate, de-identified, completed-screener data within white_label_id = 40.
#
# Layout maps to CPAL's requests (see MFB-1198):
#   1. Quick raw totals         → row 0 scorecards
#   2. High/low benefits access → row 4 scorecards + distribution chart
#   4. Partner toggling         → the CPAL collection + "CPAL Viewers" group
#      (partner sees exactly their own scoped dashboard after login)
#
# Request 3 (contact data export) is deliberately NOT served from Metabase:
# MFB anonymizes user PII in Postgres immediately after syncing consenting
# signups to HubSpot (see benefits-api integrations/services/cms_integration.py
# and authentication/views.py — "This separates PII from household
# demographic"). Contact follow-up data lives in HubSpot, keyed by screen
# uuid; the export belongs there, not in a dashboard card.
#
# -----------------------------------------------------------------------------
# The "~500 vs ~1200" partner discrepancy (MFB-1713) — root cause, for the
# next person who gets asked:
#
# The Partner filter on the Texas tenant dashboard does not offer every value
# of mart_screener_data.partner. Its value list comes from the
# tenant_partner_values helper card (metabase.tf), which lists only referrers
# flagged is_partner = true in programs_referrer. TX has 46 referrer codes and
# only 10 carry that flag, so selecting every option in the widget still
# excludes the rest — hence fewer screeners with the filter applied than with
# no filter at all.
#
# Measured on the production follower, 2026-08-26 (white_label_id = 40):
#   1,423 completed screeners total
#     668 attributable to an is_partner = true referrer (filter-selectable)
#     755 not selectable: Other 252, Friend/Family 184, Social Media 163,
#         Google 80, Flyer 73, Bridge Homeless Recovery Center 3
#
# So the delta is NOT direct-website traffic (every row has some attribution);
# it is people who picked a generic "how did you hear about us" option. The
# "All Texas — How did people hear about us?" card below puts all of it on the
# dashboard so the gap is self-explaining rather than inferred from filter
# behaviour. Note is_partner also controls partner-vs-generic grouping in the
# live screener dropdown (benefits-api screener/views.py), so re-flagging the
# ~30 Dallas coalition orgs is a product decision, tracked separately.
# =============================================================================

locals {
  cpal_db_id  = tonumber(metabase_database.tenant_postgres["tx"].id)
  cpal_col_id = tonumber(metabase_collection.cpal.id)

  # Confirmed against production programs_referrer (2026-08-11): the TX white
  # label (id 40) has referrer_code 'cpal' → "Child Poverty Action Lab (CPAL)",
  # is_partner = true. As CPAL outreach efforts get their own unique URLs
  # (per MFB-1198), add each new referrer's display name to this list.
  #
  # We filter on the mart's `partner` column (display name) rather than raw
  # referrer_code: `partner` is derived in int_complete_screener_data from
  # referrer_code OR the user-selected referral_source, so it captures screens
  # attributed to CPAL via either path and keeps this dashboard's numbers
  # consistent with the Texas partner table. (RLS on the TX connection already
  # scopes rows to white_label_id = 40, so no cross-state name collisions.)
  # As of 2026-08-26 that is 100 screeners: 79 via the ?referrer=cpal link,
  # 21 who picked CPAL in the screener's referral-source dropdown.
  cpal_partner_names = ["Child Poverty Action Lab (CPAL)"]

  cpal_referrer_predicate = format(
    "partner IN (%s)",
    join(", ", [for n in local.cpal_partner_names : format("'%s'", n)])
  )

  # One entry per tab. `predicate` is spliced into every card's WHERE clause;
  # the tx scope uses a tautology so both tabs share a single code path (the
  # TX connection's RLS is what bounds it to white_label_id = 40).
  cpal_scopes = {
    cpal = {
      tab_id      = 1
      tab_name    = "CPAL"
      name_prefix = ""
      predicate   = local.cpal_referrer_predicate
      audience    = "CPAL"
    }
    tx = {
      tab_id      = 2
      tab_name    = "All Texas"
      name_prefix = "All Texas — "
      predicate   = "1 = 1"
      audience    = "all Texas"
    }
  }

  # Scoped variants of the shared qualified-benefits table SQL: strip the
  # optional [[...]] filter clauses, then inject the scope predicate onto every
  # "WHERE 1 = 1" anchor (CTE + denominator subquery — both need it for correct
  # percentages).
  cpal_qualified_benefits_sql = {
    for key, scope in local.cpal_scopes : key => replace(
      replace(templatefile("${path.module}/sql/qualified_benefits.sql", {}), local._optional_clause_regex, ""),
      "WHERE 1 = 1",
      "WHERE 1 = 1 AND ${scope.predicate}"
    )
  }
}

# -----------------------------------------------------------------------------
# Request 1 — quick raw totals ("X respondents, Y benefits dollars, Z tax credits")
# -----------------------------------------------------------------------------

resource "metabase_card" "cpal_completed_screeners" {
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "${each.value.name_prefix}Respondents (Completed Screeners)"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT count(*) AS \"Respondents\" FROM analytics.mart_screener_data WHERE ${each.value.predicate}"
      }
    }
    visualization_settings = { "scalar.field" = "count" }
  }))
}

resource "metabase_card" "cpal_total_benefits_dollars" {
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "${each.value.name_prefix}Total Annual Benefits $ Identified"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(SUM(non_tax_credit_benefits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${each.value.predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_total_tax_credits" {
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "${each.value.name_prefix}Total Potential Tax Credits $"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(SUM(tax_credits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${each.value.predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "total"
      "column_settings" = { "[\"name\",\"total\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_total_combined" {
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "${each.value.name_prefix}Total Annual Value Identified (Benefits + Tax Credits)"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(SUM(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS total FROM analytics.mart_screener_data WHERE ${each.value.predicate}"
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
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "${each.value.name_prefix}Highest Annual Value / Household"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(MAX(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS highest FROM analytics.mart_screener_data WHERE ${each.value.predicate}"
      }
    }
    visualization_settings = {
      "scalar.field"    = "highest"
      "column_settings" = { "[\"name\",\"highest\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_lowest_household_value" {
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "${each.value.name_prefix}Lowest Annual Value / Household (of those matched)"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT COALESCE(MIN(non_tax_credit_benefits_annual + tax_credits_annual), 0) AS lowest FROM analytics.mart_screener_data WHERE ${each.value.predicate} AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "lowest"
      "column_settings" = { "[\"name\",\"lowest\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_median_household_value" {
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_scorecard_config, {
    name          = "${each.value.name_prefix}Median Annual Value / Household (of those matched)"
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY non_tax_credit_benefits_annual + tax_credits_annual) AS median FROM analytics.mart_screener_data WHERE ${each.value.predicate} AND (non_tax_credit_benefits_annual + tax_credits_annual) > 0"
      }
    }
    visualization_settings = {
      "scalar.field"    = "median"
      "column_settings" = { "[\"name\",\"median\"]" = local.currency_format_0 }
    }
  }))
}

resource "metabase_card" "cpal_value_distribution" {
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_card_base_config, {
    name          = "${each.value.name_prefix}Annual Value per Household — Distribution"
    description   = "How much annual benefit value each ${each.value.audience} household could access, bucketed."
    collection_id = local.cpal_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "WITH vals AS (SELECT non_tax_credit_benefits_annual + tax_credits_annual AS v FROM analytics.mart_screener_data WHERE ${each.value.predicate}) SELECT CASE WHEN v = 0 THEN '$0' WHEN v < 5000 THEN '$1-$4,999' WHEN v < 10000 THEN '$5,000-$9,999' WHEN v < 20000 THEN '$10,000-$19,999' WHEN v < 40000 THEN '$20,000-$39,999' ELSE '$40,000+' END AS bucket, count(*) AS households FROM vals GROUP BY 1 ORDER BY MIN(CASE WHEN v = 0 THEN 0 WHEN v < 5000 THEN 1 WHEN v < 10000 THEN 2 WHEN v < 20000 THEN 3 WHEN v < 40000 THEN 4 ELSE 5 END)"
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
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_card_base_config, {
    name          = "${each.value.name_prefix}Completed Screeners by Month"
    collection_id = local.cpal_col_id
    display       = "bar"
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = "SELECT DATE_TRUNC('month', submission_date)::date AS month, count(*) AS screeners FROM analytics.mart_screener_data WHERE ${each.value.predicate} GROUP BY 1 ORDER BY 1"
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
  for_each = local.cpal_scopes

  json = jsonencode(merge(local.global_table_card_config, {
    name          = "${each.value.name_prefix}What benefits did people qualify for?"
    description   = "Most common benefits matched for ${each.value.audience} completed screeners."
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = local.cpal_qualified_benefits_sql[each.key]
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
# All Texas tab only — attribution breakdown (MFB-1713)
# -----------------------------------------------------------------------------
# Answers "where did the other ~700 screeners come from?" directly on the
# dashboard. Reuses the shared top_partners.sql (partner / # / % plus a Total
# row) with the optional [[...]] clauses stripped, so it lists EVERY attribution
# value in TX — including the generic options the Texas dashboard's Partner
# filter cannot select. Deliberately not scoped to CPAL: a CPAL-only version
# would show a single row.
resource "metabase_card" "cpal_tx_attribution" {
  json = jsonencode(merge(local.global_table_card_config, {
    name          = "All Texas — How did people hear about us?"
    description   = "Every attribution value for Texas completed screeners, partner and generic alike. Rows the Texas dashboard's Partner filter cannot select (Other, Friend / Family, Social Media, Google, Flyer) appear here — that is the gap between filtered and unfiltered screener counts."
    collection_id = local.cpal_col_id
    dataset_query = {
      type     = "native"
      database = local.cpal_db_id
      native = {
        query = replace(
          templatefile("${path.module}/sql/top_partners.sql", {}),
          local._optional_clause_regex, ""
        )
      }
    }
    visualization_settings = merge(local.global_table_card_config.visualization_settings, {
      "table.column_widths" = [
        { "name" = "Partner", "width" = 300 },
        { "name" = "# of Screeners", "width" = 120 },
        { "name" = "% of Screeners", "width" = 120 },
      ]
      "table.row_index" = true
      "column_settings" = local.benefits_column_settings
    })
  }))
}

# -----------------------------------------------------------------------------
# Dashboard
# -----------------------------------------------------------------------------

resource "metabase_dashboard" "cpal" {
  name                = "CPAL Screener Impact"
  description         = "Aggregate impact of the MyFriendBen screener for CPAL (Child Poverty Action Lab) partner traffic in Texas, with an All Texas tab for statewide context. Completed screeners only; no personal data."
  collection_id       = local.cpal_col_id
  collection_position = 1

  tabs_json = jsonencode([
    { id = local.cpal_scopes.cpal.tab_id, name = local.cpal_scopes.cpal.tab_name },
    { id = local.cpal_scopes.tx.tab_id, name = local.cpal_scopes.tx.tab_name },
  ])

  # The provider fails an apply with "inconsistent result" unless cards_json is
  # in the order Metabase returns it: dashboard_tab_id, then row, then col.
  # Keep every block below in that order when editing.
  cards_json = jsonencode([
    # =========================== Tab 1 — CPAL ================================
    # Row 0 — raw totals scorecards (Request 1)
    { card_id = tonumber(metabase_card.cpal_completed_screeners["cpal"].id), dashboard_tab_id = 1, row = 0, col = 0, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_benefits_dollars["cpal"].id), dashboard_tab_id = 1, row = 0, col = 6, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_tax_credits["cpal"].id), dashboard_tab_id = 1, row = 0, col = 12, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_combined["cpal"].id), dashboard_tab_id = 1, row = 0, col = 18, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 4 — high/median/low scorecards (Request 2)
    { card_id = tonumber(metabase_card.cpal_highest_household_value["cpal"].id), dashboard_tab_id = 1, row = 4, col = 0, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_median_household_value["cpal"].id), dashboard_tab_id = 1, row = 4, col = 8, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_lowest_household_value["cpal"].id), dashboard_tab_id = 1, row = 4, col = 16, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 8 — value distribution (Request 2, context) + monthly trend
    { card_id = tonumber(metabase_card.cpal_value_distribution["cpal"].id), dashboard_tab_id = 1, row = 8, col = 0, size_x = 12, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_monthly_screeners["cpal"].id), dashboard_tab_id = 1, row = 8, col = 12, size_x = 12, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 14 — program mix table
    { card_id = tonumber(metabase_card.cpal_qualified_benefits_table["cpal"].id), dashboard_tab_id = 1, row = 14, col = 0, size_x = 24, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },

    # ========================= Tab 2 — All Texas =============================
    # Same metrics, statewide (MFB-1713). Row 0 — raw totals scorecards
    { card_id = tonumber(metabase_card.cpal_completed_screeners["tx"].id), dashboard_tab_id = 2, row = 0, col = 0, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_benefits_dollars["tx"].id), dashboard_tab_id = 2, row = 0, col = 6, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_tax_credits["tx"].id), dashboard_tab_id = 2, row = 0, col = 12, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_total_combined["tx"].id), dashboard_tab_id = 2, row = 0, col = 18, size_x = 6, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 4 — high/median/low scorecards
    { card_id = tonumber(metabase_card.cpal_highest_household_value["tx"].id), dashboard_tab_id = 2, row = 4, col = 0, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_median_household_value["tx"].id), dashboard_tab_id = 2, row = 4, col = 8, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_lowest_household_value["tx"].id), dashboard_tab_id = 2, row = 4, col = 16, size_x = 8, size_y = 4, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 8 — value distribution + monthly trend
    { card_id = tonumber(metabase_card.cpal_value_distribution["tx"].id), dashboard_tab_id = 2, row = 8, col = 0, size_x = 12, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_monthly_screeners["tx"].id), dashboard_tab_id = 2, row = 8, col = 12, size_x = 12, size_y = 6, parameter_mappings = [], series = [], visualization_settings = {} },

    # Row 14 — attribution breakdown (answers the partner discrepancy) + program mix
    { card_id = tonumber(metabase_card.cpal_tx_attribution.id), dashboard_tab_id = 2, row = 14, col = 0, size_x = 12, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },
    { card_id = tonumber(metabase_card.cpal_qualified_benefits_table["tx"].id), dashboard_tab_id = 2, row = 14, col = 12, size_x = 12, size_y = 8, parameter_mappings = [], series = [], visualization_settings = {} },
  ])
}

# -----------------------------------------------------------------------------
# State moves — MFB-1713
# -----------------------------------------------------------------------------
# The nine cards above became for_each resources when the All Texas tab was
# added. These blocks re-point the already-applied instances (created by
# MFB-1198) at their "cpal" keys, so Terraform updates them in place instead of
# destroying and recreating them with new Metabase card IDs. Safe to delete
# once this change has applied to every environment.
moved {
  from = metabase_card.cpal_completed_screeners
  to   = metabase_card.cpal_completed_screeners["cpal"]
}

moved {
  from = metabase_card.cpal_total_benefits_dollars
  to   = metabase_card.cpal_total_benefits_dollars["cpal"]
}

moved {
  from = metabase_card.cpal_total_tax_credits
  to   = metabase_card.cpal_total_tax_credits["cpal"]
}

moved {
  from = metabase_card.cpal_total_combined
  to   = metabase_card.cpal_total_combined["cpal"]
}

moved {
  from = metabase_card.cpal_highest_household_value
  to   = metabase_card.cpal_highest_household_value["cpal"]
}

moved {
  from = metabase_card.cpal_lowest_household_value
  to   = metabase_card.cpal_lowest_household_value["cpal"]
}

moved {
  from = metabase_card.cpal_median_household_value
  to   = metabase_card.cpal_median_household_value["cpal"]
}

moved {
  from = metabase_card.cpal_value_distribution
  to   = metabase_card.cpal_value_distribution["cpal"]
}

moved {
  from = metabase_card.cpal_monthly_screeners
  to   = metabase_card.cpal_monthly_screeners["cpal"]
}

moved {
  from = metabase_card.cpal_qualified_benefits_table
  to   = metabase_card.cpal_qualified_benefits_table["cpal"]
}
