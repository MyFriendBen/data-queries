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
  # A MONOTONIC "furthest step reached" funnel: each bar is the number of sessions
  # that got AT LEAST as far as that step. Built from mart_screener_furthest_step,
  # which records one deepest step rank per session, so "reached >= N" can only
  # decrease as N grows — the funnel cannot bulge (an earlier misdesign counted
  # per-step VIEWS mixed with a results-load terminal, which let back-navigation
  # re-views and saved-link results loads push later bars above earlier ones).
  #
  # The mart is session grain (not pre-aggregated to reached>=N) precisely so the
  # dashboard date range applies correctly: we filter sessions to the window first,
  # THEN expand each surviving session across the step ladder. Cumulative counts
  # baked per-day could not be re-summed across an arbitrary window.
  #
  # Ladder ranks live in the step_ranks CTE (kept in sync with the ranks in
  # int_screener_furthest_step). "Reached Results" is the terminal rank, folded in
  # from screener_results_loaded inside the mart. Referral Source and Select State
  # are intentionally absent from the ladder: both are conditionally shown /
  # pre-white-label, so a skip would masquerade as drop-off. Referral completion is
  # reported on its own honest-denominator card (screener_sql_referral_source_completion).
  #
  # The plotted metric is "% of Started" (bar N ÷ the first, largest bar); the raw
  # session count rides along as `Screenings` for the tooltip.
  screener_sql_step_funnel = <<-SQL
    WITH step_ranks AS (
      SELECT  1 AS step_rank, 'Language'             AS screener_step_label UNION ALL
      SELECT  2, 'Disclaimer'            UNION ALL
      SELECT  3, 'Zip Code'              UNION ALL
      SELECT  4, 'Household Size'        UNION ALL
      SELECT  5, 'Household Basics'      UNION ALL
      SELECT  6, 'Household Members'     UNION ALL
      SELECT  7, 'Member Details'        UNION ALL
      SELECT  8, 'Expenses'              UNION ALL
      SELECT  9, 'Assets'                UNION ALL
      SELECT 10, 'Current Benefits'      UNION ALL
      SELECT 11, 'Additional Resources'  UNION ALL
      SELECT 12, 'Sign Up'               UNION ALL
      SELECT 13, 'Confirm Information'   UNION ALL
      SELECT 14, 'Reached Results'
    ),
    sessions AS (
      SELECT session_key, furthest_step_rank
      FROM `${local.bq_dataset}.mart_screener_furthest_step`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    -- Monotonic by construction: a session contributes to rank N iff it reached at
    -- least N, so reached(N) >= reached(N+1) always.
    funnel AS (
      SELECT
        r.step_rank,
        r.screener_step_label,
        COUNT(DISTINCT s.session_key) AS screenings
      FROM step_ranks r
      LEFT JOIN sessions s ON s.furthest_step_rank >= r.step_rank
      GROUP BY r.step_rank, r.screener_step_label
    ),
    -- Denominator = the first (rank 1) stage: the population that entered the funnel.
    entry AS (
      SELECT screenings AS entry_screenings FROM funnel WHERE step_rank = 1
    )
    SELECT
      screener_step_label,
      ROUND(screenings * 100.0 / NULLIF((SELECT entry_screenings FROM entry), 0), 1) AS `% of Started`,
      screenings AS `Screenings`
    FROM funnel
    WHERE screenings > 0
    ORDER BY step_rank
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
  # Raw error count is the plotted bar; a "% of Step Views" rides along for the
  # hover (errors ÷ distinct sessions that viewed the step). On the current clean
  # event set every step emits a clean screener_form_step/view, so the per-step
  # view denominator is populated for all bars — including the household steps,
  # which now consolidate to a single "Household Members" view count (the old
  # member-details/household-basics 0-view problem was stale pre-cutover data).
  # NULLIF guards the rare step with errors but no captured view.
  screener_sql_errors_by_step = <<-SQL
    SELECT
      screener_step_label AS `Step`,
      SUM(total_error_count) AS `Total Errors`,
      ROUND(SUM(total_error_count) * 100.0 / NULLIF(SUM(screenings_viewed_step), 0), 1) AS `% of Step Views`
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
  # Raw back-nav count is the plotted bar; a "% of Step Views" rides along for the
  # hover (back-navigations ÷ distinct sessions that viewed the step). Same clean
  # per-step view denominator as the errors card — every step now emits a clean
  # view, so no bar is left without a rate. confirm-information IS a real step and
  # is kept.
  screener_sql_back_nav_by_step = <<-SQL
    SELECT
      screener_step_label AS `Step`,
      SUM(screenings_navigated_back) AS `Back-Nav Screenings`,
      ROUND(SUM(screenings_navigated_back) * 100.0 / NULLIF(SUM(screenings_viewed_step), 0), 1) AS `% of Step Views`
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

  # ── Tab 8 (Results): results revisits distribution ──────────────────────────
  # How many screenings loaded their results page once vs. multiple times.
  # mart_screener_results_revisits is one row per screening with its lifetime
  # results-load count; this buckets that count into 1x / 2x / 3+ and counts the
  # screenings in each bucket. The date filter is on the screening's FIRST
  # results-load date, so the window selects a cohort of screenings first seen in
  # it. A sort_key keeps the buckets in order (Metabase would otherwise sort the
  # string labels alphabetically, putting "3+ times" first).
  screener_sql_results_revisits = <<-SQL
    SELECT
      CASE
        WHEN results_load_count = 1 THEN '1 time'
        WHEN results_load_count = 2 THEN '2 times'
        ELSE '3+ times'
      END AS `Times Viewed`,
      MIN(LEAST(results_load_count, 3)) AS sort_key,
      COUNT(*) AS `Screenings`
    FROM `${local.bq_dataset}.mart_screener_results_revisits`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY `Times Viewed`
    ORDER BY sort_key
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
        ELSE COALESCE(save_channel, '(none)')
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

  # ══════════════════════════════════════════════════════════════════════════════
  # Analytics v2 cards (MFB-1306) — new event families
  # ══════════════════════════════════════════════════════════════════════════════

  # ── Results: per-program conversion (more-info ÷ shown, apply ÷ more-info) ──────
  # Pivots interaction_type from mart_screener_program_interactions to compute the
  # two conversion rates now that program_shown gives a "shown" denominator.
  # NOTE: screenings_with_interaction is deduped per DAY in the mart, so summing
  # across a multi-day window counts a screening active on N days N times — the
  # rate is "screening-days", not truly-distinct screenings. This matches every
  # other rate card over these daily-grain marts (e.g. apply_conversion_rate).
  screener_sql_program_conversion = <<-SQL
    WITH per_program AS (
      SELECT
        program_id,
        MAX(program_name) AS program_name,
        SUM(CASE WHEN interaction_type = 'shown'     THEN screenings_with_interaction ELSE 0 END) AS shown,
        SUM(CASE WHEN interaction_type = 'more_info' THEN screenings_with_interaction ELSE 0 END) AS more_info,
        SUM(CASE WHEN interaction_type = 'apply'     THEN screenings_with_interaction ELSE 0 END) AS applied
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY program_id
    )
    SELECT
      program_name AS `Program`,
      shown AS `Shown`,
      more_info AS `More Info`,
      applied AS `Applied`,
      ROUND(more_info * 100.0 / NULLIF(shown, 0), 1) AS `More-Info Rate %`,
      ROUND(applied * 100.0 / NULLIF(more_info, 0), 1) AS `Apply Rate %`
    FROM per_program
    WHERE shown > 0
    ORDER BY `More-Info Rate %` DESC
  SQL

  # ── Results: navigator engagement (program × navigator × method) ────────────────
  screener_sql_navigator_engagement = <<-SQL
    SELECT
      program_name AS `Program`,
      navigator_name AS `Navigator`,
      CASE contact_method
        WHEN 'website' THEN 'Website'
        WHEN 'email' THEN 'Email'
        WHEN 'phone' THEN 'Phone'
        ELSE COALESCE(contact_method, '(unknown)')
      END AS `Method`,
      SUM(screenings_with_engagement) AS `Screenings`
    FROM `${local.bq_dataset}.mart_screener_navigator_engagement`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY `Program`, `Navigator`, `Method`
    ORDER BY `Screenings` DESC
  SQL

  # ── Results: additional-resource engagement (more-info → website/phone) ─────────
  # Resources treated like programs: the expand ("More Info") count and the
  # contact clicks split by method, per resource.
  screener_sql_resource_engagement = <<-SQL
    SELECT
      dimension AS `Resource`,
      SUM(CASE WHEN metric = 'resource_more_info' THEN total_clicks ELSE 0 END) AS `More Info`,
      SUM(CASE WHEN metric = 'resource_click' AND contact_method = 'website' THEN total_clicks ELSE 0 END) AS `Website`,
      SUM(CASE WHEN metric = 'resource_click' AND contact_method = 'phone'   THEN total_clicks ELSE 0 END) AS `Phone`
    FROM `${local.bq_dataset}.mart_screener_resource_engagement`
    WHERE __STATE_FILTER__
      AND metric IN ('resource_more_info', 'resource_click')
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY `Resource`
    HAVING (`More Info` + `Website` + `Phone`) > 0
    ORDER BY `More Info` DESC
    LIMIT 20
  SQL

  # ── Results: Additional Resources tab engagement (count + % of results viewers) ─
  # TWO sentinels (like macro_funnel): the `tab` CTE reads
  # mart_screener_resource_engagement (no is_cesn column) → plain __STATE_FILTER__;
  # the `viewers` CTE reads mart_screener_results_outcomes (carries is_cesn) →
  # __STATE_FILTER_CESN__ so the global denominator excludes CESN, matching the
  # numerator (which has no CESN rows) and every other global funnel-rate card.
  screener_sql_resources_tab_engagement = <<-SQL
    WITH tab AS (
      SELECT SUM(distinct_screenings) AS n
      FROM `${local.bq_dataset}.mart_screener_resource_engagement`
      WHERE __STATE_FILTER__
        AND metric = 'tab_open'
        AND dimension = 'additional_resources'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    viewers AS (
      SELECT SUM(screenings_results_loaded) AS denom
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER_CESN__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      (SELECT n FROM tab) AS `Opened Additional Resources`,
      ROUND((SELECT n FROM tab) * 100.0 / NULLIF((SELECT denom FROM viewers), 0), 1) AS `% of Results Viewers`
  SQL

  # ── Form Journey: results scroll depth (funnel by tab) ──────────────────────────
  # Raw screenings-reached-depth is the plotted bar; a "% of Results Viewers"
  # rides along for the hover — the share of everyone who loaded a results page
  # that scrolled at least this far on the tab. Denominator = distinct screenings
  # that fired screener_results_loaded (uid grain, matching the scroll mart's
  # uid-deduped counts) over the same window/scope.
  screener_sql_scroll_depth = <<-SQL
    WITH viewers AS (
      SELECT SUM(screenings_results_loaded) AS denom
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      CAST(depth AS STRING) || '%' AS `Depth`,
      CASE tab_name
        WHEN 'long_term_benefits' THEN 'Long-Term Benefits'
        WHEN 'additional_resources' THEN 'Additional Resources'
        ELSE COALESCE(tab_name, '(unknown)')
      END AS `Tab`,
      SUM(screenings_reached_depth) AS `Screenings`,
      ROUND(SUM(screenings_reached_depth) * 100.0 / NULLIF((SELECT denom FROM viewers), 0), 1) AS `% of Results Viewers`
    FROM `${local.bq_dataset}.mart_screener_scroll_depth`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY depth, `Tab`
    ORDER BY depth, `Tab`
  SQL

  # ── Form Journey: help-tooltip clicks by TOPIC (which tooltips drive confusion) ──
  # The screener_help_click event carries only help_topic — the topic string is
  # itself step-identifying (e.g. "income", "household size"), and the leaf tooltip
  # component can't cheaply resolve its owning form step — so there is no step
  # dimension to slice by. Grouping by topic alone is the honest cut.
  screener_sql_help_by_topic = <<-SQL
    SELECT
      dimension AS `Help Topic`,
      SUM(total_clicks) AS `Clicks`
    FROM `${local.bq_dataset}.mart_screener_help`
    WHERE __STATE_FILTER__
      AND metric = 'help_click'
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY `Help Topic`
    ORDER BY `Clicks` DESC
  SQL

  # ── Results: "More Help / 211" CTA clicks ───────────────────────────────────────
  screener_sql_get_help_clicks = <<-SQL
    SELECT SUM(total_clicks) AS `More Help Clicks`
    FROM `${local.bq_dataset}.mart_screener_help`
    WHERE __STATE_FILTER__
      AND metric = 'get_help_click'
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
  SQL

  # ── Form Journey: which validation errors, by step ──────────────────────────────
  # Reads the humanized error columns produced in mart_screener_form_errors
  # (error_field_label / error_problem) — the raw "field:rule" parsing + friendly
  # labeling lives in the mart, so this card is a plain GROUP BY. Adding a friendly
  # label for a new field is a one-line change in the mart, not here.
  screener_sql_errors_detail = <<-SQL
    SELECT
      screener_step_label AS `Step`,
      error_field_label AS `Field`,
      error_problem AS `Problem`,
      SUM(total_errors) AS `Errors`
    FROM `${local.bq_dataset}.mart_screener_form_errors`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY `Step`, `Field`, `Problem`
    ORDER BY `Errors` DESC
    LIMIT 25
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
