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
      UNION ALL SELECT 'Viewed Details',     (SELECT n FROM more_info), 3
      UNION ALL SELECT 'Clicked Apply',      (SELECT n FROM apply),     4
    )
    ORDER BY step_order
  SQL

  # ── Tab 7 (Form Journey): step drop-off funnel ──────────────────────────────
  # "Furthest step reached" funnel: each bar counts sessions that got AT LEAST as
  # far as that step, so it's monotonic by construction. mart_screener_furthest_step
  # is session-grain (one deepest rank per session), so the dashboard date filter
  # applies before the reached>=N expansion.
  #
  # The ranked ladder comes from mart_screener_step_ladder (funnel_rank not null) —
  # the single source of truth (screener_step_ladder macro), so this card, the
  # int model, and every label stay in sync. Off-ladder steps (referral, select-
  # state, member-basics, cesn-*) have null funnel_rank and are excluded here.
  #
  # Plotted metric is "% of Started" (bar N ÷ first/largest bar); raw session count
  # rides along as `Sessions`.
  #
  # NOTE — this funnel is SESSION-keyed (COUNT DISTINCT session_key), not screening-
  # keyed: the early steps run before a screening/screener_uid even exists (created at
  # step 3), so a session key is the only unit that spans the whole funnel. The bottom
  # "Reached Results" bar folds in the SAME screener_results_loaded event the Results
  # tab uses (see int_screener_furthest_step) — so it is NOT a different event, it is
  # the same event counted by a different unit. It counts BROWSER SESSIONS that loaded
  # results; the Results-tab "Results Viewed" scalar counts distinct SCREENINGS
  # (screener_uid). One screening that loads its results across several sessions (e.g.
  # returning to a saved result in a new session/device) counts once on the Results tab
  # but once per session here — so this bar is >= the screening count by exactly the
  # amount of results-revisiting. That is expected, not a discrepancy.
  screener_sql_step_funnel = <<-SQL
    WITH step_ranks AS (
      SELECT funnel_rank AS step_rank, screener_step_label
      FROM `${local.bq_dataset}.mart_screener_step_ladder`
      WHERE funnel_rank IS NOT NULL
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
        COUNT(DISTINCT s.session_key) AS sessions
      FROM step_ranks r
      LEFT JOIN sessions s ON s.furthest_step_rank >= r.step_rank
      GROUP BY r.step_rank, r.screener_step_label
    ),
    -- Denominator = the first (rank 1) stage: the population that entered the funnel.
    entry AS (
      SELECT sessions AS entry_sessions FROM funnel WHERE step_rank = 1
    )
    SELECT
      screener_step_label,
      ROUND(sessions * 100.0 / NULLIF((SELECT entry_sessions FROM entry), 0), 1) AS `% of Started`,
      sessions AS `Sessions`
    FROM funnel
    WHERE sessions > 0
    ORDER BY step_rank
  SQL

  # ── Tab 7 (Form Journey): errors by step ────────────────────────────────────
  # The PLOTTED bar is "% of Viewers with 1+ Errors" — of the DISTINCT sessions
  # that viewed the step, the share that hit at least one error on it. Reads the
  # session-grain mart_screener_step_facts (one row per session x step, deduped
  # across days), so both numerator and denominator are exact distinct-session
  # counts over the window — no multi-day double-count. Normalizes for traffic so
  # steps are comparable by error-proneness, not volume. Total error EVENTS (raw
  # attempts, inflated by retries) ride along for the hover. NULLIF guards a step
  # with errors but no captured view.
  screener_sql_errors_by_step = <<-SQL
    SELECT
      screener_step_label AS `Step`,
      ROUND(COUNTIF(errored) * 100.0 / NULLIF(COUNTIF(viewed), 0), 1) AS `% of Viewers with 1+ Errors`,
      COUNTIF(errored) AS `Screenings with an Error`,
      SUM(error_events) AS `Total Errors`
    FROM `${local.bq_dataset}.mart_screener_step_facts`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY screener_step_label
    HAVING COUNTIF(errored) > 0
    ORDER BY `% of Viewers with 1+ Errors` DESC
  SQL

  # ── Tab 7 (Form Journey): back navigation by step ───────────────────────────
  # The PLOTTED bar is "% of Viewers who Went Back" — of the DISTINCT sessions that
  # viewed the step, the share that navigated back from it. Session-grain source
  # (mart_screener_step_facts, deduped across days) so both sides are exact
  # distinct-session counts over the window. Normalized for traffic like the errors
  # card. Raw back-nav count on hover. confirm-information IS a real step and kept.
  screener_sql_back_nav_by_step = <<-SQL
    SELECT
      screener_step_label AS `Step`,
      ROUND(COUNTIF(navigated_back) * 100.0 / NULLIF(COUNTIF(viewed), 0), 1) AS `% of Viewers who Went Back`,
      COUNTIF(navigated_back) AS `Back-Nav Screenings`
    FROM `${local.bq_dataset}.mart_screener_step_facts`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY screener_step_label
    HAVING COUNTIF(navigated_back) > 0
    ORDER BY `% of Viewers who Went Back` DESC
  SQL

  # NOTE: the former per-program cards screener_sql_apply_conversion_rate and
  # screener_sql_more_info_vs_apply were consolidated into two top-15 row charts
  # (screener_sql_program_most_shown + screener_sql_program_engagement) plus the full
  # screener_sql_program_conversion table (rates, shown>=20) further down.

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
  # "Results Viewed" comes from mart_screener_results_revisits (screening-grain,
  # one row per screener_uid) via COUNT(*), so a screening that loads results on
  # >1 day isn't double-counted — summing the per-day screenings_results_loaded
  # would inflate it. The other outcome counts (none-eligible, errors) and the avg
  # columns stay on the outcomes mart; none-eligible/errors are rare terminal
  # states (a screening lands in one once), so their per-day sum is effectively
  # screening-grain already.
  # ── Results outcome scalars (three standalone cards) ─────────────────────────
  # Replaces the old multi-column "Results Outcome KPIs" table with three scalar
  # cards. All three key off the same results-viewer base so they're directly
  # comparable. "Results Viewed" is DISTINCT screenings that loaded results at
  # least once (one row per screener_uid in mart_screener_results_revisits —
  # repeat views collapse to one), NOT total views.

  # (1) Results Viewed — distinct screenings that reached the results page.
  screener_sql_results_viewed = <<-SQL
    SELECT COUNT(*) AS `Results Viewed`
    FROM `${local.bq_dataset}.mart_screener_results_revisits`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
  SQL

  # (2) % Eligible for 1+ Program — complement of none-eligible over results-viewers.
  # none_eligible screenings are a subset of results-viewers (the FE fires
  # screener_results_loaded AND, independently, screener_results_none_eligible when
  # program_count = 0), so eligible = viewers - none_eligible, over viewers.
  # results_viewed is per-screening distinct (revisits mart, lifetime). none_eligible
  # comes from the daily-grain outcomes mart; SUM across days is distinct-per-day, but
  # since it's a strict subset of the same viewer set the subtraction stays bounded
  # (verified tiny in practice) — kept on the viewer denominator, which is the right unit.
  screener_sql_results_pct_eligible = <<-SQL
    WITH viewed AS (
      SELECT COUNT(*) AS n
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    ne AS (
      SELECT SUM(screenings_none_eligible) AS n
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT ROUND(
      ((SELECT n FROM viewed) - COALESCE((SELECT n FROM ne), 0)) * 100.0
      / NULLIF((SELECT n FROM viewed), 0), 1
    ) AS `% Eligible for 1+ Program`
  SQL

  # (3) Results Error Rate % — distinct erroring screenings ÷ distinct results-viewers.
  # Denominator is the same results-viewer base as (1)/(2) (per user: "of people who
  # got to results, how many errored"). error count is daily-distinct summed; negligible
  # multi-day inflation at current volume, and the viewer base is the intended unit.
  screener_sql_results_error_rate = <<-SQL
    WITH viewed AS (
      SELECT COUNT(*) AS n
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    err AS (
      SELECT SUM(screenings_results_error) AS n
      FROM `${local.bq_dataset}.mart_screener_results_outcomes`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT ROUND(
      COALESCE((SELECT n FROM err), 0) * 100.0
      / NULLIF((SELECT n FROM viewed), 0), 1
    ) AS `Results Error Rate %`
  SQL

  # ── Tab 9 (Sharing & Saving): share funnel — popup ──────────────────────────
  # Share popup (results page) funnel: Shown (reached results) -> Opened -> Sent.
  # The "Shown" base is results-page viewers (mart_screener_results_revisits, the
  # shared results-viewer denominator, CESN-aware sentinel) — the popup only appears
  # on results. Share actions come from mart_screener_shares (screening-keyed).
  screener_sql_share_funnel_popup = <<-SQL
    WITH filtered AS (
      SELECT * FROM `${local.bq_dataset}.mart_screener_shares`
      WHERE __STATE_FILTER__
        AND share_location = 'results_popup'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    shown AS (
      SELECT COUNT(*) AS n
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER_CESN__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step AS `Funnel Step`, screenings AS `Screenings`
    FROM (
      SELECT 'Shown (reached results)' AS funnel_step, (SELECT n FROM shown) AS screenings, 1 AS step_order
      UNION ALL
      SELECT 'Opened',
             SUM(CASE WHEN share_action = 'open' THEN screenings_with_share ELSE 0 END),
             2
      FROM filtered
      UNION ALL
      SELECT 'Sent',
             SUM(CASE WHEN share_action = 'send' THEN screenings_with_share ELSE 0 END),
             3
      FROM filtered
    )
    ORDER BY step_order
  SQL

  # ── Tab 9 (Sharing & Saving): share funnel — footer ─────────────────────────
  # Share footer funnel: Shown (started the screener) -> Opened -> Sent. The footer
  # (with its Share button) renders on ~every page, so the "Shown" base is screenings
  # that started the form (form_start on mart_screener_form_funnel, is_cesn + null-
  # state aware). Share actions come from mart_screener_shares (footer location).
  screener_sql_share_funnel_footer = <<-SQL
    WITH filtered AS (
      SELECT * FROM `${local.bq_dataset}.mart_screener_shares`
      WHERE __STATE_FILTER__
        AND share_location = 'footer'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    shown AS (
      SELECT SUM(screenings_viewed_step) AS n
      FROM `${local.bq_dataset}.mart_screener_form_funnel`
      WHERE __STATE_FILTER_CESN__
        AND screener_step_name = '__form_start__'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step AS `Funnel Step`, screenings AS `Screenings`
    FROM (
      SELECT 'Shown (started screener)' AS funnel_step, (SELECT n FROM shown) AS screenings, 1 AS step_order
      UNION ALL
      SELECT 'Opened',
             SUM(CASE WHEN share_action = 'open' THEN screenings_with_share ELSE 0 END),
             2
      FROM filtered
      UNION ALL
      SELECT 'Sent',
             SUM(CASE WHEN share_action = 'send' THEN screenings_with_share ELSE 0 END),
             3
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
  # Save funnel: Shown (reached results) -> Opened Save Popup -> Saved. Save is only
  # offered on the results page (BackAndSaveButtons), so the "Shown" base is results-
  # page viewers (shared results-viewer denominator, CESN-aware sentinel). Popup +
  # save come from mart_screener_saves.
  screener_sql_save_funnel = <<-SQL
    WITH filtered AS (
      SELECT * FROM `${local.bq_dataset}.mart_screener_saves`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    shown AS (
      SELECT COUNT(*) AS n
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER_CESN__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT funnel_step AS `Funnel Step`, screenings AS `Screenings`
    FROM (
      SELECT 'Shown (reached results)' AS funnel_step, (SELECT n FROM shown) AS screenings, 1 AS step_order
      UNION ALL SELECT 'Opened Save Popup', SUM(screenings_shown_popup), 2 FROM filtered
      UNION ALL SELECT 'Saved', SUM(screenings_with_save), 3 FROM filtered
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

  # NOTE: screener_sql_top_resources (the "Top Additional Resources" single-metric
  # bar) was removed — the "Additional Resource Engagement" chart (below) supersedes
  # it: same top-20 resources plus the more-info / website / phone breakdown.

  # ══════════════════════════════════════════════════════════════════════════════
  # Analytics v2 cards — new event families
  # ══════════════════════════════════════════════════════════════════════════════

  # ── Results: per-program conversion (more-info ÷ shown, apply ÷ more-info) ──────
  # Program engagement, from mart_screener_program_interactions. Split into two
  # cards: this VOLUME chart (all programs, raw Shown/More Info/Applied counts) and
  # the RATE chart below (conversion rates, min-Shown filtered).
  #
  # No "Other" bucket — every program is shown individually.
  # NOTE: screenings_with_interaction is deduped per DAY in the mart, so summing
  # across a multi-day window is "screening-days", not truly-distinct screenings —
  # consistent with the other daily-grain rate cards.
  # Most-shown programs — top 15 by raw Shown count, for a horizontal (row) bar chart.
  # Bounded to 15 so the chart stays readable AND to sidestep Metabase 0.56's "Other"
  # bucketing (a ~115-row bar chart buckets the tail; a top-N never trips it). The full
  # per-program counts live in the Conversion Rates table below.
  screener_sql_program_most_shown = <<-SQL
    SELECT
      program_name AS `Program`,
      SUM(CASE WHEN interaction_type = 'shown' THEN screenings_with_interaction ELSE 0 END) AS `Shown`
    FROM `${local.bq_dataset}.mart_screener_program_interactions`
    WHERE __STATE_FILTER__
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY program_name
    HAVING `Shown` > 0
    ORDER BY `Shown` DESC
    LIMIT 15
  SQL

  # Program engagement — top 15 by Viewed-Details Rate % (more-info ÷ shown), for a row
  # bar chart. Same shown >= 20 floor as the Conversion Rates table so a program with a
  # handful of impressions and a fluky rate can't top the ranking. Bounded to 15 for
  # readability and to avoid the "Other" bucket. Rate % also appears in the table below
  # (intentional: this is the at-a-glance visual, the table is the sortable detail).
  screener_sql_program_engagement = <<-SQL
    WITH per_program AS (
      SELECT
        program_name,
        SUM(CASE WHEN interaction_type = 'shown'     THEN screenings_with_interaction ELSE 0 END) AS shown,
        SUM(CASE WHEN interaction_type = 'more_info' THEN screenings_with_interaction ELSE 0 END) AS more_info
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY program_name
    )
    SELECT
      program_name AS `Program`,
      ROUND(more_info * 100.0 / NULLIF(shown, 0), 1) AS `Viewed-Details Rate %`
    FROM per_program
    WHERE shown >= 20
    ORDER BY `Viewed-Details Rate %` DESC
    LIMIT 15
  SQL

  # Program conversion RATES. Only programs shown to >= 20 screenings, because
  # program_shown events are dropped by GA4 when a screening's ~40 impressions fire
  # in one tick (verified: hundreds of more_info clicks have no matching shown
  # event) — so per-program rates on a tiny Shown denominator are unreliable and can
  # exceed 100%. The >= 20 floor also just excludes statistically-noisy low-n rates.
  # Once the FE batches the shown events (FE gaps ticket), this can relax toward a
  # smaller noise-only floor, but should never be 0. No "Other" bucket.
  screener_sql_program_conversion = <<-SQL
    WITH per_program AS (
      SELECT
        program_name,
        SUM(CASE WHEN interaction_type = 'shown'     THEN screenings_with_interaction ELSE 0 END) AS shown,
        SUM(CASE WHEN interaction_type = 'more_info' THEN screenings_with_interaction ELSE 0 END) AS more_info,
        SUM(CASE WHEN interaction_type = 'apply'     THEN screenings_with_interaction ELSE 0 END) AS applied
      FROM `${local.bq_dataset}.mart_screener_program_interactions`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY program_name
    )
    SELECT
      program_name AS `Program`,
      shown AS `Shown`,
      more_info AS `Viewed Details`,
      applied AS `Applied`,
      ROUND(more_info * 100.0 / NULLIF(shown, 0), 1)     AS `Shown -> Details %`,
      ROUND(applied * 100.0 / NULLIF(more_info, 0), 1)   AS `Details -> Applied %`,
      ROUND(applied * 100.0 / NULLIF(shown, 0), 1)       AS `Shown -> Applied %`
    FROM per_program
    WHERE shown >= 20
    ORDER BY `Shown -> Details %` DESC
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
      -- Screening-grain results-viewer count (mart_screener_results_revisits,
      -- deduped across days) — the shared denominator for the results-engagement
      -- scalars. Carries is_cesn, so the CESN-aware sentinel applies on the global card.
      SELECT COUNT(*) AS denom
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER_CESN__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      ROUND((SELECT n FROM tab) * 100.0 / NULLIF((SELECT denom FROM viewers), 0), 1) AS `% of Results Viewers`,
      (SELECT n FROM tab) AS `Opened Additional Resources`
  SQL

  # ── Form Journey: results scroll depth (distribution by tab) ────────────────────
  # mart_screener_scroll_depth is the FURTHEST depth each screening reached per tab
  # (a partition — every scroller lands in exactly one depth bucket). The PLOTTED
  # metric is "% of Tab Scrollers": of the screenings that scrolled AT ALL on a
  # tab, the share whose deepest scroll was this bucket. It's the bar (not a side
  # column) because Metabase won't show an extra column in a multi-series tooltip;
  # the raw screening count rides along for the hover.
  #
  # Denominator = total scrollers on that TAB (sum of the tab's buckets), via a
  # window SUM over the same filtered rows — NOT results_loaded, which is a
  # different cohort (a screening can scroll on a different day than it loaded
  # results, or load results before the epoch, pushing the ratio past 100%). By
  # construction each tab's buckets now sum to ~100%.
  #
  # The Depth axis is labeled with NUMBERED PAGE-FRACTION WORDS ("1. Quarter Page"
  # … "4. Full Page"), not "25%…100%", so the depth buckets can't be visually
  # confused with the "% of Tab Scrollers" measure. The leading "N." is a sort key:
  # Metabase sorts a bar chart's category axis ALPHABETICALLY (it ignores SQL row
  # order and does not honor graph.x_axis.scale = "ordinal" for this in v0.56), so
  # the numeric prefix is what forces Quarter -> Full order.
  screener_sql_scroll_depth = <<-SQL
    WITH by_bucket AS (
      SELECT
        depth,
        tab_name,
        SUM(screenings_reached_depth) AS screenings
      FROM `${local.bq_dataset}.mart_screener_scroll_depth`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY depth, tab_name
    )
    SELECT
      CASE depth
        WHEN 25 THEN '1. Quarter Page'
        WHEN 50 THEN '2. Half Page'
        WHEN 75 THEN '3. Three-Quarter Page'
        WHEN 100 THEN '4. Full Page'
        ELSE CAST(depth AS STRING) || '%'
      END AS `Depth`,
      CASE tab_name
        WHEN 'long_term_benefits' THEN 'Long-Term Benefits'
        WHEN 'additional_resources' THEN 'Additional Resources'
        ELSE COALESCE(tab_name, '(unknown)')
      END AS `Tab`,
      ROUND(screenings * 100.0 / NULLIF(SUM(screenings) OVER (PARTITION BY tab_name), 0), 1) AS `% of Tab Scrollers`,
      screenings AS `Screenings`
    FROM by_bucket
    ORDER BY depth, `Tab`
  SQL

  # ── Form Journey: help-tooltip clicks by TOPIC (which tooltips drive confusion) ──
  # Sliced by help_topic (itself step-identifying, e.g. "income", "household
  # assets"). The current event contract adds screener_step_name to
  # screener_help_click, which will enable a per-step help RATE (clicks ÷ step
  # viewers) in a follow-up; until that data is flowing, grouping by topic is the
  # available cut.
  screener_sql_help_by_topic = <<-SQL
    SELECT
      -- Humanize the kebab-case help_topic slug generically (dash -> space,
      -- Title Case) so any current OR future topic reads cleanly without a
      -- hardcoded map: 'household-assets' -> 'Household Assets'.
      INITCAP(REPLACE(dimension, '-', ' ')) AS `Help Topic`,
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

  # ── Form Journey: household-member add/edit/delete actions ──────────────────────
  # How people build their household on the member step. Bar = distinct screenings
  # per action; total events on hover. The numeric sort_key orders add->edit->delete
  # (Metabase sorts the category axis alphabetically otherwise).
  # Bar = distinct screenings per action (COUNT(DISTINCT screener_uid) — the mart is
  # screening-grain, deduped across days, so this is correct over any window). Total
  # events (additive) on hover. sort_key orders add->edit->delete.
  # The PLOTTED bar is "% of Household-Step Viewers" — of the screenings that engaged
  # the roster step, the share that took each action. BOTH numerator and denominator
  # count distinct screener_uid (screening grain) so the ratio is valid — a
  # session-keyed denominator would mix grains and exceed 100% (one browser session
  # can run multiple screenings). Denominator = screenings that VIEWED the member step
  # OR took a member action (union), from the screening-keyed views mart + the section
  # mart. The union guarantees every actor is in the denominator, so the bar can never
  # exceed 100% even at a window's start edge (where an action's paired view may fall
  # just below the date floor). Spans both the new 'member-basics' slug and the
  # pre-MFB-1348 'household-members' slug for cutover coverage. Raw count + total
  # events on hover. sort_key orders add->edit->delete.
  screener_sql_household_member_engagement = <<-SQL
    WITH viewers AS (
      SELECT COUNT(DISTINCT screener_uid) AS n FROM (
        SELECT screener_uid
        FROM `${local.bq_dataset}.mart_screener_step_views_by_screening`
        WHERE __STATE_FILTER__
          AND screener_step_name IN ('member-basics', 'household-members')
          AND viewed
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
        UNION DISTINCT
        SELECT screener_uid
        FROM `${local.bq_dataset}.mart_screener_section_engagement`
        WHERE __STATE_FILTER__
          AND section = 'Household Members'
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      )
    )
    SELECT `Action`, `% of Household-Step Viewers`, `Screenings`, `Total Actions` FROM (
      SELECT
        CASE action WHEN 'add' THEN 1 WHEN 'edit' THEN 2 WHEN 'delete' THEN 3 ELSE 4 END AS sort_key,
        INITCAP(action) AS `Action`,
        ROUND(COUNT(DISTINCT screener_uid) * 100.0 / NULLIF((SELECT n FROM viewers), 0), 1) AS `% of Household-Step Viewers`,
        COUNT(DISTINCT screener_uid) AS `Screenings`,
        SUM(total_actions) AS `Total Actions`
      FROM `${local.bq_dataset}.mart_screener_section_engagement`
      WHERE __STATE_FILTER__
        AND section = 'Household Members'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY action, sort_key
    )
    ORDER BY sort_key
  SQL

  # ── Form Journey: income-source add/delete actions ──────────────────────────────
  # Raw screening + action counts (no % denominator). A per-page rate ("% of member
  # detail pages that added income") is the meaningful metric here but needs a FE
  # member/page index the income event doesn't yet carry — tracked on the standing
  # FE analytics-gaps ticket. Until then, counts answer "does income entry happen".
  screener_sql_income_source_engagement = <<-SQL
    SELECT `Action`, `Screenings`, `Total Actions` FROM (
      SELECT
        CASE action WHEN 'add' THEN 1 WHEN 'edit' THEN 2 WHEN 'delete' THEN 3 ELSE 4 END AS sort_key,
        INITCAP(action) AS `Action`,
        COUNT(DISTINCT screener_uid) AS `Screenings`,
        SUM(total_actions) AS `Total Actions`
      FROM `${local.bq_dataset}.mart_screener_section_engagement`
      WHERE __STATE_FILTER__
        AND section = 'Income Sources'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY action, sort_key
    )
    ORDER BY sort_key
  SQL

  # ── Form Journey: confirmation-page edits by section ─────────────────
  # Which review-page sections people go back to change before submitting, as a % of
  # the screenings that reached the confirmation page (confirm-information step —
  # session-grain step-facts, deduped across days). Raw screening count on hover.
  screener_sql_confirmation_edits = <<-SQL
    WITH viewers AS (
      SELECT COUNT(DISTINCT session_key) AS n
      FROM `${local.bq_dataset}.mart_screener_step_facts`
      WHERE __STATE_FILTER__
        AND screener_step_name = 'confirm-information'
        AND viewed
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT `Section`, `% of Confirmation Viewers`, `Screenings` FROM (
      SELECT
        section_label AS `Section`,
        ROUND(SUM(screenings) * 100.0 / NULLIF((SELECT n FROM viewers), 0), 1) AS `% of Confirmation Viewers`,
        SUM(screenings) AS `Screenings`
      FROM `${local.bq_dataset}.mart_screener_confirmation_edits`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      GROUP BY section_label
    )
    ORDER BY `Screenings` DESC
  SQL

  # ── Form Journey: sign-up consent opt-in rates ───────────────────────
  # Of screenings that completed sign-up, the % opting into SMS vs email contact.
  screener_sql_signup_consent = <<-SQL
    WITH agg AS (
      SELECT
        SUM(signups) AS signups,
        SUM(sms_opt_ins) AS sms,
        SUM(email_opt_ins) AS email
      FROM `${local.bq_dataset}.mart_screener_signup_consent`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT `Channel`, `% Opted In`, `Opt-Ins` FROM (
      SELECT 1 AS sort_key, 'SMS' AS `Channel`,
        ROUND(sms * 100.0 / NULLIF(signups, 0), 1) AS `% Opted In`, sms AS `Opt-Ins` FROM agg
      UNION ALL
      SELECT 2, 'Email',
        ROUND(email * 100.0 / NULLIF(signups, 0), 1), email FROM agg
    )
    ORDER BY sort_key
  SQL

  # ── Results: citizenship filter usage ────────────────────────────────
  # Distinct screenings that engaged the results filter. Only the citizenship
  # filter exists, and the chosen option is never captured (PII) — this is a
  # yes/no engagement count, not a breakdown.
  # % of results-page viewers who used the citizenship filter. Denominator is the
  # shared results-viewer count (mart_screener_results_revisits, CESN-aware sentinel)
  # used by the sibling results-engagement cards so all three are comparable. Raw
  # screening count on hover.
  screener_sql_filter_usage = <<-SQL
    WITH engaged AS (
      SELECT SUM(screenings_engaged) AS n
      FROM `${local.bq_dataset}.mart_screener_filter_usage`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    viewers AS (
      SELECT COUNT(*) AS denom
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER_CESN__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      ROUND(COALESCE((SELECT n FROM engaged), 0) * 100.0 / NULLIF((SELECT denom FROM viewers), 0), 1) AS `% of Results Viewers`,
      COALESCE((SELECT n FROM engaged), 0) AS `Filtered Screenings`
  SQL

  # ── Results: NPS score distribution ──────────────────────────────────
  # Count of submitted NPS scores by category (Detractor 0-6 / Passive 7-8 /
  # Promoter 9-10). Response follow-through (reasons, feedback clicks) is on the
  # detail mart if needed later.
  screener_sql_nps_distribution = <<-SQL
    SELECT
      `Category`, `Responses` FROM (
        SELECT
          CASE nps_category WHEN 'Detractor' THEN 1 WHEN 'Passive' THEN 2 WHEN 'Promoter' THEN 3 ELSE 4 END AS sort_key,
          nps_category AS `Category`,
          SUM(scores_submitted) AS `Responses`
        FROM `${local.bq_dataset}.mart_screener_nps`
        WHERE __STATE_FILTER__
          AND nps_category IS NOT NULL
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
        GROUP BY nps_category, sort_key
      )
    WHERE `Responses` > 0
    ORDER BY sort_key
  SQL

  # ── Footer / site-chrome cards (GLOBAL-only) ─────────────────────────────────
  # Site chrome fires largely without screener_state, so these three cards live only
  # on the global dashboard and do NOT use the __STATE_FILTER__ sentinel. Each reads
  # the session-grain mart_screener_footer_engagement and reports "% of sessions that
  # clicked X" — denominator = distinct sessions in the window (from the session-grain
  # step-facts), so the rate is exact (no multi-day double-count). Raw session count
  # on hover. element_group selects which card. Attaching state on the FE (tracked on
  # the FE gaps ticket) will later enable per-tenant versions.
  #
  # A shared session denominator CTE is spliced into each card via __SESSIONS_CTE__.
  _footer_sessions_cte = <<-SQL
    sessions AS (
      SELECT COUNT(DISTINCT session_key) AS n
      FROM `${local.bq_dataset}.mart_screener_step_facts`
      WHERE event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
  SQL

  # Card 1 — Site Chrome Navigation: logo, About/Privacy/Terms, "Changed Language".
  screener_sql_chrome_nav = <<-SQL
    WITH ${local._footer_sessions_cte}
    SELECT
      element AS `Element`,
      ROUND(COUNT(DISTINCT session_key) * 100.0 / NULLIF((SELECT n FROM sessions), 0), 1) AS `% of Sessions`,
      COUNT(DISTINCT session_key) AS `Sessions`
    FROM `${local.bq_dataset}.mart_screener_footer_engagement`
    WHERE element_group = 'nav'
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY element
    ORDER BY `% of Sessions` DESC
  SQL

  # Card 2 — Social Link Clicks: LinkedIn / Facebook / Instagram.
  screener_sql_social_clicks = <<-SQL
    WITH ${local._footer_sessions_cte}
    SELECT
      element AS `Network`,
      ROUND(COUNT(DISTINCT session_key) * 100.0 / NULLIF((SELECT n FROM sessions), 0), 1) AS `% of Sessions`,
      COUNT(DISTINCT session_key) AS `Sessions`
    FROM `${local.bq_dataset}.mart_screener_footer_engagement`
    WHERE element_group = 'social'
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY element
    ORDER BY `% of Sessions` DESC
  SQL

  # Card 3 — Footer Feedback & Share: Report a Bug, Contact Us, Share.
  screener_sql_footer_feedback_share = <<-SQL
    WITH ${local._footer_sessions_cte}
    SELECT
      element AS `Action`,
      ROUND(COUNT(DISTINCT session_key) * 100.0 / NULLIF((SELECT n FROM sessions), 0), 1) AS `% of Sessions`,
      COUNT(DISTINCT session_key) AS `Sessions`
    FROM `${local.bq_dataset}.mart_screener_footer_engagement`
    WHERE element_group = 'feedback_share'
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY element
    ORDER BY `% of Sessions` DESC
  SQL

  # ── In-step content-link click rates ─────────────────────────────────────────
  # Each in-step content link fires from exactly one step, so it reads best as a
  # standalone rate: of the sessions that viewed that step, the % that clicked the
  # link (raw click count on hover). Denominator = distinct sessions that viewed the
  # step (session-grain step-facts, deduped across days). One local per link/step.
  #
  # FUTURE (blocked on FE link_location param — FE gaps ticket #3): the Disclaimer
  # step actually has THREE links (Public Charge + Privacy + Terms). Once the FE
  # tags link source, replace the single Public Charge scalar with one Disclaimer
  # bar chart showing all three by-link click rates.
  #
  # Public Charge link, shown on the Disclaimer step.
  screener_sql_public_charge_click_rate = <<-SQL
    WITH viewers AS (
      SELECT COUNT(DISTINCT session_key) AS n
      FROM `${local.bq_dataset}.mart_screener_step_facts`
      WHERE __STATE_FILTER__
        AND screener_step_name = 'disclaimer'
        AND viewed
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    clicks AS (
      SELECT SUM(total_clicks) AS c
      FROM `${local.bq_dataset}.mart_screener_link_clicks`
      WHERE __STATE_FILTER__
        AND link_label = 'Public Charge'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      ROUND(COALESCE((SELECT c FROM clicks), 0) * 100.0 / NULLIF((SELECT n FROM viewers), 0), 1) AS `% of Disclaimer Viewers`,
      COALESCE((SELECT c FROM clicks), 0) AS `Clicks`
  SQL

  # ── Results: "edit Additional Resources" from the results Needs section ───────
  # Clicks on the "edit your selections" link in the results Needs section, which
  # sends people back to the Additional Resources step to change what they picked.
  # Distinct from Confirmation Edits (that's the review-page edit path); this is the
  # results-page nudge. Uses the 'edit_nav' link group.
  # % of results-page viewers who clicked the "edit Additional Resources" go-back link.
  # Same shared results-viewer denominator (mart_screener_results_revisits, CESN-aware
  # sentinel) as the sibling results-engagement scalars. Numerator is DISTINCT screenings
  # (the mart's `screenings` = count(distinct screener_uid)), not raw clicks, so it's on
  # the same grain as the denominator. Raw distinct-screening count on hover.
  screener_sql_additional_resources_edits = <<-SQL
    WITH editors AS (
      SELECT SUM(screenings) AS n
      FROM `${local.bq_dataset}.mart_screener_link_clicks`
      WHERE __STATE_FILTER__
        AND link_group = 'edit_nav'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    viewers AS (
      SELECT COUNT(*) AS denom
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER_CESN__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      ROUND(COALESCE((SELECT n FROM editors), 0) * 100.0 / NULLIF((SELECT denom FROM viewers), 0), 1) AS `% of Results Viewers`,
      COALESCE((SELECT n FROM editors), 0) AS `Screenings That Edited`
  SQL

  # ── Results: document downloads (count, by document × program) ──────────────────
  # Which "Key Information You May Need to Provide" documents get downloaded, and for
  # which program. COUNT card (not a rate): there is no per-document impression event,
  # so a true "% of those shown the doc that downloaded it" is not possible (logged on
  # the FE gaps ticket). Volume is currently tiny. Distinct screenings + raw downloads.
  screener_sql_document_downloads = <<-SQL
    SELECT
      document_name AS `Document`,
      program_name  AS `Program`,
      SUM(screenings_with_interaction) AS `Screenings`,
      SUM(total_interactions)          AS `Downloads`
    FROM `${local.bq_dataset}.mart_screener_program_interactions`
    WHERE __STATE_FILTER__
      AND interaction_type = 'document_download'
      AND document_name IS NOT NULL
    AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY `Document`, `Program`
    ORDER BY `Downloads` DESC
  SQL

  # ── Results: NPS engagement rate (% of results viewers who scored NPS) ──────────
  # % of results-page viewers who engaged with the NPS widget (submitted a score).
  # Same shared results-viewer denominator (CESN-aware sentinel) as the other results
  # engagement scalars. Numerator = distinct screenings that submitted an NPS score.
  # Raw distinct-screening count on hover. scores_submitted is an event count in the
  # NPS mart, so distinct screenings are counted here off the (score-grain) mart via
  # SUM of the daily distinct — but NPS lacks a uid in output, so we count score
  # submissions as the numerator (one score per screening in practice).
  screener_sql_nps_engagement = <<-SQL
    WITH scored AS (
      SELECT SUM(scores_submitted) AS n
      FROM `${local.bq_dataset}.mart_screener_nps`
      WHERE __STATE_FILTER__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    viewers AS (
      SELECT COUNT(*) AS denom
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER_CESN__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      ROUND(COALESCE((SELECT n FROM scored), 0) * 100.0 / NULLIF((SELECT denom FROM viewers), 0), 1) AS `% of Results Viewers`,
      COALESCE((SELECT n FROM scored), 0) AS `Scored NPS`
  SQL

  # ── Results: "More Help / 211" CTA clicks ───────────────────────────────────────
  # % of results-page viewers who clicked the "More Help?" / 211 CTA. Same shared
  # results-viewer denominator as the sibling cards. Raw click count on hover.
  screener_sql_get_help_clicks = <<-SQL
    WITH clicks AS (
      SELECT SUM(total_clicks) AS n
      FROM `${local.bq_dataset}.mart_screener_help`
      WHERE __STATE_FILTER__
        AND metric = 'get_help_click'
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    ),
    viewers AS (
      SELECT COUNT(*) AS denom
      FROM `${local.bq_dataset}.mart_screener_results_revisits`
      WHERE __STATE_FILTER_CESN__
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    )
    SELECT
      ROUND(COALESCE((SELECT n FROM clicks), 0) * 100.0 / NULLIF((SELECT denom FROM viewers), 0), 1) AS `% of Results Viewers`,
      COALESCE((SELECT n FROM clicks), 0) AS `More Help Clicks`
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
  SQL

  # ── Tab 10 (Overview): language distribution ────────────────────────────────
  # Header language SWITCHES — which languages sessions switch TO via the header
  # language selector. This is header-selector engagement, NOT "language the
  # household speaks" (that intake answer lives on the Households tab). Deduped
  # per session.
  # GLOBAL-only + no state filter: language-switch events fire without screener_state
  # (stateless chrome, often pre-white-label), so a state IN(...) filter drops 100% of
  # rows. Per-tenant version is blocked on the FE attaching state (FE gaps ticket).
  screener_sql_language_distribution = <<-SQL
    SELECT
      language_name AS `Switched To`,
      SUM(distinct_screenings) AS `Sessions`
    FROM `${local.bq_dataset}.mart_screener_language`
    WHERE event_date_parsed >= DATE('${local.screener_analytics_epoch}')
    [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
    [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
    GROUP BY language_name
    ORDER BY `Sessions` DESC
  SQL
}
