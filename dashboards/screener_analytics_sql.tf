# Shared SQL bodies for the 16 screener analytics cards (MFB-1311 DRY refactor).
#
# Each card's SQL is defined ONCE here with sentinel tokens where the per-scope
# state predicate goes. Consumers substitute the sentinel with `replace()`:
#
#   __STATE_FILTER__     — the screener_state predicate for the mart being queried.
#                          tenant: "screener_state IN (${local.tenant_ga_state_filter[each.key]})"
#                          global: "1=1"  (all states, no filter)
#   __STATE_FILTER_KPI__ — ONLY in the macro funnel: the state_code predicate on
#                          mart_ga_kpi_summary (GA sessions use `state_code`, not
#                          `screener_state`).
#                          tenant: "state_code IN (${local.tenant_ga_state_filter[each.key]})"
#                          global: "1=1"
#
# The sentinel always replaces the ENTIRE predicate that follows `WHERE`, so both
# the tenant form (`WHERE screener_state IN ('co')`) and the global form
# (`WHERE 1=1`) chain correctly with any following `AND ...` / `[[AND ...]]`.
#
# The bracketed `[[AND event_date_parsed ...]]` predicates and
# `template-tags = local.ga_date_tags` are preserved verbatim by both consumers
# (screener_analytics.tf tenant cards, screener_analytics_global.tf global cards)
# and are NOT parameterized — they are Metabase optional-filter syntax.
#
# IMPORTANT: only the state filter is parameterized here. No card's SQL logic
# (aggregations, joins, ordering, HAVING) differs between the tenant and global
# versions.

