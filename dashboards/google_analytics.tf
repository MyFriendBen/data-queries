# Shared analytics locals (BigQuery/GA4-derived), retained after the old
# "Google Analytics" dashboard tab was retired. The GA-backed dashboard cards and
# the tab-1 layout were removed; these locals are still consumed by the screener
# analytics cards in dashboards/screener_analytics.tf (ga_tenants_enabled,
# tenant_ga_state_filter, ga_date_tags) and by the shared date-filter parameter
# ids used across the screener tabs (_ga_start_date_param_id / _ga_end_date_param_id).
#
# The GA marts (mart_ga_kpi_summary, mart_ga_traffic_mediums, mart_ga_clicked_links,
# etc.) are intentionally left in place in dbt — only the dashboard cards/tab were
# retired.

locals {
  # Tenants enabled for the BigQuery/GA4-derived analytics cards.
  # Derived from the central tab config: any tenant that has AT LEAST ONE screener
  # analytics tab configured (overview / form-journey / results / sharing-saving)
  # participates. Keyed off ALL four tab flags (not just screener_overview) so the
  # per-tenant screener cards are created whenever ANY screener tab is enabled —
  # otherwise re-adding, say, only "screener_results" to a tenant's tenant_tabs
  # would place the tab but leave its cards uncreated (ga_tenants_enabled would
  # still be empty), producing a visible-but-empty tab. See MFB-1268.
  # NOTE: all four screener tabs are currently removed from every tenant_tabs list
  # (hidden pending review), so this set is {} today — the per-tenant screener
  # cards are not created. Re-add any screener tab key to a tenant to re-enable.
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
