# Shared SQL strings for the Postgres-backed Metabase cards.
#
# PATTERN (mirrors screener_analytics_sql.tf — the screener DRY model):
#
#   • Each local is written in its TENANT form — with the complete set of
#     Metabase [[AND {{filter}}]] optional-clause markers that the tenant card
#     needs for template-tag wiring.
#
#   • Tenant cards (for_each = var.tenants) consume the local directly:
#       query           = local.sql_<name>
#       "template-tags" = local.filter_template_tags[each.key]
#
#   • Global cards (single-instance, no template-tags) strip the optional
#     clauses before use:
#       query = replace(local.sql_<name>, local._optional_clause_regex, "")
#     One definition, zero drift — changing the SQL here keeps both scopes
#     in sync automatically.
#
#   • local._optional_clause_regex is defined in global_cards.tf.
#     It matches /\s*\[\[[^\]]*\]\]/ (all Metabase optional-filter markers).
#
#   • SQL files (templatefile("${path.module}/sql/*.sql", {})) are already a
#     single source and do not need extraction here.  Global cards already
#     use replace(templatefile(...), local._optional_clause_regex, "") and
#     tenant cards use templatefile(...) directly.
#
# ─── CESN sentinel ──────────────────────────────────────────────────────────
# CESN cards have no global counterparts but pair homeowner / renter variants
# that share the same query logic.  Those use the sentinel __SEGMENT_FILTER__
# (mirroring __STATE_FILTER__ in screener_analytics_sql.tf) which callers
# substitute with the relevant predicate:
#
#   replace(local.sql_cesn_<name>, "__SEGMENT_FILTER__", "is_home_owner = true")
#   replace(local.sql_cesn_<name>, "__SEGMENT_FILTER__", "is_renter = true")
#
# Appliance-need cards (homeowners only) additionally substitute
# __NEEDS_COLUMN__ with the relevant boolean column name:
#
#   replace(replace(local.sql_cesn_needs_appliance,
#     "__SEGMENT_FILTER__", "is_home_owner = true"),
#     "__NEEDS_COLUMN__", "needs_stove")
#
# ─── No-op guarantee ────────────────────────────────────────────────────────
# This is a pure refactor.  The string produced by each consumer is byte-for-
# byte identical to the inline SQL it replaces, so `terraform plan` should
# show no changes except for `global_already_had_benefits_pct` whose SQL is
# aligned from "...mart_screener_data" to "...mart_screener_data WHERE 1=1"
# (semantically equivalent; required to match the tenant SQL structure after
# stripping optional clauses with the regex).

