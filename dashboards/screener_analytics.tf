# Cards for the screener analytics tabs, powered by the GTM->GA4 relay marts:
#   mart_screener_form_funnel, mart_screener_program_interactions,
#   mart_screener_results_outcomes, mart_screener_shares, mart_screener_saves.
#
# These cards intentionally mirror dashboards/google_analytics.tf exactly:
#   - for_each = local.ga_tenants_enabled (tenants with >=1 screener tab enabled;
#     see google_analytics.tf)
#   - tenant state filter via local.tenant_ga_state_filter[each.key], BUT the new
#     marts use column `screener_state` (NOT `state_code` like the GA marts)
#   - date template-tags via local.ga_date_tags + the bracketed date predicates
#   - database = metabase_database.bigquery[0].id, dataset = local.bq_dataset
#   - collection_id = local.tenant_collection_map[each.key].id
#
# Cards live across four dashboard areas:
#   Tab 10 (Overview)               — macro funnel + language distribution
#   Tab 7 (Form Journey)            — step drop-off funnel, errors, back-nav
#   Tab 8 (Results)                 — apply/more-info conversion, outcome KPIs
#   Tab 9 (Sharing & Saving)        — share and save funnels

# ══════════════════════════════════════════════════════════════════════════════
# Tab 10 (Overview) — Macro funnel
# ══════════════════════════════════════════════════════════════════════════════

# Macro funnel — 4 ordered stages assembled with UNION ALL across the screener
# event marts, mirroring the ga_conversion_funnel ordered-rows pattern:
#   Started          — distinct sessions that hit the synthetic __form_start__
#                      step in mart_screener_form_funnel
#   Saw Results      — screenings_results_loaded from mart_screener_results_outcomes
#   Clicked More Info— distinct screenings with a more_info interaction
#   Clicked Apply    — distinct screenings with an apply interaction
#
# ⚠️ MIXED DEDUP KEYS across stages — not a strictly apples-to-apples ratio:
#   Started is deduped on the GA4 SESSION key (screener_uid is null before step 3,
#   so a session key is used); Saw Results / More Info / Apply dedupe on
#   screener_uid (which exists from step 3). So the Started→Saw Results transition
#   changes denominators (sessions → screenings). Treat stage-to-stage conversion
#   as directional, not exact — noted in the card description.
resource "metabase_card" "screener_macro_funnel" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Screener Macro Funnel"
    description         = "Started -> Saw Results -> Clicked More Info -> Clicked Apply. Started is counted per browsing session; Saw Results and later are counted per screening (a screening ID isn't created until step 3), so read stage-to-stage conversion as directional, not an exact ratio."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_macro_funnel, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
        "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# ══════════════════════════════════════════════════════════════════════════════
# Tab 7 (Form Journey)
# ══════════════════════════════════════════════════════════════════════════════

