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
  # NOTE: this body uses TWO state sentinels. __STATE_FILTER_CESN__ goes on the
  # marts that carry the is_cesn flag and retain null-state rows (form funnel,
  # results outcomes); __STATE_FILTER__ goes on program_interactions, which fires
  # post-white-label (no null-state / no cesn rows, no is_cesn column). The global
  # consumer substitutes the is_cesn predicate for the former and the plain IN-list
  # for the latter; the tenant consumer substitutes its own IN-list for both.
  screener_sql_macro_funnel = <<-SQL
    WITH started AS (
      SELECT SUM(screenings_viewed_step) AS n
      FROM `${local.bq_dataset}.mart_screener_form_funnel`
      WHERE __STATE_FILTER_CESN__
        AND screener_step_name = '__form_start__'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    results AS (
      SELECT SUM(screenings_results_loaded) AS n
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER_CESN__
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
  # as the Overview funnel's "Saw Results" stage), at SESSION grain so it's
  # comparable to the session-counted step bars above.
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
  # Select State is EXCLUDED alongside Referral Source: it is a pre-white-label
  # global page (bare-domain entry), so its view count is a small unrelated
  # population that doesn't belong in the drop-off sequence.
  #
  # A "% of Started" column is added: each stage as a share of the funnel's first
  # (largest) stage, so the drop-off reads as percentages, not just raw counts.
  screener_sql_step_funnel = <<-SQL
    WITH steps AS (
      SELECT
        screener_step_label,
        -- Coalesce to a large-but-below-terminal sentinel so null-numbered form
        -- steps (or any future unmapped step) sort near the end of the form yet
        -- still BEFORE the "Reached Results" terminal bar (999999). A bare
        -- MIN(step_number) with NULLS LAST would drop them after the terminal,
        -- putting the destination in the middle of the flow.
        COALESCE(MIN(screener_step_number), 99999) AS sort_key,
        SUM(screenings_viewed_step) AS screenings
      FROM `${local.bq_dataset}.mart_screener_form_funnel`
      WHERE __STATE_FILTER__
        AND screener_step_name NOT IN ('__form_start__', '__form_complete__', 'referral-source', 'select-state')
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY screener_step_label
    ),
    reached_results AS (
      -- SESSION grain (screenings_results_loaded_by_session), NOT the uid-grain
      -- screenings_results_loaded, so this terminal bar is comparable to the
      -- step bars above — every one of which is a distinct-SESSION count from
      -- the funnel mart. Using the uid count here would silently mix grains.
      SELECT
        'Reached Results' AS screener_step_label,
        999999 AS sort_key,
        SUM(screenings_results_loaded_by_session) AS screenings
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    combined AS (
      SELECT * FROM steps UNION ALL SELECT * FROM reached_results
    )
    SELECT
      screener_step_label,
      screenings AS `Screenings`,
      -- % of the funnel's entry stage (the largest bar = the first step everyone
      -- sees). MAX() OVER () is that denominator; every stage divides into it.
      ROUND(screenings * 100.0 / NULLIF(MAX(screenings) OVER (), 0), 1) AS `% of Started`
    FROM combined
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
  #
  # Shown and Completed are aggregated per (event_date, state, step) in the mart,
  # so they align on the same day: a step's view and its completion fire seconds
  # apart, effectively always within one calendar day. Across a multi-day window
  # both sums therefore count the same cohort of sessions. GREATEST(..., 0) floors
  # the drop at zero to defend against the pathological case of a session that
  # viewed just before midnight of the window's start and completed just after —
  # which would otherwise let Completed exceed Shown and yield a nonsensical
  # negative drop. Clamping keeps the reported figure sane without a session-level
  # cohort join (the per-step mart grain does not expose session keys downstream).
  screener_sql_referral_source_completion = <<-SQL
    SELECT
      SUM(screenings_viewed_step) AS `Shown`,
      SUM(screenings_completed_step) AS `Completed`,
      GREATEST(SUM(screenings_viewed_step) - SUM(screenings_completed_step), 0) AS `Dropped`,
      ROUND(
        GREATEST(SUM(screenings_viewed_step) - SUM(screenings_completed_step), 0) * 100.0
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
  # Error RATE per step: errors at a step ÷ sessions that VIEWED that step, so a
  # deep step isn't penalized for having fewer people reach it. Only synthetic
  # rows are excluded — confirm-information IS a real step and is kept.
  screener_sql_errors_by_step = <<-SQL
    SELECT
      screener_step_label AS `Step`,
      SUM(total_error_count) AS `Total Errors`,
      ROUND(SUM(total_error_count) * 100.0 / NULLIF(SUM(screenings_viewed_step), 0), 1) AS `Errors per 100 Views`
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
  # Raw counts (no rate) — deliberately. A back-nav RATE needs a per-step view
  # denominator, but the steps with the MOST back-nav (confirm-information,
  # member-details, household-basics) currently emit their view under a
  # nonstandard event name (screener_step_* / screener_form_step_*) instead of
  # the clean screener_form_step/view the mart counts, so their view count is 0
  # and a rate would be NULL exactly on the biggest bars. Once the frontend
  # normalizes those view events, this can move to a rate (see the errors card,
  # whose steps all have clean views, for the pattern). confirm-information IS a
  # real step and is kept.
  screener_sql_back_nav_by_step = <<-SQL
    SELECT
      screener_step_label AS `Step`,
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
    SELECT
      program_name AS `Program`,
      more_info AS `More Info`,
      apply AS `Apply`,
      ROUND(apply * 100.0 / NULLIF(more_info, 0), 1) AS `Apply Rate %`
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
  # Counts only COMPLETED saves (save_action = 'send'), mirroring
  # screener_sql_shares_by_channel. A channel is only assigned at 'send'; the
  # 'open' and 'close' actions carry a null channel (the user opened the save
  # popup but had not picked Email/SMS yet). Including those inflated each real
  # channel (the same save counted at open + close + send) and produced a
  # spurious '(no channel yet)' bar. The open→send drop-off — i.e. people who
  # opened the save popup and exited without picking a channel — is shown on the
  # Save Funnel card, which is the correct home for that abandonment signal.
  screener_sql_saves_by_channel = <<-SQL
    SELECT
      CASE save_channel
        WHEN 'email' THEN 'Email'
        WHEN 'sms' THEN 'SMS'
        WHEN 'whatsapp' THEN 'WhatsApp'
        WHEN 'copy_link' THEN 'Copy Link'
        ELSE save_channel
      END AS `Save Channel`,
      SUM(total_saves) AS `Total Saves`
    FROM `${local.bq_dataset}.mart_screener_saves`
    WHERE __STATE_FILTER__
      AND save_action = 'send'
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
