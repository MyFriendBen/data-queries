# Cards for "Google Analytics" (Tab 1)
#
# All GA cards use BigQuery native SQL so metrics are computed accurately
# across the full date range rather than averaging pre-aggregated daily rates.
# Cards are created only for tenants with a Google Analytics tab configured
# in local.tenant_has_tab (config_template.tf).

locals {
  # Tenants that have a Google Analytics tab (derived from central tab config)
  ga_tenants = {
    for key, tenant in var.tenants : key => tenant
    if local.tenant_has_tab[key]["google_analytics"]
  }
  # Rollout control: GA cards (KPIs, charts) are enabled per-state as data is validated.
  # Add states here when ready; MAU chart always uses ga_tenants (all states) instead.
  ga_tenants_nc_only = var.bigquery_enabled && contains(keys(local.ga_tenants), "nc") ? { nc = local.ga_tenants["nc"] } : {}


  # Map each tenant to the GA state_code(s) used in URL paths.
  # cesn maps to two URL prefixes; update once CESN gets its own GA4 property.
  tenant_ga_state_codes = {
    nc   = ["nc"]
    co   = ["co"]
    tx   = ["tx"]
    il   = ["il"]
    ma   = ["ma"]
    cesn = ["cesn", "co_energy_calculator"]
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
}



# ── KPI Scorecards ────────────────────────────────────────────────────────────

# KPI: Total Visitors — SUM of daily session counts from mart_ga_kpi_summary
resource "metabase_card" "ga_total_visitors" {
  for_each = local.ga_tenants_nc_only


  json = jsonencode({
    name                = "Total Visitors"
    description         = "Total number of GA4 sessions"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT SUM(total_sessions) FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]"
        template-tags = local.ga_date_tags
      }
    }
    display                = "scalar"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

# KPI: Started Screener % — sessions that hit /step-1 as % of total sessions
resource "metabase_card" "ga_started_screener_pct" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Started Screener"
    description         = "Percentage of sessions that started the screener (/step-1)"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT CONCAT(CAST(ROUND(SUM(sessions_started_screener) * 100.0 / NULLIF(SUM(total_sessions), 0), 1) AS STRING), '%') FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]"
        template-tags = local.ga_date_tags
      }
    }
    display                = "scalar"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

# KPI: Completed to Click Rate (D/C ratio) — sessions that completed AND clicked / sessions completed
resource "metabase_card" "ga_completed_to_click_rate" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Completed to Click Rate"
    description         = "D/C ratio: % of completed screener sessions that also clicked an outbound link"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT CONCAT(CAST(ROUND(SUM(sessions_clicked_after_completion) * 100.0 / NULLIF(SUM(sessions_completed_screener), 0), 1) AS STRING), '%') FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]"
        template-tags = local.ga_date_tags
      }
    }
    display                = "scalar"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

# KPI: Completion Time — average of daily medians from mart_ga_kpi_summary
# Each daily row already holds an APPROX_QUANTILES p50 computed at session grain (see mart).
# AVG across days is an approximation of the true overall median but avoids querying the
# intermediate schema (dbt +schema: internal → different BigQuery dataset).
resource "metabase_card" "ga_median_completion_time" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Completion Time (approx. median)"
    description         = "Approximate median session duration from screener start to completion; average of daily p50 values"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT CONCAT(LPAD(CAST(DIV(secs, 3600) AS STRING), 2, '0'), ':', LPAD(CAST(DIV(MOD(secs, 3600), 60) AS STRING), 2, '0'), ':', LPAD(CAST(MOD(secs, 60) AS STRING), 2, '0')) FROM (SELECT CAST(ROUND(AVG(median_completion_time_seconds), 0) AS INT64) AS secs FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) AND median_completion_time_seconds IS NOT NULL [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]])"
        template-tags = local.ga_date_tags
      }
    }
    display                = "scalar"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

# ── Charts ────────────────────────────────────────────────────────────────────