# Monotonic "furthest step reached" funnel from mart_screener_furthest_step.
# Each bar = distinct sessions that got AT LEAST this far, so the funnel can only
# shrink down the ladder. Referral Source and Select State are excluded from the
# ladder (conditionally shown / pre-white-label — a skip would read as drop-off).
resource "metabase_card" "screener_step_funnel" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Form Step Reached"
    description         = "Share of screening sessions that reached at least each step, in flow order through the results page. Monotonic: each bar counts every session that got this far or further, so it always decreases down the funnel. Hover a bar for the raw session count. Referral Source and Select State are excluded (conditionally shown / pre-white-label)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_step_funnel, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"        = ["screener_step_label"]
      "graph.metrics"           = ["% of Started"]
      "graph.show_values"       = true
      "graph.x_axis.title_text" = "Screener Step"
      "series_settings"         = { "% of Started" = { color = "#4e79a7" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Errors by step — horizontal bar. Raw error count is the bar; hover shows the
# error rate (errors / step views) now that every step has a clean view count.
resource "metabase_card" "screener_errors_by_step" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Form Errors by Step"
    description         = "Of the screenings that viewed each step, the % that hit at least one validation error on it — normalized for traffic so steps are comparable by how error-prone they are. Hover for the raw screening count and total error events (attempts, inflated by retries)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_errors_by_step, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"        = ["Step"]
      "graph.metrics"           = ["% of Viewers with 1+ Errors"]
      "graph.show_values"       = true
      "graph.x_axis.title_text" = "Screener Step"
      "series_settings"         = { "% of Viewers with 1+ Errors" = { color = "#d64550" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Back-navigation by step — horizontal bar (distinct screenings that navigated
# back). Bar is the raw count; hover shows it as a % of the step's views.
resource "metabase_card" "screener_back_nav_by_step" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Back Navigation by Step"
    description         = "Of the screenings that viewed each step, the % that navigated back from it — normalized for traffic so steps are comparable by how often they send people back. Hover for the raw back-navigation count."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_back_nav_by_step, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"        = ["Step"]
      "graph.metrics"           = ["% of Viewers who Went Back"]
      "graph.show_values"       = true
      "graph.x_axis.title_text" = "Screener Step"
      "series_settings"         = { "% of Viewers who Went Back" = { color = "#59a14f" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# Tab 8 (Results)
# ══════════════════════════════════════════════════════════════════════════════

# HEADLINER: apply conversion rate per program = apply / more_info, sorted desc.
# Pivots interaction_type in mart_screener_program_interactions with conditional
# SUMs, grouping by program_id (the stable key) and carrying program_name as the
# display label (MAX, matching the mart's own display-label convention).
resource "metabase_card" "screener_apply_conversion_rate" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Apply Conversion Rate by Program"
    description         = "apply / more_info conversion rate per program (screenings basis), highest first"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_apply_conversion_rate, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.max_categories_enabled" = false
      "graph.show_values"            = true
      "graph.dimensions"             = ["Program"]
      "graph.metrics"                = ["Apply Rate %"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Paired/grouped bar per program: more_info and apply side by side, sorted by the
# gap (more_info - apply) descending — surfaces the programs with the biggest
# interest-to-action drop-off.
resource "metabase_card" "screener_more_info_vs_apply" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "More Info vs Apply by Program"
    description         = "Distinct screenings clicking more-info vs apply per program, sorted by the gap"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_more_info_vs_apply, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.max_categories_enabled" = false
      "graph.show_values"            = true
      "graph.dimensions"             = ["Program"]
      "graph.metrics"                = ["More Info", "Apply"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Results revisits — bar. How many screenings loaded their results page once vs.
# multiple times (1 / 2 / 3+), a proxy for how often people return to a saved
# result. From mart_screener_results_revisits (one row per screening, lifetime
# load count), bucketed and counted.
resource "metabase_card" "screener_results_revisits" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Results Views per Screening"
    description         = "How many screenings loaded their results page once, twice, or 3+ times — a proxy for returning to a saved result. Counted per screening; the date filter selects screenings by their first results view."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_results_revisits, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.show_values"       = true
      "graph.dimensions"        = ["Times Viewed"]
      "graph.metrics"           = ["Screenings"]
      "graph.x_axis.title_text" = "Times Results Viewed"
      "graph.y_axis.decimals"   = 0
      "series_settings"         = { "Screenings" = { color = "#af7aa1" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Results outcome KPIs — single table of the outcome scalars, mirroring the GA
# funnel-detail table pattern (one native query, ordered rows). Kept as one card
# rather than many tiles to avoid re-querying the mart per tile.
#   results viewed, none-eligible count + %, avg program_count,
#   avg total_estimated_value, results errors.
resource "metabase_card" "screener_results_outcome_kpis" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Results Outcome KPIs"
    description         = "Results viewed, none-eligible count/%, avg programs found, avg estimated value, results errors"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_results_outcome_kpis, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# ══════════════════════════════════════════════════════════════════════════════
# Tab 9 (Sharing & Saving)
# ══════════════════════════════════════════════════════════════════════════════

# Share funnel — Popup location: open -> send.
# mart_screener_shares has (share_location, share_channel, share_provider,
# share_action). The share funnel is open -> send within a share_location.
# NOTE: assumes share_action values 'open' and 'send' (open->send is the design's
# stated funnel). If the relay emits different action labels these predicates need
# updating
resource "metabase_card" "screener_share_funnel_popup" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Share Funnel — Popup"
    description         = "Popup share funnel: distinct screenings that opened vs sent a share"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_share_funnel_popup, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# Share funnel — Footer location: open -> send.
resource "metabase_card" "screener_share_funnel_footer" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Share Funnel — Footer"
    description         = "Footer share funnel: distinct screenings that opened vs sent a share"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_share_funnel_footer, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# Shares by channel — bar. share_provider (email provider etc.) is carried in the
# mart and shown in the detail via the channel/provider grouping.
resource "metabase_card" "screener_shares_by_channel" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Shares by Channel"
    description         = "Total shares by channel (and provider, e.g. email provider)"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_shares_by_channel, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"      = ["Share Channel"]
      "graph.metrics"         = ["Total Shares"]
      "graph.y_axis.decimals" = 0
      "series_settings"       = { "Total Shares" = { color = "#76b7b2" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Save funnel — popup shown -> saved. mart_screener_saves carries both the
# popup-impression counts (screenings_shown_popup) and the save counts
# (screenings_with_save, keyed by save_channel/save_action).
# NOTE: the save funnel denominator is the share-popup impression (the mart pairs
# these two on date+state); numerator is distinct screenings that saved. This is
# an approximation of a true per-screening funnel since the two events are joined
# at day/state grain, not per screening
resource "metabase_card" "screener_save_funnel" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Save Funnel"
    description         = "Popup impressions vs distinct screenings that engaged the save-results modal. Note: 'Saved' counts any save_action (open/send/close/back) — i.e. modal engagement, not only completed sends."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_save_funnel, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# Saves by channel — bar.
resource "metabase_card" "screener_saves_by_channel" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Saves by Channel"
    description         = "Total results-saves by channel"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_saves_by_channel, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"      = ["Save Channel"]
      "graph.metrics"         = ["Total Saves"]
      "graph.y_axis.decimals" = 0
      "series_settings"       = { "Total Saves" = { color = "#ff9da7" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Results-page tab split — bar. Tab opens on the results page:
# long_term_benefits vs additional_resources, from
# mart_screener_resource_engagement (metric = 'tab_open').
resource "metabase_card" "screener_tab_split" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Results Tab Engagement"
    description         = "% of results-page viewers who opened each results tab (denominator = screenings that loaded results). Long-Term Benefits is the default tab (~100%); the signal is the Additional Resources rate."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_tab_split, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Tab"]
      "graph.metrics"    = ["% of Results Viewers"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Top Additional Resources clicked — bar. Same mart (metric = 'resource_click'),
# top 20 resources by total clicks.
resource "metabase_card" "screener_top_resources" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Top Additional Resources"
    description         = "Top 20 additional resources clicked on the results page, by total clicks"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_top_resources, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.max_categories_enabled" = false
      "graph.show_values"            = true
      "graph.dimensions"             = ["Resource"]
      "graph.metrics"                = ["Clicks"]
      "graph.y_axis.decimals"        = 0
      "series_settings"              = { "Clicks" = { color = "#9c755f" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# Analytics v2 cards — new event families
# ══════════════════════════════════════════════════════════════════════════════

# Per-program conversion — table. Two conversion rates (more-info / shown and
# apply / more-info) alongside the raw counts; multi-metric rates read best as a
# table.
resource "metabase_card" "screener_program_conversion" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Program Conversion"
    description         = "Per-program funnel: shown, more-info, and applied counts with the more-info and apply conversion rates, highest more-info rate first."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_program_conversion, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# Navigator engagement — table. Program x navigator x contact method with the
# distinct-screening count.
resource "metabase_card" "screener_navigator_engagement" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Navigator Engagement"
    description         = "Distinct screenings that engaged a navigator, broken out by program, navigator, and contact method."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_navigator_engagement, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# Additional-resource engagement — horizontal bar. Per resource, the expand
# (more-info) count and contact clicks split by website vs phone.
resource "metabase_card" "screener_resource_engagement" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Additional Resource Engagement"
    description         = "Per additional resource: more-info expands and contact clicks split by website vs phone, top 20 by more-info."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_resource_engagement, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.max_categories_enabled" = false
      "graph.show_values"            = true
      "graph.dimensions"             = ["Resource"]
      "graph.metrics"                = ["More Info", "Website", "Phone"]
      "graph.y_axis.decimals"        = 0
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Additional Resources tab engagement — table. Count of screenings that opened
# the tab plus that count as a share of results viewers (single row).
resource "metabase_card" "screener_resources_tab_engagement" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Additional Resources Tab Engagement"
    description         = "Screenings that opened the Additional Resources tab and that count as a percentage of results-page viewers."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_resources_tab_engagement, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
        "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# Results scroll depth — bar. How far screenings scroll on the results page,
# split by tab.
resource "metabase_card" "screener_scroll_depth" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Results Scroll Depth"
    description         = "Of the screenings that scrolled a results tab, how far the deepest scroll got (each screening counted once, in its furthest bucket). Bars are the % of that tab's scrollers; hover for the raw count. Split by tab."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_scroll_depth, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      # % is the bar (a multi-series tooltip can't surface a side column). Depth
      # labels are numeric-prefixed so the alphabetical axis sort stays Quarter->Full.
      "graph.dimensions"  = ["Depth", "Tab"]
      "graph.metrics"     = ["% of Tab Scrollers"]
      "graph.show_values" = true
      "series_settings" = {
        "Long-Term Benefits"   = { color = "#4e79a7" }
        "Additional Resources" = { color = "#59a14f" }
      }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Help clicks by topic — horizontal bar. Which help tooltips drive the most
# clicks. The click event carries only the help topic (no step), so this slices
# by topic alone.
resource "metabase_card" "screener_help_by_topic" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Help Clicks by Topic"
    description         = "Help-tooltip clicks by help topic, surfacing which tooltips drive the most confusion. The click event carries only the topic (which is itself step-identifying), so there is no step breakdown."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_help_by_topic, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.max_categories_enabled" = false
      "graph.show_values"            = true
      "graph.dimensions"             = ["Help Topic"]
      "graph.metrics"                = ["Clicks"]
      "series_settings"              = { "Clicks" = { color = "#e8a33d" } }
      # Clicks are whole numbers; force integer axis ticks so a max of 2 doesn't
      # auto-scale to 0.2/0.4/... gridlines.
      "graph.y_axis.decimals" = 0
      "column_settings"       = { "[\"name\",\"Clicks\"]" = { number_style = "decimal", decimals = 0 } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Household-member add/edit/delete actions.
resource "metabase_card" "screener_household_member_engagement" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Household Member Actions"
    description         = "Of the screenings that reached the member step, the % that added, edited, or deleted a member. Hover for the raw screening count and total action events."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_household_member_engagement, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Action"]
      "graph.metrics"     = ["% of Household-Step Viewers"]
      "graph.show_values" = true
      "series_settings"   = { "% of Household-Step Viewers" = { color = "#499894" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Income-source add/delete actions.
resource "metabase_card" "screener_income_source_engagement" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Income Source Actions"
    description         = "Total add/edit/delete actions on income sources, and the number of distinct screenings doing each."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_income_source_engagement, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Action"]
      "graph.metrics"     = ["Total Actions"]
      "graph.show_values" = true
      "series_settings"   = { "Total Actions" = { color = "#d37295" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Get-help clicks — single number. Total clicks on the "More Help / 211" CTA.
resource "metabase_card" "screener_get_help_clicks" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "More Help Clicks"
    description         = "Total clicks on the More Help / 211 call-to-action from the results page."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_get_help_clicks, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field" = "More Help Clicks"
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Validation errors detail — table. Which specific validation messages fire, by
# step.
resource "metabase_card" "screener_errors_detail" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Validation Errors Detail"
    description         = "Which fields fail validation and why, by screener step, ordered by error count. Field and Problem are humanized from the PII-safe error code; counts are consolidated across repeated fields (e.g. all income rows roll up to Income)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_errors_detail, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# NOTE: "Header Language Switches" is GLOBAL-only — language-change events fire
# without screener_state, so it can't be attributed per tenant (see the FE gaps
# ticket). The card lives in screener_analytics_global.tf.

# ── Previously-untracked screener_* events ──────────────────────────────────────

# Confirmation-page edits by section — horizontal (row) bar. Row layout keeps
# section labels readable as more sections accumulate over time.
resource "metabase_card" "screener_confirmation_edits" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Confirmation Edits by Section"
    description         = "Of the screenings that reached the confirmation page, the % that went back to edit each section before submitting. Hover for the raw screening count."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_confirmation_edits, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions" = ["Section"]
      "graph.metrics"    = ["% of Confirmation Viewers"]
      "series_settings"  = { "% of Confirmation Viewers" = { color = "#4e79a7" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Sign-up consent opt-in rates — bar. Of completed sign-ups, the % opting into SMS
# vs email contact.
resource "metabase_card" "screener_signup_consent" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Sign-up Consent Rates"
    description         = "Of screenings that completed sign-up, the % opting into SMS vs email contact. Hover for the opt-in count."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_signup_consent, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Channel"]
      "graph.metrics"     = ["% Opted In"]
      "graph.show_values" = true
      "series_settings"   = { "% Opted In" = { color = "#59a14f" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Citizenship filter usage — scalar. Distinct screenings that engaged the results
# citizenship filter (chosen option not captured — PII).
resource "metabase_card" "screener_filter_usage" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Citizenship Filter Usage"
    description         = "Distinct screenings that used the results citizenship filter. The chosen option isn't captured, so this is a yes/no engagement count."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_filter_usage, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field" = "Filtered Screenings"
    }
    parameter_mappings = []
    parameters         = []
  })
}

# NPS distribution — bar. Submitted NPS scores bucketed Detractor / Passive /
# Promoter.
resource "metabase_card" "screener_nps_distribution" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "NPS Score Distribution"
    description         = "Submitted results-page NPS scores, bucketed Detractor (0-6), Passive (7-8), Promoter (9-10)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_nps_distribution, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"      = ["Category"]
      "graph.metrics"         = ["Responses"]
      "graph.y_axis.decimals" = 0
      "series_settings"       = { "Responses" = { color = "#af7aa1" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# NOTE: the footer / site-chrome cards (chrome nav, social, feedback & share) are
# GLOBAL-only — site chrome fires without screener_state, so it can't be attributed
# per tenant. They live in screener_analytics_global.tf. Per-tenant versions are
# blocked on the FE attaching state (see the FE gaps ticket).

# Public Charge link click rate — scalar. % of Disclaimer-step viewers who clicked
# the Public Charge link. Raw click count as the scalar's secondary value.
resource "metabase_card" "screener_public_charge_click_rate" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Public Charge Link — Click Rate"
    description         = "Of the sessions that viewed the Disclaimer step, the % that clicked the Public Charge info link."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_public_charge_click_rate, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field"    = "% of Disclaimer Viewers"
      "column_settings" = { "[\"name\",\"% of Disclaimer Viewers\"]" = { suffix = "%" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}


# Additional Resources edits — scalar. Clicks on the results-page "edit your
# selections" link that sends people back to the Additional Resources step.
resource "metabase_card" "screener_additional_resources_edits" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Additional Resources Edits (from Results)"
    description         = "Clicks on the results-page link that sends people back to the Additional Resources step to change their selections. Distinct from confirmation-page edits."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_additional_resources_edits, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field" = "Additional Resource Edits"
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ══════════════════════════════════════════════════════════════════════════════
# Dashboard layouts
# ══════════════════════════════════════════════════════════════════════════════
# Each layout local is a per-tenant list of dashcards keyed by dashboard_tab_id,
# mirroring the other screener layout locals. They are concatenated into
# metabase_dashboard.tenant_analytics.cards_json in metabase.tf. All date-filtered
# cards map the shared ga_start_date_filter / ga_end_date_filter parameters onto
# their start_date / end_date template-tags, exactly like the GA layout.
#
# Cards must be ordered by dashboard_tab_id then row ascending to avoid the
# provider "inconsistent result" error on cards_json round-trip comparison.

locals {
  # Reuse the shared date param ids (defined in google_analytics.tf as
  # local._ga_start_date_param_id / _ga_end_date_param_id).

  # Overview tab (tab id 10): macro funnel at the top, language distribution below.
  tenant_dashboard_screener_overview_layout = {
    for key, tenant in var.tenants : key => (
      var.bigquery_enabled && contains(keys(local.ga_tenants_enabled), key) ? [
        {
          card_id          = tonumber(metabase_card.screener_macro_funnel[key].id)
          dashboard_tab_id = 10
          row              = 0
          col              = 0
          size_x           = 24
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_macro_funnel[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_macro_funnel[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : []
    )
  }

  # Tab 7: Form Journey
  tenant_dashboard_screener_form_journey_layout = {
    for key, tenant in var.tenants : key => (
      var.bigquery_enabled && contains(keys(local.ga_tenants_enabled), key) ? [
        {
          card_id          = tonumber(metabase_card.screener_step_funnel[key].id)
          dashboard_tab_id = 7
          row              = 0
          col              = 0
          size_x           = 24
          size_y           = 12
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_step_funnel[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_step_funnel[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # Errors full-width; Back Nav + Help Clicks share the row below it.
          card_id          = tonumber(metabase_card.screener_errors_by_step[key].id)
          dashboard_tab_id = 7
          row              = 16
          col              = 0
          size_x           = 24
          size_y           = 9
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_errors_by_step[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_errors_by_step[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_back_nav_by_step[key].id)
          dashboard_tab_id = 7
          row              = 25
          col              = 0
          size_x           = 12
          size_y           = 9
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_back_nav_by_step[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_back_nav_by_step[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_help_by_topic[key].id)
          dashboard_tab_id = 7
          row              = 25
          col              = 12
          size_x           = 12
          size_y           = 9
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_help_by_topic[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_help_by_topic[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_errors_detail[key].id)
          dashboard_tab_id = 7
          row              = 34
          col              = 0
          size_x           = 24
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_errors_detail[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_errors_detail[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_household_member_engagement[key].id)
          dashboard_tab_id = 7
          row              = 42
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_household_member_engagement[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_household_member_engagement[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_income_source_engagement[key].id)
          dashboard_tab_id = 7
          row              = 42
          col              = 12
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_income_source_engagement[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_income_source_engagement[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # confirmation-page edits by section
          card_id          = tonumber(metabase_card.screener_confirmation_edits[key].id)
          dashboard_tab_id = 7
          row              = 50
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_confirmation_edits[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_confirmation_edits[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # sign-up consent opt-in rates
          card_id          = tonumber(metabase_card.screener_signup_consent[key].id)
          dashboard_tab_id = 7
          row              = 50
          col              = 12
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_signup_consent[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_signup_consent[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # in-step content-link click rates — per-step engagement, so on this tab
          card_id          = tonumber(metabase_card.screener_public_charge_click_rate[key].id)
          dashboard_tab_id = 7
          row              = 58
          col              = 0
          size_x           = 6
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_public_charge_click_rate[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_public_charge_click_rate[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : []
    )
  }

  # Tab 8: Results
  tenant_dashboard_screener_results_layout = {
    for key, tenant in var.tenants : key => (
      var.bigquery_enabled && contains(keys(local.ga_tenants_enabled), key) ? [
        {
          # ── (1) OVERVIEW ──
          card_id          = tonumber(metabase_card.screener_results_outcome_kpis[key].id)
          dashboard_tab_id = 8
          row              = 2
          col              = 0
          size_x           = 24
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_results_outcome_kpis[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_results_outcome_kpis[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_results_revisits[key].id)
          dashboard_tab_id = 8
          row              = 6
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_results_revisits[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_results_revisits[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_scroll_depth[key].id)
          dashboard_tab_id = 8
          row              = 6
          col              = 12
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_scroll_depth[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_scroll_depth[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # ── (2) PROGRAMS (eligible-programs list + CTAs) ──
          card_id          = tonumber(metabase_card.screener_program_conversion[key].id)
          dashboard_tab_id = 8
          row              = 14
          col              = 0
          size_x           = 24
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_program_conversion[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_program_conversion[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_more_info_vs_apply[key].id)
          dashboard_tab_id = 8
          row              = 22
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_more_info_vs_apply[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_more_info_vs_apply[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_apply_conversion_rate[key].id)
          dashboard_tab_id = 8
          row              = 22
          col              = 12
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_apply_conversion_rate[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_apply_conversion_rate[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # ── (3) RESULTS FILTER ──
          card_id          = tonumber(metabase_card.screener_filter_usage[key].id)
          dashboard_tab_id = 8
          row              = 30
          col              = 0
          size_x           = 8
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_filter_usage[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_filter_usage[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # ── (4) ADDITIONAL RESOURCES section ──
          card_id          = tonumber(metabase_card.screener_top_resources[key].id)
          dashboard_tab_id = 8
          row              = 34
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_top_resources[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_top_resources[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_resource_engagement[key].id)
          dashboard_tab_id = 8
          row              = 34
          col              = 12
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_resource_engagement[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_resource_engagement[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_resources_tab_engagement[key].id)
          dashboard_tab_id = 8
          row              = 42
          col              = 0
          size_x           = 12
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_resources_tab_engagement[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_resources_tab_engagement[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_additional_resources_edits[key].id)
          dashboard_tab_id = 8
          row              = 42
          col              = 12
          size_x           = 12
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_additional_resources_edits[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_additional_resources_edits[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_navigator_engagement[key].id)
          dashboard_tab_id = 8
          row              = 46
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_navigator_engagement[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_navigator_engagement[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # ── (5) NAV BETWEEN RESULTS TABS ──
          card_id          = tonumber(metabase_card.screener_tab_split[key].id)
          dashboard_tab_id = 8
          row              = 54
          col              = 0
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_tab_split[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_tab_split[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # ── (6) HELP & FEEDBACK ──
          card_id          = tonumber(metabase_card.screener_get_help_clicks[key].id)
          dashboard_tab_id = 8
          row              = 62
          col              = 0
          size_x           = 8
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_get_help_clicks[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_get_help_clicks[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_nps_distribution[key].id)
          dashboard_tab_id = 8
          row              = 62
          col              = 8
          size_x           = 16
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_nps_distribution[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_nps_distribution[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : []
    )
  }

  # Tab 9: Sharing & Saving
  tenant_dashboard_screener_sharing_saving_layout = {
    for key, tenant in var.tenants : key => (
      var.bigquery_enabled && contains(keys(local.ga_tenants_enabled), key) ? [
        {
          card_id          = tonumber(metabase_card.screener_share_funnel_popup[key].id)
          dashboard_tab_id = 9
          row              = 0
          col              = 0
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_share_funnel_popup[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_share_funnel_popup[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_share_funnel_footer[key].id)
          dashboard_tab_id = 9
          row              = 0
          col              = 12
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_share_funnel_footer[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_share_funnel_footer[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_shares_by_channel[key].id)
          dashboard_tab_id = 9
          row              = 6
          col              = 0
          size_x           = 24
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_shares_by_channel[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_shares_by_channel[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_save_funnel[key].id)
          dashboard_tab_id = 9
          row              = 12
          col              = 0
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_save_funnel[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_save_funnel[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_saves_by_channel[key].id)
          dashboard_tab_id = 9
          row              = 12
          col              = 12
          size_x           = 12
          size_y           = 6
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_saves_by_channel[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_saves_by_channel[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
      ] : []
    )
  }
}
