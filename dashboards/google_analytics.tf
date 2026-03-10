
# ─────────────────────────────────────────────────────────────────────────────
# Google Analytics tab cards — per-tenant, filtered by state_code
# All 9 cards use native BigQuery SQL so metrics are computed accurately
# across the full date range rather than averaging pre-aggregated daily rates.
# ─────────────────────────────────────────────────────────────────────────────

# KPI: Total Visitors — COUNT of distinct sessions
resource "metabase_card" "ga_total_visitors" {
  for_each = var.tenants

  json = jsonencode({
    name                = "Total Visitors"
    description         = "Total number of GA4 sessions"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
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
  for_each = var.tenants

  json = jsonencode({
    name                = "Started Screener"
    description         = "Percentage of sessions that started the screener (/step-1)"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
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
  for_each = var.tenants

  json = jsonencode({
    name                = "Completed to Click Rate"
    description         = "D/C ratio: % of completed screener sessions that also clicked an outbound link"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
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

# KPI: Completion Time — true median from session-grain data
# Uses APPROX_QUANTILES on int_ga4_sessions so the result is the actual p50 across all sessions,
# not an average of pre-aggregated daily medians which would vary with bucketing.
resource "metabase_card" "ga_median_completion_time" {
  for_each = var.tenants

  json = jsonencode({
    name                = "Median Completion Time"
    description         = "Median session duration from screener start (/step-1) to completion (/results)"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
      type     = "native"
      native = {
        query         = <<-SQL
          SELECT CONCAT(
            LPAD(CAST(DIV(secs, 3600)            AS STRING), 2, '0'), ':',
            LPAD(CAST(DIV(MOD(secs, 3600), 60)   AS STRING), 2, '0'), ':',
            LPAD(CAST(MOD(secs, 60)              AS STRING), 2, '0')
          )
          FROM (
            SELECT CAST(ROUND(
              APPROX_QUANTILES(completion_time_seconds, 100 IGNORE NULLS)[OFFSET(50)],
              0
            ) AS INT64) AS secs
            FROM `${local.bq_dataset}.int_ga4_sessions`
            WHERE state_code = '${local.tenant_ga_state_codes[each.key]}'
              AND completion_time_seconds IS NOT NULL
          )
        SQL
        template-tags = {}
      }
    }
    display                = "scalar"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

# Conversion Funnel — A→B→C→D step counts as a bar chart
# NOTE: display = "bar" is used here. The team can change to "funnel" in the Metabase UI
# since the data is pre-shaped as step rows; a funnel display may render better visually.
resource "metabase_card" "ga_conversion_funnel" {
  for_each = var.tenants

  json = jsonencode({
    name                = "Conversion Funnel"
    description         = "Session counts at each screener funnel step: A=Total, B=Started, C=Completed, D=Clicked"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
      type     = "native"
      native = {
        query         = <<-SQL
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
          ORDER BY step_order
        SQL
        template-tags = {}
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.x_axis.title_text"  = "Funnel Step"
      "graph.y_axis.title_text"  = "Sessions"
      "graph.dimensions"         = ["funnel_step"]
      "graph.metrics"            = ["session_count"]
    }
    parameter_mappings = []
    parameters         = []
  })
}
# Conversion Funnel — detail table: step-by-step breakdown with counts and percentages
resource "metabase_card" "ga_conversion_funnel_table" {
  for_each = var.tenants

  json = jsonencode({
    name                = "Conversion Funnel (Detail)"
    description         = "Step-by-step session counts and drop-off for the screener funnel"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
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
  for_each = var.tenants

  json = jsonencode({
    name                = "Traffic Mediums"
    description         = "Sessions by traffic medium (organic, direct, referral, etc.)"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
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
  for_each = var.tenants

  json = jsonencode({
    name                = "Traffic Mediums (Detail)"
    description         = "Session counts by traffic medium and source"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
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
  for_each = var.tenants

  json = jsonencode({
    name                = "Clicked Links"
    description         = "Top outbound link domains clicked by users"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
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
  for_each = var.tenants

  json = jsonencode({
    name                = "Clicked Links (Detail)"
    description         = "Outbound link domains with click, session, and user counts"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery.id)
      type     = "native"
      native = {
        query         = "SELECT link_domain, SUM(total_clicks) AS total_clicks, SUM(sessions_with_clicks) AS sessions, SUM(users_with_clicks) AS users FROM `${local.bq_dataset}.mart_ga_clicked_links` WHERE state_code = '${local.tenant_ga_state_codes[each.key]}' AND is_outbound = 'true' GROUP BY link_domain ORDER BY total_clicks DESC"
        template-tags = {}
      }
    }
    display                = "table"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}