locals {
  # ── Tab 10 (Overview): Macro funnel ─────────────────────────────────────────
  screener_sql_macro_funnel = <<-SQL
    WITH visitors AS (
      SELECT SUM(total_sessions) AS n
      FROM `${local.bq_dataset}.mart_ga_kpi_summary`
      WHERE __STATE_FILTER_KPI__
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    started AS (
      SELECT SUM(screenings_viewed_step) AS n
      FROM `${local.bq_dataset}.mart_screener_form_funnel`
      WHERE __STATE_FILTER__
        AND screener_step_name = '__form_start__'
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    results AS (
      SELECT SUM(screenings_results_loaded) AS n
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    more_info AS (
      SELECT SUM(screenings_with_interaction) AS n
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
        AND interaction_type = 'more_info'
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    apply AS (
      SELECT SUM(screenings_with_interaction) AS n
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
        AND interaction_type = 'apply'
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step, screenings
    FROM (
      SELECT 'Visitors'          AS funnel_step, (SELECT n FROM visitors)  AS screenings, 1 AS step_order
      UNION ALL SELECT 'Started',            (SELECT n FROM started),   2
      UNION ALL SELECT 'Saw Results',        (SELECT n FROM results),   3
      UNION ALL SELECT 'Clicked More Info',  (SELECT n FROM more_info), 4
      UNION ALL SELECT 'Clicked Apply',      (SELECT n FROM apply),     5
    )
    ORDER BY step_order
  SQL

  # ── Tab 7 (Form Journey): step drop-off funnel ──────────────────────────────
  screener_sql_step_funnel = <<-SQL
    SELECT
      screener_step_name,
      SUM(screenings_viewed_step) AS screenings_viewed
    FROM `${local.bq_dataset}.mart_screener_form_funnel`
    WHERE __STATE_FILTER__
      AND screener_step_name NOT IN ('__form_start__', '__form_complete__')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY screener_step_name
    ORDER BY MIN(screener_step_number) NULLS LAST, screener_step_name
  SQL

  # ── Tab 7 (Form Journey): errors by step ────────────────────────────────────
  screener_sql_errors_by_step = <<-SQL
    SELECT
      screener_step_name,
      SUM(total_error_count) AS total_errors
    FROM `${local.bq_dataset}.mart_screener_form_funnel`
    WHERE __STATE_FILTER__
      AND screener_step_name NOT IN ('__form_start__', '__form_complete__')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY screener_step_name
    HAVING SUM(total_error_count) > 0
    ORDER BY total_errors DESC
  SQL

  # ── Tab 7 (Form Journey): back navigation by step ───────────────────────────
  screener_sql_back_nav_by_step = <<-SQL
    SELECT
      screener_step_name,
      SUM(screenings_navigated_back) AS screenings_back
    FROM `${local.bq_dataset}.mart_screener_form_funnel`
    WHERE __STATE_FILTER__
      AND screener_step_name NOT IN ('__form_start__', '__form_complete__')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY screener_step_name
    HAVING SUM(screenings_navigated_back) > 0
    ORDER BY screenings_back DESC
  SQL

  # ── Tab 8 (Results): apply conversion rate by program ───────────────────────
  screener_sql_apply_conversion_rate = <<-SQL
    WITH per_program AS (
      SELECT
        program_id,
        MAX(program_name) AS program_name,
        SUM(CASE WHEN interaction_type = 'more_info' THEN screenings_with_interaction ELSE 0 END) AS more_info_screenings,
        SUM(CASE WHEN interaction_type = 'apply'     THEN screenings_with_interaction ELSE 0 END) AS apply_screenings
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY program_id
    )
    SELECT
      program_name,
      more_info_screenings,
      apply_screenings,
      ROUND(apply_screenings * 100.0 / NULLIF(more_info_screenings, 0), 1) AS apply_rate_pct
    FROM per_program
    WHERE more_info_screenings > 0
    ORDER BY apply_rate_pct DESC
  SQL

  # ── Tab 8 (Results): more info vs apply by program ──────────────────────────
  screener_sql_more_info_vs_apply = <<-SQL
    WITH per_program AS (
      SELECT
        program_id,
        MAX(program_name) AS program_name,
        SUM(CASE WHEN interaction_type = 'more_info' THEN screenings_with_interaction ELSE 0 END) AS more_info,
        SUM(CASE WHEN interaction_type = 'apply'     THEN screenings_with_interaction ELSE 0 END) AS apply
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY program_id
    )
    SELECT program_name, more_info, apply
    FROM per_program
    WHERE more_info > 0 OR apply > 0
    ORDER BY (more_info - apply) DESC
  SQL

  # ── Tab 8 (Results): more info vs apply scatter ─────────────────────────────
  screener_sql_more_info_apply_scatter = <<-SQL
    WITH per_program AS (
      SELECT
        program_id,
        MAX(program_name) AS program_name,
        SUM(CASE WHEN interaction_type = 'more_info' THEN screenings_with_interaction ELSE 0 END) AS more_info,
        SUM(CASE WHEN interaction_type = 'apply'     THEN screenings_with_interaction ELSE 0 END) AS apply
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY program_id
    )
    SELECT program_name, more_info, apply
    FROM per_program
    WHERE more_info > 0 OR apply > 0
    ORDER BY more_info DESC
  SQL

  # ── Tab 8 (Results): results outcome KPIs ───────────────────────────────────
  screener_sql_results_outcome_kpis = <<-SQL
    WITH agg AS (
      SELECT
        SUM(screenings_results_loaded) AS results_viewed,
        SUM(screenings_none_eligible)  AS none_eligible,
        SUM(screenings_results_error)  AS results_errors,
        -- avg_* columns are daily averages in the mart; average them across
        -- days as an approximation (matches the GA median-of-medians approach)
        ROUND(AVG(avg_program_count), 2)          AS avg_program_count,
        ROUND(AVG(avg_total_estimated_value), 2)  AS avg_total_estimated_value
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      results_viewed,
      none_eligible,
      ROUND(none_eligible * 100.0 / NULLIF(results_viewed + none_eligible, 0), 1) AS none_eligible_pct,
      avg_program_count,
      avg_total_estimated_value,
      results_errors
    FROM agg
  SQL

  # ── Tab 9 (Sharing & Saving): share funnel — popup ──────────────────────────
  screener_sql_share_funnel_popup = <<-SQL
    WITH filtered AS (
      SELECT * FROM `${local.bq_dataset}.mart_screener_shares`
      WHERE __STATE_FILTER__
        AND share_location = 'popup'
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step, screenings
    FROM (
      SELECT 'Opened' AS funnel_step,
             SUM(CASE WHEN share_action = 'open' THEN screenings_with_share ELSE 0 END) AS screenings,
             1 AS step_order
      FROM filtered
      UNION ALL
      SELECT 'Sent',
             SUM(CASE WHEN share_action = 'send' THEN screenings_with_share ELSE 0 END),
             2
      FROM filtered
    )
    ORDER BY step_order
  SQL

  # ── Tab 9 (Sharing & Saving): share funnel — footer ─────────────────────────
  screener_sql_share_funnel_footer = <<-SQL
    WITH filtered AS (
      SELECT * FROM `${local.bq_dataset}.mart_screener_shares`
      WHERE __STATE_FILTER__
        AND share_location = 'footer'
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step, screenings
    FROM (
      SELECT 'Opened' AS funnel_step,
             SUM(CASE WHEN share_action = 'open' THEN screenings_with_share ELSE 0 END) AS screenings,
             1 AS step_order
      FROM filtered
      UNION ALL
      SELECT 'Sent',
             SUM(CASE WHEN share_action = 'send' THEN screenings_with_share ELSE 0 END),
             2
      FROM filtered
    )
    ORDER BY step_order
  SQL

  # ── Tab 9 (Sharing & Saving): shares by channel ─────────────────────────────
  screener_sql_shares_by_channel = <<-SQL
    SELECT
      share_channel,
      COALESCE(share_provider, '(none)') AS share_provider,
      SUM(total_shares) AS total_shares
    FROM `${local.bq_dataset}.mart_screener_shares`
    WHERE __STATE_FILTER__
      AND share_action = 'send'
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY share_channel, share_provider
    ORDER BY total_shares DESC
  SQL

  # ── Tab 9 (Sharing & Saving): save funnel ───────────────────────────────────
  screener_sql_save_funnel = <<-SQL
    WITH filtered AS (
      SELECT * FROM `${local.bq_dataset}.mart_screener_saves`
      WHERE __STATE_FILTER__
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step, screenings
    FROM (
      SELECT 'Shown Popup' AS funnel_step, SUM(screenings_shown_popup) AS screenings, 1 AS step_order FROM filtered
      UNION ALL SELECT 'Saved', SUM(screenings_with_save), 2 FROM filtered
    )
    ORDER BY step_order
  SQL

  # ── Tab 9 (Sharing & Saving): saves by channel ──────────────────────────────
  screener_sql_saves_by_channel = <<-SQL
    SELECT
      COALESCE(save_channel, '(none)') AS save_channel,
      SUM(total_saves) AS total_saves
    FROM `${local.bq_dataset}.mart_screener_saves`
    WHERE __STATE_FILTER__
      AND save_channel IS NOT NULL
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY save_channel
    ORDER BY total_saves DESC
  SQL

  # ── Tab 8 (Results): results-page tab split ─────────────────────────────────
  screener_sql_tab_split = <<-SQL
    SELECT
      dimension AS tab,
      SUM(distinct_screenings) AS screenings
    FROM `${local.bq_dataset}.mart_screener_resource_engagement`
    WHERE __STATE_FILTER__
      AND metric = 'tab_open'
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY dimension
    ORDER BY screenings DESC
  SQL

  # ── Tab 8 (Results): top additional resources ───────────────────────────────
  screener_sql_top_resources = <<-SQL
    SELECT
      dimension AS resource,
      SUM(total_clicks) AS clicks
    FROM `${local.bq_dataset}.mart_screener_resource_engagement`
    WHERE __STATE_FILTER__
      AND metric = 'resource_click'
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY dimension
    ORDER BY clicks DESC
    LIMIT 20
  SQL

  # ── Tab 10 (Overview): language distribution ────────────────────────────────
  screener_sql_language_distribution = <<-SQL
    SELECT
      language_name,
      SUM(distinct_screenings) AS screenings
    FROM `${local.bq_dataset}.mart_screener_language`
    WHERE __STATE_FILTER__
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY language_name
    ORDER BY screenings DESC
  SQL
}