# Conversion Funnel — A→B→C→D step counts as a funnel chart
# display = "funnel" works because the data is pre-shaped as ordered step rows.
# The subquery hides step_order so only (funnel_step, session_count) are returned.
resource "metabase_card" "ga_conversion_funnel" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Conversion Funnel"
    description         = "Session counts at each screener funnel step: A=Total, B=Started, C=Completed, D=Clicked"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = <<-SQL
          SELECT funnel_step, session_count
          FROM (
            SELECT 'Total Visitors' AS funnel_step, SUM(total_sessions) AS session_count, 1 AS step_order
            FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
            UNION ALL
            SELECT 'Started Screener', SUM(sessions_started_screener), 2
            FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
            UNION ALL
            SELECT 'Completed Screener', SUM(sessions_completed_screener), 3
            FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
            UNION ALL
            SELECT 'Clicked Link', SUM(sessions_clicked_after_completion), 4
            FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
          )
          ORDER BY step_order
        SQL
        template-tags = local.ga_date_tags
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["funnel_step"]
      "graph.metrics"    = ["session_count"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Conversion Funnel — detail table: step-by-step breakdown with counts and percentages
resource "metabase_card" "ga_conversion_funnel_table" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Conversion Funnel (Detail)"
    description         = "Step-by-step session counts and drop-off for the screener funnel"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = <<-SQL
          WITH totals AS (
            SELECT
              SUM(total_sessions)                    AS a,
              SUM(sessions_started_screener)         AS b,
              SUM(sessions_completed_screener)       AS c,
              SUM(sessions_clicked_after_completion) AS d
            FROM `${local.bq_dataset}.mart_ga_kpi_summary`
            WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
          ),
          steps AS (
            SELECT 'Total Visitors'     AS funnel_step, a AS session_count, a AS prev_count, 1 AS step_order FROM totals
            UNION ALL
            SELECT 'Started Screener',   b, a, 2 FROM totals
            UNION ALL
            SELECT 'Completed Screener', c, b, 3 FROM totals
            UNION ALL
            SELECT 'Clicked Link',       d, c, 4 FROM totals
          )
          SELECT
            funnel_step,
            session_count,
            ROUND(session_count * 100.0 / NULLIF(prev_count, 0), 1) AS conversion_pct,
            prev_count - session_count                               AS drop_off
          FROM steps
          ORDER BY step_order
        SQL
        template-tags = local.ga_date_tags
      }
    }
    display                = "table"
    visualization_settings = {
      "table.row_index" = true
      "table.paginate"  = true
    }
    parameter_mappings     = []
    parameters             = []
  })
}

# Traffic Mediums — bar chart: sessions by medium/channel
resource "metabase_card" "ga_traffic_mediums_bar" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Traffic Mediums"
    description         = "Sessions by traffic medium (organic, direct, referral, etc.)"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT session_medium, SUM(total_sessions) AS sessions FROM `${local.bq_dataset}.mart_ga_traffic_mediums` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]] GROUP BY session_medium ORDER BY sessions DESC"
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["session_medium"]
      "graph.metrics"    = ["sessions"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Traffic Mediums — table: full breakdown with source detail
resource "metabase_card" "ga_traffic_mediums_table" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Traffic Mediums (Detail)"
    description         = "Session counts by traffic medium and source"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT session_medium, session_source, SUM(total_sessions) AS sessions, SUM(total_users) AS users FROM `${local.bq_dataset}.mart_ga_traffic_mediums` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]] GROUP BY session_medium, session_source ORDER BY sessions DESC"
        template-tags = local.ga_date_tags
      }
    }
    display                = "table"
    visualization_settings = {
      "table.row_index" = true
      "table.paginate"  = true
    }
    parameter_mappings     = []
    parameters             = []
  })
}

# Clicked Links — bar chart: top outbound domains
resource "metabase_card" "ga_clicked_links_bar" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Clicked Links"
    description         = "Top outbound link domains clicked by users"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT link_domain, SUM(total_clicks) AS total_clicks FROM `${local.bq_dataset}.mart_ga_clicked_links` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) AND is_outbound = 'true' [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]] GROUP BY link_domain ORDER BY total_clicks DESC LIMIT 10"
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["link_domain"]
      "graph.metrics"    = ["total_clicks"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Clicked Links — table: full domain breakdown with click counts
resource "metabase_card" "ga_clicked_links_table" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Clicked Links (Detail)"
    description         = "Outbound link domains with click counts"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT link_domain, SUM(total_clicks) AS total_clicks FROM `${local.bq_dataset}.mart_ga_clicked_links` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) AND is_outbound = 'true' [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]] [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]] GROUP BY link_domain ORDER BY total_clicks DESC"
        template-tags = local.ga_date_tags
      }
    }
    display                = "table"
    visualization_settings = {
      "table.row_index" = true
      "table.paginate"  = true
    }
    parameter_mappings     = []
    parameters             = []
  })
}

