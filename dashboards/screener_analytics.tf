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
    description         = "Started -> Saw Results -> Viewed Details -> Clicked Apply. 'Viewed Details' = clicked 'More info' on a program. Started is counted per browsing session; Saw Results and later are counted per screening (a screening ID isn't created until step 3), so read stage-to-stage conversion as directional, not an exact ratio."
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
    description         = "How far people get through the form: each bar is the share of visits that reached at least that step, so bars always shrink down the list. Counted per visit (session), not per screening — the first steps happen before a screening exists. Hover for the count. Because it counts visits, 'Reached Results' runs higher than 'Results Viewed' on the Results Page tab (which counts distinct screenings). Referral Source and Select State are excluded (only shown to some users)."
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
    description         = "Of the screenings that viewed each step, the % that hit at least one validation error there — so steps are comparable regardless of traffic. Hover for the screening count and total error attempts."
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
    description         = "Of the screenings that viewed each step, the % that clicked Back from it — so steps are comparable regardless of traffic. Hover for the back-navigation count."
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
# NOTE: "Apply Conversion Rate by Program" and "More Info vs Apply by Program" were
# consolidated into two top-15 row charts — "Most Shown Programs" (counts) and
# "Program Engagement" (More-Info Rate %) — plus the "Program Conversion Rates" table
# (rates, shown>=20) further down. See screener_sql_program_most_shown /
# screener_sql_program_engagement / screener_sql_program_conversion.

