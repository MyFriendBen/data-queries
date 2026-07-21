# Global (all-states) versions of the 16 screener analytics cards.
#
# These are SINGLE-INSTANCE cards (no for_each) that live in the Global
# collection and query ALL states. They consume the SAME shared SQL bodies as
# the per-tenant cards (locals in screener_analytics_sql.tf); the ONLY difference
# is the state predicate substitution — filtered to the full set of valid
# lowercase state codes (NOT a bare 1=1) so legacy DOM-scrape rows (display-name
# state) and null-state landing rows don't contaminate the all-states totals:
#   __STATE_FILTER__     -> "screener_state IN (${local.all_screener_state_filter})"
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
        query = replace(
          replace(local.screener_sql_macro_funnel, "__STATE_FILTER_CESN__", local.all_screener_global_predicate),
        "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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
    name                = "Header Language Switches"
    description         = "Which languages sessions switch TO via the header language selector (header-selector engagement, NOT the language the household speaks). Counted per session per language — a session that switches to more than one language is counted under each, so these won't sum to the 'Changed Language' total on the Header & Footer Links card."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.screener_sql_language_distribution
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"      = ["Switched To"]
      "graph.metrics"         = ["Sessions"]
      "series_settings"       = { "Sessions" = { color = "#edc948" } }
      "graph.y_axis.decimals" = 0
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
    name                = "Form Step Reached"
    description         = "Share of screening sessions that reached at least each step, in flow order through the results page. Monotonic: each bar counts every session that got this far or further, so it always decreases down the funnel. Hover a bar for the raw session count. Referral Source and Select State are excluded (conditionally shown / pre-white-label)."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_step_funnel, "__STATE_FILTER__", local.all_screener_global_predicate)
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"        = ["screener_step_label"]
      "graph.metrics"           = ["% of Started"]
      "series_settings"         = { "% of Started" = { color = "#4e79a7" } }
      "graph.show_values"       = true
      "graph.x_axis.title_text" = "Screener Step"
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_errors_by_step" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Form Errors by Step"
    description         = "Of the screenings that viewed each step, the % that hit at least one validation error on it — normalized for traffic so steps are comparable by how error-prone they are. Hover for the raw screening count and total error events (attempts, inflated by retries)."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_errors_by_step, "__STATE_FILTER__", local.all_screener_global_predicate)
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"        = ["Step"]
      "graph.metrics"           = ["% of Viewers with 1+ Errors"]
      "graph.show_values"       = true
      "graph.x_axis.title_text" = "Screener Step"
      # Red = the "problem" metric (errors); distinct from Back Nav (blue) / Help (amber).
      "series_settings" = { "% of Viewers with 1+ Errors" = { color = "#d64550" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_back_nav_by_step" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Back Navigation by Step"
    description         = "Of the screenings that viewed each step, the % that navigated back from it — normalized for traffic so steps are comparable by how often they send people back. Hover for the raw back-navigation count."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_back_nav_by_step, "__STATE_FILTER__", local.all_screener_global_predicate)
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"        = ["Step"]
      "graph.metrics"           = ["% of Viewers who Went Back"]
      "graph.show_values"       = true
      "graph.x_axis.title_text" = "Screener Step"
      # Blue = neutral navigation behavior (distinct from the red errors bar).
      "series_settings" = { "% of Viewers who Went Back" = { color = "#59a14f" } }
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
        query         = replace(local.screener_sql_results_outcome_kpis, "__STATE_FILTER__", local.all_screener_global_predicate)
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

# Results revisits — how many screenings viewed results once vs. multiple times.
# Plain state filter excludes CESN (its 'cesn' state code isn't in the non-CESN
# list); results events have no null-state rows, matching the sibling cards.
resource "metabase_card" "global_screener_results_revisits" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Results Views per Screening"
    description         = "How many screenings loaded their results page once, twice, or 3+ times — a proxy for returning to a saved result. Counted per screening; the date filter selects screenings by their first results view."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_results_revisits, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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


resource "metabase_card" "global_screener_tab_split" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Results Tab Engagement"
    description         = "% of results-page viewers who opened each results tab (denominator = screenings that loaded results). Long-Term Benefits is the default tab (~100%); the signal is the Additional Resources rate."
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
      "graph.metrics"    = ["% of Results Viewers"]
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

resource "metabase_card" "global_screener_program_conversion" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Program Conversion"
    description         = "Per-program funnel: shown, more-info, and applied counts with the more-info and apply conversion rates, highest more-info rate first."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_program_conversion, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

resource "metabase_card" "global_screener_navigator_engagement" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Navigator Engagement"
    description         = "Distinct screenings that engaged a navigator, broken out by program, navigator, and contact method."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_navigator_engagement, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

resource "metabase_card" "global_screener_resource_engagement" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Additional Resource Engagement"
    description         = "Per additional resource: more-info expands and contact clicks split by website vs phone, top 20 by more-info."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_resource_engagement, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

resource "metabase_card" "global_screener_resources_tab_engagement" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Additional Resources Tab Engagement"
    description         = "Screenings that opened the Additional Resources tab and that count as a percentage of results-page viewers."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query = replace(
          replace(local.screener_sql_resources_tab_engagement, "__STATE_FILTER_CESN__", local.all_screener_global_predicate),
        "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

resource "metabase_card" "global_screener_scroll_depth" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Results Scroll Depth"
    description         = "Of the screenings that scrolled a results tab, how far the deepest scroll got (each screening counted once, in its furthest bucket). Bars are the % of that tab's scrollers; hover for the raw count. Split by tab."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_scroll_depth, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      # Depth on the x-axis, one series per Tab; bar height is % of that tab's
      # scrollers whose furthest scroll was this depth (multi-series can't show a
      # side column on hover). Count on hover. Depth labels are numeric-prefixed
      # ("1. Quarter Page" ...) so Metabase's alphabetical axis sort yields
      # Quarter -> Full.
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

resource "metabase_card" "global_screener_help_by_topic" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Help Clicks by Topic"
    description         = "Help-tooltip clicks by help topic, surfacing which tooltips drive the most confusion. The click event carries only the topic (which is itself step-identifying), so there is no step breakdown."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_help_by_topic, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.max_categories_enabled" = false
      "graph.show_values"            = true
      "graph.dimensions"             = ["Help Topic"]
      "graph.metrics"                = ["Clicks"]
      # Amber = help/info (distinct from red errors + blue back-nav).
      "series_settings" = { "Clicks" = { color = "#e8a33d" } }
      # Whole-number clicks; force integer axis ticks (no 0.2/0.4 gridlines).
      "graph.y_axis.decimals" = 0
      "column_settings"       = { "[\"name\",\"Clicks\"]" = { number_style = "decimal", decimals = 0 } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_household_member_engagement" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Household Member Actions"
    description         = "How people build their household: of the screenings that reached the member basic-info step, the % that added, edited, or deleted a member. Hover for the raw screening count and total action events."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_household_member_engagement, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

resource "metabase_card" "global_screener_income_source_engagement" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Income Source Actions"
    description         = "Total add/edit/delete actions on income sources, and the number of distinct screenings doing each."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_income_source_engagement, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"      = ["Action"]
      "graph.metrics"         = ["Total Actions"]
      "graph.show_values"     = true
      "graph.y_axis.decimals" = 0
      "series_settings"       = { "Total Actions" = { color = "#d37295" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_get_help_clicks" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "More Help Clicks"
    description         = "Total clicks on the More Help / 211 call-to-action from the results page."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_get_help_clicks, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

resource "metabase_card" "global_screener_errors_detail" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Validation Errors Detail"
    description         = "Which fields fail validation and why, by screener step, ordered by error count. Field and Problem are humanized from the PII-safe error code; counts are consolidated across repeated fields (e.g. all income rows roll up to Income)."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_errors_detail, "__STATE_FILTER__", local.all_screener_global_predicate)
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
      "graph.dimensions"      = ["Share Channel"]
      "graph.metrics"         = ["Total Shares"]
      "series_settings"       = { "Total Shares" = { color = "#76b7b2" } }
      "graph.y_axis.decimals" = 0
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
      "graph.dimensions"      = ["Save Channel"]
      "graph.metrics"         = ["Total Saves"]
      "series_settings"       = { "Total Saves" = { color = "#ff9da7" } }
      "graph.y_axis.decimals" = 0
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ── Previously-untracked screener_* events (global) ─────────────────────────────

resource "metabase_card" "global_screener_confirmation_edits" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Confirmation Edits by Section"
    description         = "Of the screenings that reached the confirmation page, the % that went back to edit each section before submitting. Hover for the raw screening count."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_confirmation_edits, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

resource "metabase_card" "global_screener_signup_consent" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Sign-up Consent Rates"
    description         = "Of screenings that completed sign-up, the % opting into SMS vs email contact. Hover for the opt-in count."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_signup_consent, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
        template-tags = local.ga_date_tags
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"      = ["Channel"]
      "graph.metrics"         = ["% Opted In"]
      "graph.show_values"     = true
      "graph.tooltip_columns" = ["Opt-Ins"]
      "series_settings"       = { "% Opted In" = { color = "#59a14f" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_filter_usage" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Citizenship Filter Usage"
    description         = "Distinct screenings that used the results citizenship filter. The chosen option isn't captured, so this is a yes/no engagement count."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_filter_usage, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

resource "metabase_card" "global_screener_nps_distribution" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "NPS Score Distribution"
    description         = "Submitted results-page NPS scores, bucketed Detractor (0-6), Passive (7-8), Promoter (9-10)."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_nps_distribution, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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

# Footer / site-chrome cards (GLOBAL-only — chrome fires without state). Each reads
# the session-grain mart_screener_footer_engagement and plots "% of sessions".
resource "metabase_card" "global_screener_chrome_nav" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Header & Footer Links"
    description         = "Of all sessions, the % that used each persistent header/footer element: the logo, the footer About/Privacy/Terms links, and the language switcher. Hover for the session count. (All states — these aren't attributed to a single state.)"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.screener_sql_chrome_nav
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"      = ["Element"]
      "graph.metrics"         = ["% of Sessions"]
      "graph.tooltip_columns" = ["Sessions"]
      "series_settings"       = { "% of Sessions" = { color = "#76b7b2" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_social_clicks" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Social Link Clicks"
    description         = "Of all sessions, the % that clicked a footer social icon, by network. Hover for the session count. (All states — chrome isn't attributed to a single state.)"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.screener_sql_social_clicks
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"      = ["Network"]
      "graph.metrics"         = ["% of Sessions"]
      "graph.tooltip_columns" = ["Sessions"]
      "series_settings"       = { "% of Sessions" = { color = "#b07aa1" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_footer_feedback_share" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Footer Feedback & Share"
    description         = "Of all sessions, the % that clicked a footer support/share action: Report a Bug, Contact Us, or Share. Share is explored in depth on the Sharing & Saving tab. Hover for the session count. (All states — chrome isn't attributed to a single state.)"
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.screener_sql_footer_feedback_share
        template-tags = local.ga_date_tags
      }
    }
    display = "row"
    visualization_settings = {
      "graph.dimensions"      = ["Action"]
      "graph.metrics"         = ["% of Sessions"]
      "graph.tooltip_columns" = ["Sessions"]
      "series_settings"       = { "% of Sessions" = { color = "#f28e2b" } }
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "global_screener_public_charge_click_rate" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Public Charge Link — Click Rate"
    description         = "Of the sessions that viewed the Disclaimer step, the % that clicked the Public Charge info link."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_public_charge_click_rate, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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


resource "metabase_card" "global_screener_additional_resources_edits" {
  count = var.bigquery_enabled ? 1 : 0

  json = jsonencode({
    name                = "Additional Resources Edits (from Results)"
    description         = "Clicks on the results-page link that sends people back to the Additional Resources step to change their selections. Distinct from confirmation-page edits."
    collection_id       = local.global_col_id
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = replace(local.screener_sql_additional_resources_edits, "__STATE_FILTER__", "screener_state IN (${local.all_screener_state_filter})")
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
