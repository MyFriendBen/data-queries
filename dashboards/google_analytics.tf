
# ─────────────────────────────────────────────────────────────────────────────
# Google Analytics tab cards — per-tenant, filtered by state_code
# All 11 cards use native BigQuery SQL so metrics are computed accurately
# across the full date range rather than averaging pre-aggregated daily rates.
# ─────────────────────────────────────────────────────────────────────────────

# Dashboard card layout for the Google Analytics tab (tab ID 1).
# Referenced by metabase_dashboard.tenant_analytics in metabase.tf via
# local.ga_dashboard_cards[each.key]. Kept here so all GA concerns
# (cards + layout) live in one file.
locals {
  ga_dashboard_cards = var.bigquery_enabled ? {
    for key in keys(var.tenants) : key => [
      # Row 0: 4 KPI scalar cards side-by-side (each 6 wide × 3 tall)
      {
        card_id                = tonumber(metabase_card.ga_total_visitors[key].id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 0
        size_x                 = 6
        size_y                 = 3
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.ga_started_screener_pct[key].id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 6
        size_x                 = 6
        size_y                 = 3
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.ga_completed_to_click_rate[key].id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 12
        size_x                 = 6
        size_y                 = 3
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.ga_median_completion_time[key].id)
        dashboard_tab_id       = 1
        row                    = 0
        col                    = 18
        size_x                 = 6
        size_y                 = 3
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },

      # Row 3: Conversion funnel bar chart (left, 12 wide × 6 tall) + detail table (right)
      {
        card_id                = tonumber(metabase_card.ga_conversion_funnel[key].id)
        dashboard_tab_id       = 1
        row                    = 3
        col                    = 0
        size_x                 = 12
        size_y                 = 6
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.ga_conversion_funnel_table[key].id)
        dashboard_tab_id       = 1
        row                    = 3
        col                    = 12
        size_x                 = 12
        size_y                 = 6
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },

      # Row 9: Traffic Mediums — bar chart (left) + detail table (right)
      {
        card_id                = tonumber(metabase_card.ga_traffic_mediums_bar[key].id)
        dashboard_tab_id       = 1
        row                    = 9
        col                    = 0
        size_x                 = 12
        size_y                 = 6
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.ga_traffic_mediums_table[key].id)
        dashboard_tab_id       = 1
        row                    = 9
        col                    = 12
        size_x                 = 12
        size_y                 = 6
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },

      # Row 15: Clicked Links — bar chart (left) + detail table (right)
      {
        card_id                = tonumber(metabase_card.ga_clicked_links_bar[key].id)
        dashboard_tab_id       = 1
        row                    = 15
        col                    = 0
        size_x                 = 12
        size_y                 = 6
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },
      {
        card_id                = tonumber(metabase_card.ga_clicked_links_table[key].id)
        dashboard_tab_id       = 1
        row                    = 15
        col                    = 12
        size_x                 = 12
        size_y                 = 6
        parameter_mappings     = []
        series                 = []
        visualization_settings = {}
      },

      # Row 21: Last 7 Days Visitors — daily session bar chart (full width)
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
    ]
  } : {}
}


# KPI: Total Visitors — SUM of daily session counts from mart_ga_kpi_summary
resource "metabase_card" "ga_total_visitors" {
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT SUM(total_sessions) FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'"
        template-tags = {}
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
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT CONCAT(CAST(ROUND(SUM(sessions_started_screener) * 100.0 / NULLIF(SUM(total_sessions), 0), 1) AS STRING), '%') FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'"
        template-tags = {}
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
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT CONCAT(CAST(ROUND(SUM(sessions_clicked_after_completion) * 100.0 / NULLIF(SUM(sessions_completed_screener), 0), 1) AS STRING), '%') FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'"
        template-tags = {}
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
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT CONCAT(LPAD(CAST(DIV(secs, 3600) AS STRING), 2, '0'), ':', LPAD(CAST(DIV(MOD(secs, 3600), 60) AS STRING), 2, '0'), ':', LPAD(CAST(MOD(secs, 60) AS STRING), 2, '0')) FROM (SELECT CAST(ROUND(AVG(median_completion_time_seconds), 0) AS INT64) AS secs FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}' AND median_completion_time_seconds IS NOT NULL)"
        template-tags = {}
      }
    }
    display                = "scalar"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

# Last 7 days Visitors — daily session counts per day as a bar chart
resource "metabase_card" "ga_users_in_week" {
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT event_date_parsed, SUM(total_sessions) AS sessions FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}' AND event_date_parsed >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) GROUP BY event_date_parsed ORDER BY event_date_parsed ASC"
        template-tags = {}
      }
    }
    display                = "bar"
    visualization_settings = {
      "graph.dimensions"   = ["event_date_parsed"]
      "graph.metrics"      = ["sessions"]
    }
    parameter_mappings     = []
    parameters             = []
  })
}

# Conversion Funnel — A→B→C→D step counts as a funnel chart
# display = "funnel" works because the data is pre-shaped as ordered step rows
# (funnel_step, session_count, step_order). The bar display is also compatible
# if the team prefers it — just change display to "bar" and restore visualization_settings.
resource "metabase_card" "ga_conversion_funnel" {
  for_each = var.bigquery_enabled ? var.tenants : {}

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
            FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'
            UNION ALL
            SELECT 'Started Screener', SUM(sessions_started_screener), 2
            FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'
            UNION ALL
            SELECT 'Completed Screener', SUM(sessions_completed_screener), 3
            FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'
            UNION ALL
            SELECT 'Clicked Link', SUM(sessions_clicked_after_completion), 4
            FROM `${local.bq_dataset}.mart_ga_kpi_summary` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'
          )
          ORDER BY step_order
        SQL
        template-tags = {}
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
  for_each = var.bigquery_enabled ? var.tenants : {}

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
            WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'
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
        template-tags = {}
      }
    }
    display                = "table"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

# Traffic Mediums — bar chart: sessions by medium/channel
resource "metabase_card" "ga_traffic_mediums_bar" {
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT session_medium, SUM(total_sessions) AS sessions FROM `${local.bq_dataset}.mart_ga_traffic_mediums` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}' GROUP BY session_medium ORDER BY sessions DESC"
        template-tags = {}
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
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT session_medium, session_source, SUM(total_sessions) AS sessions, SUM(total_users) AS users FROM `${local.bq_dataset}.mart_ga_traffic_mediums` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}' GROUP BY session_medium, session_source ORDER BY sessions DESC"
        template-tags = {}
      }
    }
    display                = "table"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

# Clicked Links — bar chart: top outbound domains
resource "metabase_card" "ga_clicked_links_bar" {
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT link_domain, SUM(total_clicks) AS total_clicks FROM `${local.bq_dataset}.mart_ga_clicked_links` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}' AND is_outbound = 'true' GROUP BY link_domain ORDER BY total_clicks DESC LIMIT 10"
        template-tags = {}
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

# Clicked Links — table: full domain breakdown with session/user counts
resource "metabase_card" "ga_clicked_links_table" {
  for_each = var.bigquery_enabled ? var.tenants : {}

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
        query         = "SELECT link_domain, SUM(total_clicks) AS total_clicks FROM `${local.bq_dataset}.mart_ga_clicked_links` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}' AND is_outbound = 'true' GROUP BY link_domain ORDER BY total_clicks DESC"
        template-tags = {}
      }
    }
    display                = "table"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}