# Results revisits — bar. How many screenings loaded their results page once vs.
# multiple times (1 / 2 / 3+), a proxy for how often people return to a saved
# result. From mart_screener_results_revisits (one row per screening, lifetime
# load count), bucketed and counted.
resource "metabase_card" "screener_results_revisits" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Results Views per Screening"
    description         = "How many screenings loaded their results page once, twice, or 3+ times — a sign of people returning to a saved result. The date filter picks screenings by their first results view."
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
resource "metabase_card" "screener_results_viewed" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Results Viewed"
    description         = "How many screenings reached the results page at least once. Counts each screening once, not total views — reloading or revisiting results doesn't inflate it. (The 'Reached Results' bar on the Engagement by Step tab counts per visit instead, so it runs higher.)"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_results_viewed, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field" = "Results Viewed"
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "screener_results_pct_eligible" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "% Eligible for 1+ Program"
    description         = "Of the screenings that reached the results page, the % that qualified for at least one program (i.e. were not shown an empty results page)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_results_pct_eligible, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field"    = "% Eligible for 1+ Program"
      "column_settings" = { "[\"name\",\"% Eligible for 1+ Program\"]" = { suffix = "%" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "screener_results_error_rate" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Results Error Rate %"
    description         = "Of the screenings that reached the results page, the % that hit an error while loading results."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_results_error_rate, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field"    = "Results Error Rate %"
      "column_settings" = { "[\"name\",\"Results Error Rate %\"]" = { suffix = "%" } }
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
    description         = "Popup share funnel: distinct SCREENINGS that opened vs sent a share (counted once per screening, so the funnel stays monotonic). Shares by Channel counts total send events instead, so its per-channel total can exceed this 'Sent' stage when a screening sends more than once."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_share_funnel_popup, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
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

# Share funnel — Footer location: open -> send.
resource "metabase_card" "screener_share_funnel_footer" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Share Funnel — Footer"
    description         = "Footer share funnel: distinct SCREENINGS that opened vs sent a share (counted once per screening, so the funnel stays monotonic). Shares by Channel counts total send events instead, so its per-channel total can exceed this 'Sent' stage when a screening sends more than once."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_share_funnel_footer, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
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

# Shares by channel — bar. share_provider (email provider etc.) is carried in the
# mart and shown in the detail via the channel/provider grouping.
resource "metabase_card" "screener_shares_by_channel" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Shares by Channel"
    description         = "How many shares were sent, broken out by channel (and provider, e.g. email provider). Counts every send, so it can run a bit higher than the Share Funnel's 'Sent' stage, which counts each screening only once."
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
    description         = "Save-results funnel: reached results → opened the save popup → saved. 'Saved' counts screenings that completed a save (sent it to themselves), not just opening the popup."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_save_funnel, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
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

# Saves by channel — bar.
resource "metabase_card" "screener_saves_by_channel" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Saves by Channel"
    description         = "How many results-saves were sent, broken out by channel. Counts every save, so it can run a bit higher than the Save Funnel, which counts each screening only once."
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

# NOTE: "Results Tab Engagement" (screener_tab_split) was removed — the
# Additional-Resources open rate it surfaced is now the "Opened Additional
# Resources" scalar in the results-engagement row, and Long-Term Benefits was the
# default tab (~100%, no signal).

# ══════════════════════════════════════════════════════════════════════════════
# Analytics v2 cards — new event families
# ══════════════════════════════════════════════════════════════════════════════

# Per-program conversion — table. Two conversion rates (more-info / shown and
# apply / more-info) alongside the raw counts; multi-metric rates read best as a
# table.
resource "metabase_card" "screener_program_conversion" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Program Conversion Rates"
    description         = "Per-program funnel: how many screenings were Shown each program, Viewed Details (clicked 'More info'), and Applied — plus the step-to-step conversion rates. Only programs shown to 20+ screenings (smaller numbers are too noisy to trust). Sorted by the Shown → Details rate."
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
    # Table, not a bar/row chart: with ~115 programs a bar chart is unreadable and
    # Metabase auto-buckets the long tail into an "Other" category that this build
    # exposes no toggle to disable. A table shows every program, sortable.
    display = "table"
    visualization_settings = {
      "table.row_index"     = false
      "table.paginate"      = false
      "table.column_widths" = {}
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Most-shown programs — top-15 horizontal bar chart (raw Shown count). Bounded to 15
# so the row chart is readable and never trips Metabase's "Other" bucketing.
resource "metabase_card" "screener_program_most_shown" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Most Shown Programs (Top 15)"
    description         = "The 15 programs shown to the most screenings. Raw count of distinct screenings each program appeared for. Full per-program counts are in the Conversion Rates table."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_program_most_shown, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"        = ["Program"]
      "graph.metrics"           = ["Shown"]
      "graph.show_values"       = true
      "graph.x_axis.title_text" = "Program"
      "graph.y_axis.title_text" = "Screenings Shown"
      "series_settings"         = { "Shown" = { color = "#4e79a7" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Program engagement — top-15 horizontal bar chart of More-Info Rate % (more-info ÷
# shown), shown >= 20 floor. Rate % also appears in the Conversion Rates table below
# (this is the at-a-glance visual; the table is the sortable detail).
resource "metabase_card" "screener_program_engagement" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Program Engagement (Top 15)"
    description         = "The 15 programs with the highest Viewed-Details Rate % (share of screenings shown the program that clicked 'More info' to view its details). Only programs shown to ≥20 screenings, so small-denominator flukes don't top the ranking."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_program_engagement, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"        = ["Program"]
      "graph.metrics"           = ["Viewed-Details Rate %"]
      "graph.show_values"       = true
      "graph.x_axis.title_text" = "Program"
      "graph.y_axis.title_text" = "Viewed-Details Rate %"
      "series_settings"         = { "Viewed-Details Rate %" = { color = "#59a14f" } }
      "column_settings"         = { "[\"name\",\"Viewed-Details Rate %\"]" = { suffix = "%" } }
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

# Additional-resource engagement — grouped vertical bar. Per resource, the expand
# (more-info) count and contact clicks split by website vs phone. Top 20 by more-info.
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
    display = "bar"
    visualization_settings = {
      "graph.show_values"       = true
      "graph.dimensions"        = ["Resource"]
      "graph.metrics"           = ["More Info", "Website", "Phone"]
      "graph.x_axis.title_text" = "Resource"
      "graph.y_axis.title_text" = "Clicks"
      "graph.y_axis.decimals"   = 0
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
    name                = "Opened Additional Resources"
    description         = "Of the screenings that reached the results page, the % that opened the Additional Resources tab."
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
    display = "scalar"
    visualization_settings = {
      "scalar.field"    = "% of Results Viewers"
      "column_settings" = { "[\"name\",\"% of Results Viewers\"]" = { suffix = "%" } }
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
      "graph.show_values" = true
      "graph.dimensions"  = ["Help Topic"]
      "graph.metrics"     = ["Clicks"]
      "series_settings"   = { "Clicks" = { color = "#e8a33d" } }
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
    name                = "Clicked More Help?"
    description         = "Of the screenings that reached the results page, the % that clicked the More Help / 211 call-to-action."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_get_help_clicks, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
        "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field"    = "% of Results Viewers"
      "column_settings" = { "[\"name\",\"% of Results Viewers\"]" = { suffix = "%" } }
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
    name                = "Used Citizenship Filter"
    description         = "Of the screenings that reached the results page, the % that used the citizenship filter. Which option they picked isn't captured (privacy)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_filter_usage, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
        "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field"    = "% of Results Viewers"
      "column_settings" = { "[\"name\",\"% of Results Viewers\"]" = { suffix = "%" } }
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


# Additional Resources edited — scalar (% of results viewers). Clicks on the
# results-page "edit your selections" link that sends people back to the Additional
# Resources step, as a share of results viewers. Sits in the results-engagement row.
resource "metabase_card" "screener_additional_resources_edits" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Additional Resources Edited (from Results)"
    description         = "Of the screenings that reached the results page, the % that clicked the link to go back and edit their Additional Resources selections (different from edits made on the confirmation page)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_additional_resources_edits, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
        "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field"    = "% of Results Viewers"
      "column_settings" = { "[\"name\",\"% of Results Viewers\"]" = { suffix = "%" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Document downloads — table. Which "Key Information" documents get downloaded, by
# program. Count card (no impression event exists → no true download rate; see FE
# gaps ticket). Sits next to the Navigator table.
resource "metabase_card" "screener_document_downloads" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Document Downloads"
    description         = "Which 'Key Information You May Need to Provide' documents were downloaded, and for which program. Screenings = how many screenings downloaded it; Downloads = total download clicks."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_document_downloads, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# NPS engagement — scalar (% of results viewers who submitted an NPS score). Sits
# next to the NPS Score Distribution card.
resource "metabase_card" "screener_nps_engagement" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Engaged with NPS"
    description         = "Of the screenings that reached the results page, the % that engaged with the NPS survey (clicked a score)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_nps_engagement, "__STATE_FILTER_CESN__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})"),
        "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "scalar"
    visualization_settings = {
      "scalar.field"    = "% of Results Viewers"
      "column_settings" = { "[\"name\",\"% of Results Viewers\"]" = { suffix = "%" } }
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
          # ── (1) OVERVIEW: three outcome scalars in a row ──
          card_id          = tonumber(metabase_card.screener_results_viewed[key].id)
          dashboard_tab_id = 8
          row              = 2
          col              = 0
          size_x           = 8
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_results_viewed[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_results_viewed[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_results_pct_eligible[key].id)
          dashboard_tab_id = 8
          row              = 2
          col              = 8
          size_x           = 8
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_results_pct_eligible[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_results_pct_eligible[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_results_error_rate[key].id)
          dashboard_tab_id = 8
          row              = 2
          col              = 16
          size_x           = 8
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_results_error_rate[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_results_error_rate[key].id)
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
          # ── (2) PROGRAMS: two row charts side-by-side, then conversion table ──
          card_id          = tonumber(metabase_card.screener_program_most_shown[key].id)
          dashboard_tab_id = 8
          row              = 14
          col              = 0
          size_x           = 12
          size_y           = 10
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_program_most_shown[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_program_most_shown[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_program_engagement[key].id)
          dashboard_tab_id = 8
          row              = 14
          col              = 12
          size_x           = 12
          size_y           = 10
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_program_engagement[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_program_engagement[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_program_conversion[key].id)
          dashboard_tab_id = 8
          row              = 24
          col              = 0
          size_x           = 24
          size_y           = 10
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
          # ── (3) RESULTS-PAGE ENGAGEMENT (4 scalars, % of results viewers) ──
          # Order: Citizenship Filter, More Help, Viewed Additional Resources,
          # Additional Resources Edited. 6-wide each across the 24-col row.
          card_id          = tonumber(metabase_card.screener_filter_usage[key].id)
          dashboard_tab_id = 8
          row              = 34
          col              = 0
          size_x           = 6
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
          card_id          = tonumber(metabase_card.screener_get_help_clicks[key].id)
          dashboard_tab_id = 8
          row              = 34
          col              = 6
          size_x           = 6
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
          card_id          = tonumber(metabase_card.screener_resources_tab_engagement[key].id)
          dashboard_tab_id = 8
          row              = 34
          col              = 12
          size_x           = 6
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
          row              = 34
          col              = 18
          size_x           = 6
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
          # ── (4) ADDITIONAL RESOURCES section ──
          # Full-width, tall grouped bar (top 20 resources × more-info/website/phone);
          # replaces the old side-by-side Top Resources + Engagement pair.
          card_id          = tonumber(metabase_card.screener_resource_engagement[key].id)
          dashboard_tab_id = 8
          row              = 38
          col              = 0
          size_x           = 24
          size_y           = 12
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
          card_id          = tonumber(metabase_card.screener_navigator_engagement[key].id)
          dashboard_tab_id = 8
          row              = 50
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
          card_id          = tonumber(metabase_card.screener_document_downloads[key].id)
          dashboard_tab_id = 8
          row              = 50
          col              = 12
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_document_downloads[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_document_downloads[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          # ── (5) FEEDBACK ──
          card_id          = tonumber(metabase_card.screener_nps_distribution[key].id)
          dashboard_tab_id = 8
          row              = 58
          col              = 0
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
        {
          card_id          = tonumber(metabase_card.screener_nps_engagement[key].id)
          dashboard_tab_id = 8
          row              = 58
          col              = 16
          size_x           = 8
          size_y           = 4
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_nps_engagement[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_nps_engagement[key].id)
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
