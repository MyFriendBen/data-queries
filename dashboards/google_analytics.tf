# Shared BigQuery/GA4-derived locals for the screener analytics cards.
# Consumed by dashboards/screener_analytics.tf: ga_tenants_enabled,
# tenant_ga_state_filter, ga_date_tags, and the shared date-filter parameter ids
# (_ga_start_date_param_id / _ga_end_date_param_id) used across the screener tabs.
# The GA marts (mart_ga_kpi_summary, mart_ga_traffic_mediums, mart_ga_clicked_links,
# etc.) remain available in dbt and feed the macro-funnel Visitors stage.

locals {
  # Tenants enabled for the BigQuery/GA4-derived analytics cards.
  # Derived from the central tab config: any tenant that has AT LEAST ONE screener
  # analytics tab configured (overview / form-journey / results / sharing-saving)
  # participates. Keyed off ALL four tab flags (not just screener_overview) so the
  # per-tenant screener cards are created whenever ANY screener tab is enabled —
  # otherwise adding, say, only "screener_results" to a tenant's tenant_tabs would
  # place the tab but leave its cards uncreated (ga_tenants_enabled would be
  # empty), producing a visible-but-empty tab. Re-adding any screener tab key to a
  # tenant's tenant_tabs list re-creates that tenant's screener cards.
  ga_tenants = {
    for key, tenant in var.tenants : key => tenant
    if local.tenant_has_tab[key]["screener_overview"]
    || local.tenant_has_tab[key]["screener_form_journey"]
    || local.tenant_has_tab[key]["screener_results"]
    || local.tenant_has_tab[key]["screener_sharing_saving"]
  }
  # Analytics cards are enabled for all eligible tenants when BigQuery is on.
  ga_tenants_enabled = var.bigquery_enabled ? local.ga_tenants : {}


  # Map each tenant to the GA state_code(s) used in URL paths.
  # cesn maps to two URL prefixes; update once CESN gets its own GA4 property.
  tenant_ga_state_codes = {
    nc   = ["nc"]
    co   = ["co"]
    tx   = ["tx"]
    wa   = ["wa"]
    il   = ["il"]
    ma   = ["ma"]
    cesn = ["cesn"]
  }

  # Pre-computed SQL IN clause per tenant for use in native queries.
  # Usage: WHERE state_code IN (${local.tenant_ga_state_filter[each.key]})
  tenant_ga_state_filter = {
    for key, codes in local.tenant_ga_state_codes :
    key => join(", ", [for c in codes : "'${c}'"])
  }

  # Valid screener_state codes for the GLOBAL (all-states) screener cards, as a
  # SQL IN-list. Used instead of a no-op `1=1` so the global cards only count the
  # clean app-emitted rows: the marts also contain legacy DOM-scrape rows (state
  # stored as a display name like 'Colorado') and null-state landing rows, which a
  # bare `1=1` would sweep in and inflate. Filtering to the known lowercase codes
  # keeps global cards consistent with the per-tenant cards.
  #
  # EXCLUDES `cesn`: it's an energy program (not a US state) with a DIFFERENT
  # screener flow (extra energy steps), so folding it into "all-states" totals —
  # especially the step-level charts — is misleading. CESN data lives on its own
  # tenant dashboard.
  all_screener_state_filter = join(", ", [
    for k, codes in local.tenant_ga_state_codes : join(", ", [for c in codes : "'${c}'"])
    if k != "cesn"
  ])

  # Global predicate for the two marts that carry the session-level is_cesn flag
  # AND retain null-state rows (form funnel + results outcomes). It:
  #  - keeps known non-CESN state codes,
  #  - ALSO keeps null-state rows (pre-white-label landing / language / select-state
  #    sessions the funnel mart deliberately retains for correct top-of-funnel), and
  #  - excludes every CESN session's rows via NOT is_cesn — including a CESN
  #    session's own null-state landing rows (energysavings.colorado.gov redirect),
  #    which a bare `OR screener_state IS NULL` would otherwise leak back in.
  # Other global marts (interactions, saves, shares, resources, language) fire
  # after a white-label is set — no null-state rows and no cesn rows — so they use
  # the plain all_screener_state_filter IN-list and need no is_cesn column.
  all_screener_global_predicate = "NOT is_cesn AND (screener_state IN (${local.all_screener_state_filter}) OR screener_state IS NULL)"

  # Shared note shown at the top of each screener engagement tab, explaining the
  # data start date + ramp-up so a sparse recent window isn't misread as a drop.
  screener_epoch_note = "📊 **About this data** — Screener engagement tracking reflects activity from **July 21, 2026** forward, the day the current event contract (MFB-1348) went live in production."

  # Analytics epoch: the day the current app-emitted screener_* event CONTRACT went
  # live in production. Every screener card floors on this so metrics reflect one
  # contract. MFB-1348 (stable per-rule error codes, member-basics/member-details
  # sub-step slugs, results-as-step, help step context) shipped to prod 2026-07-21;
  # flooring here means the cards use the new contract only — no legacy English error
  # messages or parent household-members slug. A fixed historical fact.
  screener_analytics_epoch = "2026-07-21"

  # Convenience prefix for BigQuery table references in native SQL.
  # Usage: `${local.bq_dataset}.table_name`
  bq_dataset = "${var.gcp_project_id}.${var.bigquery_analytics_dataset}"

  # Plain date variables (not field filters) — avoids the Metabase BigQuery driver bug
  # where field filters generate `schema.table`.column references that BigQuery misparses.
  # We write the SQL condition ourselves so Metabase never touches the column reference.
  ga_date_tags = var.bigquery_enabled ? {
    start_date = {
      id             = "ga_start_date"
      name           = "start_date"
      "display-name" = "Start Date"
      type           = "date"
    }
    end_date = {
      id             = "ga_end_date"
      name           = "end_date"
      "display-name" = "End Date"
      type           = "date"
    }
  } : {}

  # Shared dashboard-parameter ids for the start/end date filters. The screener
  # layout locals map these onto each card's start_date / end_date template-tags.
  _ga_start_date_param_id = "ga_start_date_filter"
  _ga_end_date_param_id   = "ga_end_date_filter"
}
