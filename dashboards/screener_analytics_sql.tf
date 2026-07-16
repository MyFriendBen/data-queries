# Shared SQL bodies for the 16 screener analytics cards.
#
# Each card's SQL is defined ONCE here with sentinel tokens where the per-scope
# state predicate goes. Consumers substitute the sentinel with `replace()`:
#
#   __STATE_FILTER__     — the screener_state predicate for the mart being queried.
#                          tenant: "screener_state IN (${local.tenant_ga_state_filter[each.key]})"
#                          global: "screener_state IN (${local.all_screener_state_filter})"
#
# The sentinel always replaces the ENTIRE predicate that follows `WHERE`, so both
# the tenant form (`WHERE screener_state IN ('co')`) and the global form
# (all valid codes) chain correctly with any following `AND ...` / `[[AND ...]]`.
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
    WITH started AS (
      SELECT SUM(screenings_viewed_step) AS n
      FROM `${local.bq_dataset}.mart_screener_form_funnel`
      WHERE __STATE_FILTER__
        AND screener_step_name = '__form_start__'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    results AS (
      SELECT SUM(screenings_results_loaded) AS n
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    more_info AS (
      SELECT SUM(screenings_with_interaction) AS n
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
        AND interaction_type = 'more_info'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    apply AS (
      SELECT SUM(screenings_with_interaction) AS n
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
        AND interaction_type = 'apply'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    -- Funnel starts at "Started" (form_start), not raw site Visitors: the old
    -- Visitors stage read the legacy all-time mart_ga_kpi_summary, a different
    -- population/window that produced a meaningless ~99% first-stage drop. All
    -- stages here come from the new event marts on the same epoch-floored window.
    SELECT funnel_step AS `Funnel Step`, screenings AS `Screenings`
    FROM (
      SELECT 'Started'            AS funnel_step, (SELECT n FROM started)   AS screenings, 1 AS step_order
      UNION ALL SELECT 'Saw Results',        (SELECT n FROM results),   2
      UNION ALL SELECT 'Clicked More Info',  (SELECT n FROM more_info), 3
      UNION ALL SELECT 'Clicked Apply',      (SELECT n FROM apply),     4
    )
    ORDER BY step_order
  SQL

  # ── Tab 7 (Form Journey): step drop-off funnel ──────────────────────────────
  # Per-step view counts (form steps), capped with a terminal "Reached Results"
  # bar so the chart shows how many screenings actually reached the results page.
  #
  # Results is a destination, not a form step, so no 'results' step-view event is
  # emitted — the results page fires its own screener_results_loaded event. We
  # read that terminal count from mart_screener_results_outcomes (the SAME source
  # as the Overview funnel's "Saw Results" stage) so the two funnels agree,
  # rather than from screener_form_complete (a confirmation-page button click,
  # deduped on a different key, that would show a slightly different number).
  #
  # Referral Source is EXCLUDED: it is conditionally shown (auto-skipped when the
  # entry URL carries a referral parameter), so its view count is lower than the
  # steps around it for reasons unrelated to drop-off. Leaving it in would break
  # the monotonic funnel shape and corrupt any step-to-step drop-off percentage
  # (a skip would read as attrition). Its completion is reported on its own card
  # (screener_sql_referral_source_completion) against the population actually
  # shown the step.
  #
  # Both synthetic mart rows ('__form_start__' / '__form_complete__') are excluded
  # from the form-step side. The results row carries a large sort key so it lands
  # last regardless of step numbering.
  screener_sql_step_funnel = <<-SQL
    WITH steps AS (
      SELECT
        screener_step_label,
        -- Coalesce to a large-but-below-terminal sentinel so null-numbered form
        -- steps (e.g. select-state, or any future unmapped step) sort near the
        -- end of the form yet still BEFORE the "Reached Results" terminal bar
        -- (999999). A bare MIN(step_number) with NULLS LAST would drop them
        -- after the terminal, putting the destination in the middle of the flow.
        COALESCE(MIN(screener_step_number), 99999) AS sort_key,
        SUM(screenings_viewed_step) AS screenings
      FROM `${local.bq_dataset}.mart_screener_form_funnel`
      WHERE __STATE_FILTER__
        AND screener_step_name NOT IN ('__form_start__', '__form_complete__', 'referral-source')
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY screener_step_label
    ),
    reached_results AS (
      SELECT
        'Reached Results' AS screener_step_label,
        999999 AS sort_key,
        SUM(screenings_results_loaded) AS screenings
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT screener_step_label, screenings AS `Screenings`
    FROM (SELECT * FROM steps UNION ALL SELECT * FROM reached_results)
    WHERE screenings > 0
    ORDER BY sort_key, screener_step_label
  SQL

  # ── Tab 7 (Form Journey): Referral Source completion (reported separately) ───
  # Referral Source is conditionally shown — it is auto-skipped when the entry
  # URL carries a referral parameter — so it is pulled out of the main step
  # funnel (a skip there would masquerade as drop-off and corrupt the cross-step
  # percentages). It is reported HERE against its own honest denominator: of the
  # sessions that were actually SHOWN the step (viewed it), how many completed it
  # vs dropped. "Shown" = viewed, so a session that never saw the step (referral
  # skip) is excluded from both the numerator and the denominator — the drop-off
  # % reflects only people who were genuinely asked.
  screener_sql_referral_source_completion = <<-SQL
    SELECT
      SUM(screenings_viewed_step) AS `Shown`,
      SUM(screenings_completed_step) AS `Completed`,
      SUM(screenings_viewed_step) - SUM(screenings_completed_step) AS `Dropped`,
      ROUND(
        (SUM(screenings_viewed_step) - SUM(screenings_completed_step)) * 100.0
        / NULLIF(SUM(screenings_viewed_step), 0), 1
      ) AS `Drop-off %`
    FROM `${local.bq_dataset}.mart_screener_form_funnel`
    WHERE __STATE_FILTER__
      AND screener_step_name = 'referral-source'
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
  SQL

  # ── Tab 7 (Form Journey): errors by step ────────────────────────────────────
  screener_sql_errors_by_step = <<-SQL
    SELECT
      screener_step_label,
      SUM(total_error_count) AS `Total Errors`
    FROM `${local.bq_dataset}.mart_screener_form_funnel`
    WHERE __STATE_FILTER__
      AND screener_step_name NOT IN ('__form_start__', '__form_complete__')
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY screener_step_label
    HAVING SUM(total_error_count) > 0
    ORDER BY `Total Errors` DESC
  SQL

  # ── Tab 7 (Form Journey): back navigation by step ───────────────────────────
  screener_sql_back_nav_by_step = <<-SQL
    SELECT
      screener_step_label,
      SUM(screenings_navigated_back) AS `Back-Nav Screenings`
    FROM `${local.bq_dataset}.mart_screener_form_funnel`
    WHERE __STATE_FILTER__
      AND screener_step_name NOT IN ('__form_start__', '__form_complete__')
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY screener_step_label
    HAVING SUM(screenings_navigated_back) > 0
    ORDER BY `Back-Nav Screenings` DESC
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
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY program_id
    )
    SELECT
      program_name AS `Program`,
      more_info_screenings AS `More Info`,
      apply_screenings AS `Applied`,
      ROUND(apply_screenings * 100.0 / NULLIF(more_info_screenings, 0), 1) AS `Apply Rate %`
    FROM per_program
    WHERE more_info_screenings > 0
    ORDER BY `Apply Rate %` DESC
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
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY program_id
    )
    SELECT program_name AS `Program`, more_info AS `More Info`, apply AS `Apply`
    FROM per_program
    WHERE more_info > 0 OR apply > 0
    ORDER BY (more_info - apply) DESC
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
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      results_viewed AS `Results Viewed`,
      none_eligible AS `None Eligible`,
      ROUND(none_eligible * 100.0 / NULLIF(results_viewed + none_eligible, 0), 1) AS `% None Eligible`,
      avg_program_count AS `Avg Programs`,
      avg_total_estimated_value AS `Avg Est Value`,
      results_errors AS `Results Errors`
    FROM agg
  SQL

  # ── Tab 9 (Sharing & Saving): share funnel — popup ──────────────────────────
  screener_sql_share_funnel_popup = <<-SQL
    WITH filtered AS (
      SELECT * FROM `${local.bq_dataset}.mart_screener_shares`
      WHERE __STATE_FILTER__
        AND share_location = 'results_popup'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step AS `Funnel Step`, screenings AS `Screenings`
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
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step AS `Funnel Step`, screenings AS `Screenings`
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
      CASE share_channel
        WHEN 'email' THEN 'Email'
        WHEN 'sms' THEN 'SMS'
        WHEN 'whatsapp' THEN 'WhatsApp'
        WHEN 'copy_link' THEN 'Copy Link'
        ELSE COALESCE(share_channel, '(none)')
      END AS `Share Channel`,
      COALESCE(share_provider, '(none)') AS `Share Provider`,
      SUM(total_shares) AS `Total Shares`
    FROM `${local.bq_dataset}.mart_screener_shares`
    WHERE __STATE_FILTER__
      AND share_action = 'send'
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY `Share Channel`, `Share Provider`
    ORDER BY `Total Shares` DESC
  SQL

  # ── Tab 9 (Sharing & Saving): save funnel ───────────────────────────────────
  screener_sql_save_funnel = <<-SQL
    WITH filtered AS (
      SELECT * FROM `${local.bq_dataset}.mart_screener_saves`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step AS `Funnel Step`, screenings AS `Screenings`
    FROM (
      SELECT 'Shown Popup' AS funnel_step, SUM(screenings_shown_popup) AS screenings, 1 AS step_order FROM filtered
      UNION ALL SELECT 'Saved', SUM(screenings_with_save), 2 FROM filtered
    )
    ORDER BY step_order
  SQL

  # ── Tab 9 (Sharing & Saving): saves by channel ──────────────────────────────
  # save_channel is null on two kinds of rows in the mart: the synthetic
  # __saved__/__popup_shown__ funnel rows, and real save events fired before the
  # user picked a channel (e.g. save_action='open'). This is a by-channel
  # breakdown, so channel-less rows have no bar to contribute to: the synthetic
  # rows are excluded by save_action, and un-channeled saves are surfaced under a
  # '(no channel yet)' bucket rather than silently dropped, so the totals still
  # reconcile with the overall save count.
  screener_sql_saves_by_channel = <<-SQL
    SELECT
      CASE save_channel
        WHEN 'email' THEN 'Email'
        WHEN 'sms' THEN 'SMS'
        WHEN 'whatsapp' THEN 'WhatsApp'
        WHEN 'copy_link' THEN 'Copy Link'
        ELSE COALESCE(save_channel, '(no channel yet)')
      END AS `Save Channel`,
      SUM(total_saves) AS `Total Saves`
    FROM `${local.bq_dataset}.mart_screener_saves`
    WHERE __STATE_FILTER__
      AND save_action NOT IN ('__saved__', '__popup_shown__')
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY `Save Channel`
    ORDER BY `Total Saves` DESC
  SQL

  # ── Tab 8 (Results): results-page tab split ─────────────────────────────────
  # % of results-page viewers who opened each results tab. Numerator = distinct
  # screenings that opened the tab; denominator = distinct screenings that loaded
  # results (mart_screener_results_outcomes). A raw count is meaningless without
  # this denominator. Note long_term_benefits is the default tab (≈100%); the
  # signal is the Additional Resources rate.
  screener_sql_tab_split = <<-SQL
    WITH tab_opens AS (
      SELECT
        CASE dimension
          WHEN 'additional_resources' THEN 'Additional Resources'
          WHEN 'long_term_benefits' THEN 'Long-Term Benefits'
          ELSE COALESCE(dimension, '(none)')
        END AS tab_label,
        SUM(distinct_screenings) AS n
      FROM `${local.bq_dataset}.mart_screener_resource_engagement`
      WHERE __STATE_FILTER__
        AND metric = 'tab_open'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY tab_label
    ),
    results_viewers AS (
      SELECT SUM(screenings_results_loaded) AS denom
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      tab_opens.tab_label AS `Tab`,
      ROUND(tab_opens.n * 100.0 / NULLIF((SELECT denom FROM results_viewers), 0), 1) AS `% of Results Viewers`
    FROM tab_opens
    ORDER BY `% of Results Viewers` DESC
  SQL

  # ── Tab 8 (Results): top additional resources ───────────────────────────────
  screener_sql_top_resources = <<-SQL
    SELECT
      dimension AS `Resource`,
      SUM(total_clicks) AS `Clicks`
    FROM `${local.bq_dataset}.mart_screener_resource_engagement`
    WHERE __STATE_FILTER__
      AND metric = 'resource_click'
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY dimension
    ORDER BY `Clicks` DESC
    LIMIT 20
  SQL

  # ── Tab 10 (Overview): language distribution ────────────────────────────────
  # Header language SWITCHES — which languages sessions switch TO via the header
  # language selector. This is header-selector engagement, NOT "language the
  # household speaks" (that intake answer lives on the Households tab). Deduped
  # per session.
  screener_sql_language_distribution = <<-SQL
    SELECT
      language_name AS `Switched To`,
      SUM(distinct_screenings) AS `Sessions`
    FROM `${local.bq_dataset}.mart_screener_language`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY language_name
    ORDER BY `Sessions` DESC
  SQL
}