locals {
  # ──────────────────────────────────────────────────────────────────────────
  # Tab 1 / Tab 5 — Overall Performance & Benefits scorecards
  # Source files:
  #   tenant  → benefits_and_immediate_needs.tf (for_each = var.tenants)
  #   global  → global_cards.tf (single instance)
  # ──────────────────────────────────────────────────────────────────────────

  sql_completed_screeners = "SELECT count(*) AS \"Completed Screeners\" FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]"

  sql_already_had_benefits_pct = "SELECT count(*) FILTER (WHERE has_benefits = 'true')::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]"

  sql_qualified_for_benefits_pct = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]"

  sql_qualified_for_tax_creds_pct = "SELECT count(*) FILTER (WHERE tax_credits_annual > 0)::float / NULLIF(count(*), 0) as pct FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]] [[AND {{utm_campaign}}]] [[AND {{utm_medium}}]] [[AND {{utm_source}}]]"

  # ──────────────────────────────────────────────────────────────────────────
  # Tab 2 / Tab 4 — Households scorecards
  # Source files:
  #   tenant  → households.tf (for_each = var.tenants)
  #   global  → global_cards.tf (single instance)
  # Note: households scorecard queries carry only 3 optional filters (no UTM).
  # ──────────────────────────────────────────────────────────────────────────

  sql_median_household_size = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY household_size) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]"

  sql_median_household_assets = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY household_assets) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]"

  sql_median_annual_income = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_income * 12) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]"

  sql_median_monthly_income = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_income) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]"

  sql_median_monthly_expenses = "SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_expenses) AS median FROM analytics.mart_screener_data WHERE 1=1 [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]"

  # ──────────────────────────────────────────────────────────────────────────
  # CESN — Homeowners vs Renters (cesn_homeowners_vs_renters.tf)
  # No global counterparts; extracted here so each question type has ONE SQL
  # definition shared by both the homeowner and renter variants.
  #
  # Callers substitute __SEGMENT_FILTER__ at point of use:
  #   replace(local.sql_cesn_<name>, "__SEGMENT_FILTER__", "is_home_owner = true")
  #   replace(local.sql_cesn_<name>, "__SEGMENT_FILTER__", "is_renter = true")
  # ──────────────────────────────────────────────────────────────────────────

  sql_cesn_scorecards_completed = "SELECT count(*) AS count FROM analytics.mart_screener_data WHERE __SEGMENT_FILTER__ [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]"

  sql_cesn_scorecards_qualified_pct = "SELECT count(*) FILTER (WHERE non_tax_credit_benefits_annual > 0)::float / NULLIF(count(*), 0) AS pct FROM analytics.mart_screener_data WHERE __SEGMENT_FILTER__ [[AND {{submission_date}}]] [[AND {{partner}}]] [[AND {{county}}]]"

  sql_cesn_daily_screeners = <<-SQL
    SELECT submission_date, count(*) AS "Screeners"
    FROM analytics.mart_screener_data
    WHERE __SEGMENT_FILTER__
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
    GROUP BY submission_date ORDER BY submission_date
  SQL

  sql_cesn_electric_provider = <<-SQL
    SELECT
      COALESCE(electric_provider_name, electric_provider, '(Unknown)') AS "Provider",
      count(*) AS "# of Screeners"
    FROM analytics.mart_screener_data
    WHERE __SEGMENT_FILTER__
      AND electric_provider IS NOT NULL
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
    GROUP BY 1
    ORDER BY 2 DESC
    LIMIT 20
  SQL

  sql_cesn_gas_provider = <<-SQL
    SELECT
      COALESCE(gas_heat_provider_name, gas_heat_provider, '(Unknown)') AS "Provider",
      count(*) AS "# of Screeners"
    FROM analytics.mart_screener_data
    WHERE __SEGMENT_FILTER__
      AND gas_heat_provider IS NOT NULL
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
    GROUP BY 1
    ORDER BY 2 DESC
    LIMIT 20
  SQL

  sql_cesn_disconnected = <<-SQL
    SELECT
      CASE WHEN electricity_is_disconnected THEN 'Yes' ELSE 'No' END AS "Answer",
      count(*) AS "# of Screeners"
    FROM analytics.mart_screener_data
    WHERE __SEGMENT_FILTER__
      AND electricity_is_disconnected IS NOT NULL
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
    GROUP BY 1
    ORDER BY 1
  SQL

  sql_cesn_past_due = <<-SQL
    SELECT
      CASE WHEN has_past_due_energy_bills THEN 'Yes' ELSE 'No' END AS "Answer",
      count(*) AS "# of Screeners"
    FROM analytics.mart_screener_data
    WHERE __SEGMENT_FILTER__
      AND has_past_due_energy_bills IS NOT NULL
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
    GROUP BY 1
    ORDER BY 1
  SQL

  sql_cesn_old_car = <<-SQL
    SELECT
      CASE WHEN has_old_car THEN 'Yes' ELSE 'No' END AS "Answer",
      count(*) AS "# of Screeners"
    FROM analytics.mart_screener_data
    WHERE __SEGMENT_FILTER__
      AND has_old_car IS NOT NULL
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
    GROUP BY 1
    ORDER BY 1
  SQL

  # Appliance-need cards are homeowners-only, so __SEGMENT_FILTER__ is always
  # "is_home_owner = true".  __NEEDS_COLUMN__ is the boolean column to test.
  # Callers:
  #   replace(replace(local.sql_cesn_needs_appliance,
  #     "__SEGMENT_FILTER__", "is_home_owner = true"),
  #     "__NEEDS_COLUMN__", "needs_stove")
  sql_cesn_needs_appliance = <<-SQL
    SELECT
      CASE WHEN __NEEDS_COLUMN__ THEN 'Yes' ELSE 'No' END AS "Answer",
      count(*) AS "# of Screeners"
    FROM analytics.mart_screener_data
    WHERE __SEGMENT_FILTER__
      AND __NEEDS_COLUMN__ IS NOT NULL
      [[AND {{submission_date}}]]
      [[AND {{partner}}]]
      [[AND {{county}}]]
    GROUP BY 1
    ORDER BY 1
  SQL
}
