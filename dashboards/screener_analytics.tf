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
        query         = replace(local.screener_sql_macro_funnel, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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

# Detailed per-step drop-off funnel from mart_screener_form_funnel.
# Ordered by MIN(screener_step_number) so steps appear in true flow order rather
# than alphabetically. CAVEAT: select-state is a pre-numbered page with a null
# screener_step_number (see the mart header); such rows
# sort last (NULLS LAST). The synthetic __form_start__/__form_complete__ rows are
# excluded here since this is the step-by-step (not start-to-complete) funnel.
resource "metabase_card" "screener_step_funnel" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Form Step Drop-off Funnel"
    description         = "Distinct screenings that viewed each screener step, in flow order (by step number; null-numbered pages sort last)"
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
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["screener_step_label"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Errors by step — bar. Uses total_error_count (raw error events); screenings_with_error
# is available if a distinct-screening view is preferred later.
resource "metabase_card" "screener_errors_by_step" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Form Errors by Step"
    description         = "Total form validation errors recorded at each screener step"
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
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["screener_step_label"]
      "graph.metrics"    = ["Total Errors"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Back-navigation by step — bar (distinct screenings that navigated back from a step).
resource "metabase_card" "screener_back_nav_by_step" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Back Navigation by Step"
    description         = "Distinct screenings that navigated back from each screener step"
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
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Program"]
      "graph.metrics"    = ["Apply Rate %"]
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
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Program"]
      "graph.metrics"    = ["More Info", "Apply"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Scatter: more_info (x) vs apply (y) per program.
# NOTE: display="scatter" is not used elsewhere in this repo; the column shape
# (two numeric metrics + a program dimension) is also valid for a table fallback
# if the Metabase scatter renderer misbehaves
resource "metabase_card" "screener_more_info_apply_scatter" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "More Info vs Apply (Scatter)"
    description         = "Per-program scatter of distinct more-info screenings (x) against apply screenings (y)"
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_more_info_apply_scatter, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
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
      "graph.dimensions" = ["Share Channel"]
      "graph.metrics"    = ["Total Shares"]
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
      "graph.dimensions" = ["Save Channel"]
      "graph.metrics"    = ["Total Saves"]
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
    name                = "Results Tab Split"
    description         = "Distinct screenings opening each results-page tab (long-term benefits vs additional resources)"
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
      "graph.metrics"    = ["Screenings"]
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
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Resource"]
      "graph.metrics"    = ["Clicks"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

# Language distribution — bar. Language changes by language from
# mart_screener_language.
resource "metabase_card" "screener_language_distribution" {
  for_each = local.ga_tenants_enabled

  json = jsonencode({
    name                = "Header Language Switches"
    description         = "Which languages sessions switch TO via the header language selector (header-selector engagement — NOT the language the household speaks, which is on the Households tab). Deduped per session."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_language_distribution, "__STATE_FILTER__", "screener_state IN (${local.tenant_ga_state_filter[each.key]})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions" = ["Switched To"]
      "graph.metrics"    = ["Sessions"]
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
        {
          card_id          = tonumber(metabase_card.screener_language_distribution[key].id)
          dashboard_tab_id = 10
          row              = 8
          col              = 0
          size_x           = 24
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_language_distribution[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_language_distribution[key].id)
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
          size_y           = 8
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
          card_id          = tonumber(metabase_card.screener_errors_by_step[key].id)
          dashboard_tab_id = 7
          row              = 8
          col              = 0
          size_x           = 12
          size_y           = 6
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
          row              = 8
          col              = 12
          size_x           = 12
          size_y           = 6
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
      ] : []
    )
  }

  # Tab 8: Results
  tenant_dashboard_screener_results_layout = {
    for key, tenant in var.tenants : key => (
      var.bigquery_enabled && contains(keys(local.ga_tenants_enabled), key) ? [
        {
          card_id          = tonumber(metabase_card.screener_results_outcome_kpis[key].id)
          dashboard_tab_id = 8
          row              = 0
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
          card_id          = tonumber(metabase_card.screener_apply_conversion_rate[key].id)
          dashboard_tab_id = 8
          row              = 4
          col              = 0
          size_x           = 24
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
          card_id          = tonumber(metabase_card.screener_more_info_vs_apply[key].id)
          dashboard_tab_id = 8
          row              = 12
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
          card_id          = tonumber(metabase_card.screener_more_info_apply_scatter[key].id)
          dashboard_tab_id = 8
          row              = 12
          col              = 12
          size_x           = 12
          size_y           = 8
          parameter_mappings = [
            {
              parameter_id = local._ga_start_date_param_id
              card_id      = tonumber(metabase_card.screener_more_info_apply_scatter[key].id)
              target       = ["variable", ["template-tag", "start_date"]]
            },
            {
              parameter_id = local._ga_end_date_param_id
              card_id      = tonumber(metabase_card.screener_more_info_apply_scatter[key].id)
              target       = ["variable", ["template-tag", "end_date"]]
            }
          ]
          series                 = []
          visualization_settings = {}
        },
        {
          card_id          = tonumber(metabase_card.screener_tab_split[key].id)
          dashboard_tab_id = 8
          row              = 20
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
          card_id          = tonumber(metabase_card.screener_top_resources[key].id)
          dashboard_tab_id = 8
          row              = 20
          col              = 12
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
