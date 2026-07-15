# Global (all-states) versions of the 16 screener analytics cards.
#
# These are SINGLE-INSTANCE cards (no for_each) that live in the Global
# collection and query ALL states. They consume the SAME shared SQL bodies as
# the per-tenant cards (locals in screener_analytics_sql.tf); the ONLY difference
# is the state predicate substitution — filtered to the full set of valid
# lowercase state codes (NOT a bare 1=1) so legacy DOM-scrape rows (display-name
# state) and null-state landing rows don't contaminate the all-states totals:
#   __STATE_FILTER__     -> "screener_state IN (${local.all_screener_state_filter})"
#   __STATE_FILTER_KPI__ -> "state_code IN (${local.all_screener_state_filter})"  (macro funnel only)
#
# name / description / display / visualization_settings / template-tags are
# identical to the tenant versions in screener_analytics.tf. Placed on the
# Global dashboard (metabase.tf, metabase_dashboard.analytics) tabs 4-7.

# ══════════════════════════════════════════════════════════════════════════════
# Tab 4 (Engagement Overview) — Macro funnel + language distribution
# ══════════════════════════════════════════════════════════════════════════════

resource "metabase_card" "global_screener_macro_funnel" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Screener Macro Funnel"
    description         = "Visitors -> Started -> Saw Results -> Clicked More Info -> Clicked Apply. Note: Visitors/Started are counted per browsing session; Saw Results and later are counted per screening (a screening ID isn't created until step 3). Read stage-to-stage conversion as directional, not an exact ratio."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_macro_funnel, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["Funnel Step"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_language_distribution" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Language Distribution"
    description         = "Distinct screenings by language (language changes)"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_language_distribution, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["language_name"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# Tab 5 (Form Journey)
# ══════════════════════════════════════════════════════════════════════════════

resource "metabase_card" "global_screener_step_funnel" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Form Step Drop-off Funnel"
    description         = "Distinct screenings that viewed each screener step, in flow order (by step number; null-numbered pages sort last)"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_step_funnel, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["screener_step_label"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_errors_by_step" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Form Errors by Step"
    description         = "Total form validation errors recorded at each screener step"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_errors_by_step, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["screener_step_label"]
      "graph.metrics"    = ["Total Errors"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_back_nav_by_step" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Back Navigation by Step"
    description         = "Distinct screenings that navigated back from each screener step"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_back_nav_by_step, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["screener_step_label"]
      "graph.metrics"    = ["Screenings (Back-Nav)"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# Tab 6 (Results Page Activity)
# ══════════════════════════════════════════════════════════════════════════════

resource "metabase_card" "global_screener_results_outcome_kpis" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Results Outcome KPIs"
    description         = "Results viewed, none-eligible count/%, avg programs found, avg estimated value, results errors"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_results_outcome_kpis, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "table"
    visualization_settings = {
      "table.row_index" = false
      "table.paginate"  = false
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_apply_conversion_rate" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Apply Conversion Rate by Program"
    description         = "apply / more_info conversion rate per program (screenings basis), highest first"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_apply_conversion_rate, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Program"]
      "graph.metrics"    = ["Apply Rate %"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_more_info_vs_apply" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "More Info vs Apply by Program"
    description         = "Distinct screenings clicking more-info vs apply per program, sorted by the gap"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_more_info_vs_apply, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Program"]
      "graph.metrics"    = ["More Info", "Apply"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_more_info_apply_scatter" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "More Info vs Apply (Scatter)"
    description         = "Per-program scatter of distinct more-info screenings (x) against apply screenings (y)"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_more_info_apply_scatter, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scatter"
    visualization_settings = {
      "graph.dimensions" = ["More Info"]
      "graph.metrics"    = ["Apply"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_tab_split" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Results Tab Split"
    description         = "Distinct screenings opening each results-page tab (long-term benefits vs additional resources)"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_tab_split, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Tab"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_top_resources" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Top Additional Resources"
    description         = "Top 20 additional resources clicked on the results page, by total clicks"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_top_resources, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Resource"]
      "graph.metrics"    = ["Clicks"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# Tab 7 (Sharing & Saving)
# ══════════════════════════════════════════════════════════════════════════════

resource "metabase_card" "global_screener_share_funnel_popup" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Share Funnel — Popup"
    description         = "Popup share funnel: distinct screenings that opened vs sent a share"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_share_funnel_popup, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["Funnel Step"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_share_funnel_footer" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Share Funnel — Footer"
    description         = "Footer share funnel: distinct screenings that opened vs sent a share"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_share_funnel_footer, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["Funnel Step"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_shares_by_channel" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Shares by Channel"
    description         = "Total shares by channel (and provider, e.g. email provider)"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_shares_by_channel, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Share Channel"]
      "graph.metrics"    = ["Total Shares"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_save_funnel" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Save Funnel"
    description         = "Popup impressions vs distinct screenings that engaged the save-results modal. Note: 'Saved' counts any save_action (open/send/close/back) — i.e. modal engagement, not only completed sends."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_save_funnel, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["Funnel Step"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_saves_by_channel" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Saves by Channel"
    description         = "Total results-saves by channel"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_saves_by_channel, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Save Channel"]
      "graph.metrics"    = ["Total Saves"]
    }
    parameter_mappings = []
    parameters         = []
  })
}