# Last 7 Days Visitors — daily session counts per day as a bar chart
# No date_range filter here — this card is always scoped to the last 7 days.
resource "metabase_card" "ga_users_in_week" {
  for_each = local.ga_tenants_nc_only

  json = jsonencode({
    name                = "Last 7 Days Visitors"
    description         = "Daily session counts for the last 7 days"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = "SELECT event_date_parsed, SUM(total_sessions) AS sessions FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code IN (${local.tenant_ga_state_filter[each.key]}) AND event_date_parsed >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) GROUP BY event_date_parsed ORDER BY event_date_parsed ASC"
        template-tags = {}
      }
    }
    display                = "bar"
    visualization_settings = {
      "graph.dimensions" = ["event_date_parsed"]
      "graph.metrics"    = ["sessions"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ── Monthly Active Users chart ────────────────────────────────────────────────

resource "metabase_card" "tenant_monthly_active_users" {
  for_each = var.bigquery_enabled ? local.ga_tenants : {}

  json = jsonencode({
    name                = "What is the monthly active users (MAU) trend?"
    description         = "Distinct GA4 users per month from BigQuery page view events"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    display             = "bar"
    dataset_query = {
      type     = "native"
      database = tonumber(metabase_database.bigquery[0].id)
      native = {
        query = templatefile("${path.module}/sql/monthly_active_users.sql", {
          state_codes          = join(", ", [for code in lookup(local.tenant_ga_state_codes, each.key, [each.key]) : "'${code}'"])
          bq_internal_dataset  = "${var.gcp_project_id}.${var.bigquery_analytics_dataset}_internal"
        })
      }
    }
    visualization_settings = {
      "graph.dimensions"        = ["month"]
      "graph.metrics"           = ["active_users"]
      "graph.x_axis.title_text" = ""
      "graph.y_axis.title_text" = ""
      "graph.show_values"       = true
      "series_settings" = {
        "active_users" = { color = "#509EE3" }
      }
    }
    parameter_mappings = []
    parameters         = []
  })
}
# ── Dashboard layout for Google Analytics tab (tab ID 1) ──────────────────────
# Referenced by metabase_dashboard.tenant_analytics in metabase.tf via
# local.tenant_dashboard_ga_layout[each.key].
# Cards must be ordered by dashboard_tab_id then row ascending to avoid
# the provider "inconsistent result" error on cards_json round-trip comparison.

locals {
  _ga_start_date_param_id = "ga_start_date_filter"
  _ga_end_date_param_id   = "ga_end_date_filter"

  tenant_dashboard_ga_layout = {
    for key, tenant in var.tenants : key => (
      var.bigquery_enabled && contains(keys(local.ga_tenants_nc_only), key) ? [

        # Row 0: 4 KPI scalar cards side-by-side (each 6 wide × 3 tall)
        # (MAU chart moved to end of tab, below Last 7 Days Visitors)
        {
          card_id          = tonumber(metabase_card.ga_total_visitors[key].id)
          dashboard_tab_id = 1
          row              = 0
          col              = 0
          size_x           = 6
          size_y           = 3
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_total_visitors[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_total_visitors[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.ga_started_screener_pct[key].id)
          dashboard_tab_id = 1
          row              = 0
          col              = 6
          size_x           = 6
          size_y           = 3
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_started_screener_pct[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_started_screener_pct[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.ga_completed_to_click_rate[key].id)
          dashboard_tab_id = 1
          row              = 0
          col              = 12
          size_x           = 6
          size_y           = 3
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_completed_to_click_rate[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_completed_to_click_rate[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.ga_median_completion_time[key].id)
          dashboard_tab_id = 1
          row              = 0
          col              = 18
          size_x           = 6
          size_y           = 3
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_median_completion_time[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_median_completion_time[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },

        # Row 3: Conversion funnel (left, 12×6) + detail table (right)
        {
          card_id          = tonumber(metabase_card.ga_conversion_funnel[key].id)
          dashboard_tab_id = 1
          row              = 3
          col              = 0
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_conversion_funnel[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_conversion_funnel[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.ga_conversion_funnel_table[key].id)
          dashboard_tab_id = 1
          row              = 3
          col              = 12
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_conversion_funnel_table[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_conversion_funnel_table[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },

        # Row 9: Traffic Mediums — bar chart (left) + detail table (right)
        {
          card_id          = tonumber(metabase_card.ga_traffic_mediums_bar[key].id)
          dashboard_tab_id = 1
          row              = 9
          col              = 0
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_traffic_mediums_bar[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_traffic_mediums_bar[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.ga_traffic_mediums_table[key].id)
          dashboard_tab_id = 1
          row              = 9
          col              = 12
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_traffic_mediums_table[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_traffic_mediums_table[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },

        # Row 15: Clicked Links — bar chart (left) + detail table (right)
        {
          card_id          = tonumber(metabase_card.ga_clicked_links_bar[key].id)
          dashboard_tab_id = 1
          row              = 15
          col              = 0
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_clicked_links_bar[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_clicked_links_bar[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.ga_clicked_links_table[key].id)
          dashboard_tab_id = 1
          row              = 15
          col              = 12
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.ga_clicked_links_table[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.ga_clicked_links_table[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },

        # Row 21: Last 7 Days Visitors — no date filter (fixed 7-day window)
        {
          card_id                = tonumber(metabase_card.ga_users_in_week[key].id)
          dashboard_tab_id       = 1
          row                    = 21
          col                    = 0
          size_x                 = 24
          size_y                 = 6
          parameter_mappings     = []
          series                 = []
          visualization_settings = {}
        },

        # Row 27: MAU trend chart (full width, 24×8) — no date filter (monthly aggregation)
        {
          card_id                = tonumber(metabase_card.tenant_monthly_active_users[key].id)
          dashboard_tab_id       = 1
          row                    = 27
          col                    = 0
          size_x                 = 24
          size_y                 = 8
          parameter_mappings     = []
          series                 = []
          visualization_settings = {}
        },

      ] : (
        # Non-nc GA tenants: show only the MAU chart (other cards not yet enabled)
        var.bigquery_enabled && contains(keys(local.ga_tenants), key) ? [
          {
            card_id                = tonumber(metabase_card.tenant_monthly_active_users[key].id)
            dashboard_tab_id       = 1
            row                    = 0
            col                    = 0
            size_x                 = 24
            size_y                 = 8
            parameter_mappings     = []
            series                 = []
            visualization_settings = {}
          },
        ] : []
      )
    )
  }
}
