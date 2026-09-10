# CESN-only tab: Heat Pump Journey (Tab 11).
#
# Cards for the CESN HVAC / heat-pump results-page journey, powered by the
# BigQuery heat-pump marts:
#   mart_heat_pump_engagement          — clicks + users per interaction (Story 1/3)
#   mart_heat_pump_calculator_funnel   — impact-calculator step funnel (Story 2)
#   mart_heat_pump_calculator_errors   — errors by type (Story 2)
#   mart_heat_pump_calculator_results  — one row per screening that saw results,
#                                        with the contractor-search cohort flag
#                                        and emissions in tons / forest acres (Story 7)
#   mart_heat_pump_user_journey        — per-uid milestone flags + first/last
#                                        section (Stories 5/6)
#
# Every card is built ONLY for tenants that have this tab, not for every tenant
# with a BigQuery tab. The cards hardcode screener_state = 'cesn', so building
# them per-tenant would drop a card carrying CESN data into every other tenant's
# collection — unplaced on any dashboard, but browsable and runnable by their
# users. Same gate and same reason as screener_cesn_funnel in
# screener_analytics.tf. Every other BigQuery card is safe without it because it
# filters on the tenant's own state; these do not.
#
# Date filtering mirrors the other BigQuery cards: an epoch floor plus the optional
# {{start_date}}/{{end_date}} template tags (local.ga_date_tags), mapped onto the
# shared dashboard date filter in the layout block at the bottom.
#
# Partner decisions baked in here: trends are WEEKLY, emissions are metric tons
# plus the forest-acre equivalency the product shows, savings/emissions are split
# by whether the screening went on to a contractor search, the savings median
# carries a p20-p80 range table beneath it, and any group smaller than
# hp_min_group_size is suppressed once a segment filter narrows the population.
#
# Period-over-period: the partner asked for weekly with a WoW/MoM comparison.
# Shipped as MONTHLY on the three headline numbers (top card), with weekly WoW
# deferred until traffic supports a percentage that is not noise — the same call
# she made on the Story 5 ranked path list. Revisit when volume grows.
#
# The tab opens filtered to "below 200% FPL" (hp_below_200_filter, defaulted on),
# which is the partner's target population. Note the interaction: that default is
# itself a segment, so suppression is active on open. At CESN volume the tab will
# look sparse by default and emptier still once a region is added on top — that is
# the suppression rule working, not a broken dashboard. Worth saying out loud at
# the walkthrough.

locals {
  hp_state_filter = "screener_state = 'cesn'"

  # Suppress groups smaller than this on cards that slice people into segments.
  # Raw interaction counts are not suppressed — they identify nobody, and at CESN
  # volume suppressing them would empty the tab.
  hp_min_group_size = 5

  # Minimum prior-month base before a month-over-month change is shown at all.
  # Separate from hp_min_group_size because it answers a different question: 5 is
  # the disclosure floor, this is the "is the number meaningful" floor. A cell
  # that survives suppression can still make noise look like a trend — 3 to 5
  # households renders as +67%. Below this the change is withheld and the two
  # raw counts still show, so the reader sees the base rather than a percentage.
  # PROVISIONAL: 10 is an engineering default, pending the partner's answer on
  # what floor she wants.
  hp_min_mom_base = 10

  # The partner asked for any group under hp_min_group_size to be hidden. Applied
  # ONLY while a segment filter is narrowing the population, which is the case
  # that carries disclosure risk: unfiltered, a cell is "everyone who clicked X"
  # and names nobody; filtered to one income band in one region it can be a
  # single household. Suppressing unconditionally would blank the tab at CESN
  # volume, which is why the floor rides the filters rather than the card.
  #
  # Each clause is a Metabase optional block, so it disappears when its filter is
  # unset. __N__ is replaced per card with that card's group-size expression.
  hp_suppress_when_segmented = <<-SQL
    [[AND {{income_band}} IS NOT NULL AND __N__ >= ${local.hp_min_group_size}]]
    [[AND {{region}} IS NOT NULL AND __N__ >= ${local.hp_min_group_size}]]
    [[AND {{utility}} IS NOT NULL AND __N__ >= ${local.hp_min_group_size}]]
    [[AND {{below_200}} IS NOT NULL AND __N__ >= ${local.hp_min_group_size}]]
  SQL

  # Story 4 segmentation filters. Plain text variables rather than Metabase field
  # filters, for the same reason the date filters are: the BigQuery driver mangles
  # the column reference a field filter generates. Each clause is optional, so an
  # unset filter drops out of the SQL entirely.
  hp_segment_tags = {
    income_band = {
      id             = "hp_income_band_filter"
      name           = "income_band"
      "display-name" = "Income Band"
      type           = "text"
    }
    region = {
      id             = "hp_region_filter"
      name           = "region"
      "display-name" = "Region"
      type           = "text"
    }
    utility = {
      id             = "hp_utility_filter"
      name           = "utility"
      "display-name" = "Utility"
      type           = "text"
    }
    below_200 = {
      id             = "hp_below_200_filter"
      name           = "below_200"
      "display-name" = "Income Quick Filter"
      type           = "text"
    }
  }

  # ── Story 1 & 3: what users click on the HVAC page + contractor lookups ──────
  # Clicks and distinct users per interaction. PDF pages sort naturally via
  # interaction_sort so "page 2" precedes "page 10".
  hp_sql_engagement = <<-SQL
    SELECT
      interaction AS `Interaction`,
      SUM(total_clicks) AS `Clicks`,
      HLL_COUNT.MERGE(users_hll) AS `Users`
    FROM `${local.bq_dataset}.mart_heat_pump_engagement`
    WHERE ${local.hp_state_filter}
      AND interaction IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
      [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    GROUP BY interaction, interaction_sort
    HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "HLL_COUNT.MERGE(users_hll)")}
    ORDER BY interaction_sort, `Clicks` DESC
  SQL

  # ── Story 1 & 3: click-through rate ─────────────────────────────────────────
  # % of users who SAW a section that then clicked its element. Recomputed from
  # summed users / view_users over the range (not an average of daily rates), so
  # the denominator is the section_view impression, not raw clicks.
  hp_sql_click_through_rate = <<-SQL
    SELECT
      interaction AS `Interaction`,
      ROUND(HLL_COUNT.MERGE(users_hll) * 100.0 / NULLIF(HLL_COUNT.MERGE(view_users_hll), 0), 1)
        AS `% of viewers who clicked`
    FROM `${local.bq_dataset}.mart_heat_pump_engagement`
    WHERE ${local.hp_state_filter}
      AND interaction IS NOT NULL
      AND view_users IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
      [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    GROUP BY interaction
    HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "HLL_COUNT.MERGE(view_users_hll)")}
    ORDER BY `% of viewers who clicked` DESC
  SQL

  # ── Story 2: impact-calculator funnel ───────────────────────────────────────
  # Distinct users reaching each calculator stage, in funnel order. The errors
  # stage (funnel_rank 10) is excluded here — it's off-funnel and gets its own
  # card below. clicked_calculate (button pressed) precedes calculate_impact
  # (passed validation); the drop between them is validation failures.
  hp_sql_calculator_funnel = <<-SQL
    WITH agg AS (
      SELECT stage, funnel_rank, HLL_COUNT.MERGE(users_hll) AS users
      FROM `${local.bq_dataset}.mart_heat_pump_calculator_funnel`
      WHERE ${local.hp_state_filter}
        AND funnel_rank < 10
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
        [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
      GROUP BY stage, funnel_rank
      HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "HLL_COUNT.MERGE(users_hll)")}
    )
    SELECT
      CASE stage
        WHEN 'household_type'     THEN 'Household type'
        WHEN 'address'            THEN 'Address'
        WHEN 'heating_fuel'       THEN 'Heating fuel'
        WHEN 'water_heating'      THEN 'Water heating'
        WHEN 'project_type'       THEN 'Project type'
        WHEN 'clicked_calculate'  THEN 'Clicked Calculate impact'
        WHEN 'calculate_impact'   THEN 'Passed validation'
        WHEN 'results_shown'      THEN 'Results shown'
        WHEN 'edit_after_results' THEN 'Edit after results'
      END AS `Stage`,
      users AS `Users`
    FROM agg
    ORDER BY funnel_rank
  SQL

  # ── Story 2: calculator errors, by type ─────────────────────────────────────
  hp_sql_calculator_errors = <<-SQL
    SELECT
      error_label AS `Error`,
      SUM(total_errors) AS `Errors`,
      HLL_COUNT.MERGE(users_hll) AS `Users`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_errors`
    WHERE ${local.hp_state_filter}
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
      [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    GROUP BY error_label
    HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "HLL_COUNT.MERGE(users_hll)")}
    ORDER BY `Errors` DESC
  SQL

  # ── Story 5: page-level drop-off ────────────────────────────────────────────
  # Debra's chosen main view for "order in which people click through". Distinct
  # screenings reaching each milestone of the page journey, in order, so the
  # weakest link is visible. Built from the per-uid journey mart, so a screening
  # is counted once no matter how many times it clicked.
  hp_sql_page_funnel = <<-SQL
    WITH j AS (
      SELECT *
      FROM `${local.bq_dataset}.mart_heat_pump_user_journey`
      WHERE ${local.hp_state_filter}
        AND first_event_date >= DATE('${local.screener_analytics_epoch}')
        [[AND first_event_date >= CAST({{start_date}} AS DATE)]]
        [[AND first_event_date <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
        [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    )
    SELECT `Stage`, `Screenings` FROM (
      SELECT 'Reached the heat pump section' AS `Stage`, COUNT(*) AS `Screenings`, 1 AS o FROM j
      UNION ALL
      SELECT 'Clicked "Learn more"', COUNTIF(clicked_learn_more), 2 FROM j
      UNION ALL
      SELECT 'Clicked "Calculate impact"', COUNTIF(clicked_calculate_impact_cta), 3 FROM j
      UNION ALL
      SELECT 'Engaged the calculator', COUNTIF(engaged_calculator), 4 FROM j
      UNION ALL
      SELECT 'Saw calculator results', COUNTIF(saw_calculator_results), 5 FROM j
      UNION ALL
      SELECT 'Opened the contractor PDF', COUNTIF(opened_contractor_pdf), 6 FROM j
      UNION ALL
      SELECT 'Reached a contractor search', COUNTIF(reached_contractor_search), 7 FROM j
    )
    -- Floor the row, not the cohort: (SELECT COUNT(*) FROM j) is the whole
    -- cohort, so a stage reached by a single screening rendered as long as the
    -- cohort cleared 5. `Screenings` is the stage's own count. Stage 1 is the
    -- cohort itself, so a cohort under the floor still empties the card.
    WHERE TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "`Screenings`")}
    ORDER BY o
  SQL

  # ── Story 5: where journeys start and end ───────────────────────────────────
  # The companion view Debra asked for beside the drop-off chart: the section a
  # screening engaged with FIRST, and the last one it touched before leaving.
  hp_sql_journey_start_end = <<-SQL
    WITH j AS (
      SELECT first_section, last_section
      FROM `${local.bq_dataset}.mart_heat_pump_user_journey`
      WHERE ${local.hp_state_filter}
        AND first_event_date >= DATE('${local.screener_analytics_epoch}')
        [[AND first_event_date >= CAST({{start_date}} AS DATE)]]
        [[AND first_event_date <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
        [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    ),
    labelled AS (
      SELECT
        CASE section
          WHEN 'why_heat_pump'        THEN 'Why get a heat pump?'
          WHEN 'bills_impact'         THEN 'Will it impact my bills?'
          WHEN 'find_contractor_card' THEN 'Whom should I hire?'
          WHEN 'connect_now_page'     THEN 'Connect now page'
          WHEN 'rebates'              THEN 'Rebates'
          WHEN 'calculator'           THEN 'Impact calculator'
          WHEN 'contractor_pdf'       THEN 'Contractor tips PDF'
          ELSE '(unknown)'
        END AS `Section`,
        journey_position
      FROM (
        SELECT first_section AS section, 'Started here' AS journey_position FROM j WHERE first_section IS NOT NULL
        UNION ALL
        SELECT last_section, 'Ended here' FROM j WHERE last_section IS NOT NULL
      )
    )
    SELECT `Section`, journey_position AS `Position`, COUNT(*) AS `Screenings`
    FROM labelled
    GROUP BY `Section`, `Position`
    HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "COUNT(*)")}
    ORDER BY `Screenings` DESC
  SQL

  # ── Story 6: contractor-search correlation ──────────────────────────────────
  # Of users who reached a contractor search, what share also clicked "Learn more"
  # and what share engaged the impact calculator. The per-uid journey mart makes
  # each user one row, so these are clean subset shares.
  hp_sql_contractor_correlation = <<-SQL
    WITH reached AS (
      SELECT clicked_learn_more, engaged_calculator, saw_calculator_results, opened_contractor_pdf
      FROM `${local.bq_dataset}.mart_heat_pump_user_journey`
      WHERE ${local.hp_state_filter}
        AND reached_contractor_search
        AND first_event_date >= DATE('${local.screener_analytics_epoch}')
        [[AND first_event_date >= CAST({{start_date}} AS DATE)]]
        [[AND first_event_date <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
        [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    )
    SELECT `Cohort`, `Users`, `% of contractor-search users` FROM (
      SELECT 'Also clicked "Learn more"' AS `Cohort`,
        COUNTIF(clicked_learn_more) AS `Users`,
        ROUND(COUNTIF(clicked_learn_more) * 100.0 / NULLIF(COUNT(*), 0), 1) AS `% of contractor-search users`,
        1 AS o
      FROM reached
      UNION ALL
      SELECT 'Also engaged the calculator',
        COUNTIF(engaged_calculator),
        ROUND(COUNTIF(engaged_calculator) * 100.0 / NULLIF(COUNT(*), 0), 1), 2
      FROM reached
      UNION ALL
      SELECT 'Also saw calculator results',
        COUNTIF(saw_calculator_results),
        ROUND(COUNTIF(saw_calculator_results) * 100.0 / NULLIF(COUNT(*), 0), 1), 3
      FROM reached
      UNION ALL
      SELECT 'Also opened the contractor PDF',
        COUNTIF(opened_contractor_pdf),
        ROUND(COUNTIF(opened_contractor_pdf) * 100.0 / NULLIF(COUNT(*), 0), 1), 4
      FROM reached
    )
    -- Floor each row's own subgroup, not the cohort. `Users` is also selected so
    -- the percentage is never read without the count it came from; the chart
    -- plots only the percentage.
    WHERE TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "`Users`")}
    ORDER BY o
  SQL

  # ── Story 7: annual bill savings trend ──────────────────────────────────────
  # Weekly MEDIAN of the per-screening estimated annual saving, split by whether
  # the screening went on to a contractor search. The AC asks for the trend among
  # contractor-search users; the second series is everyone else, so the comparison
  # answers "do bigger savings actually move people to act?".
  # The mart already flips the sign, so a positive number is a saving.
  hp_sql_savings_trend = <<-SQL
    SELECT
      event_week AS `Week`,
      CASE WHEN reached_contractor_search
        THEN 'Went to a contractor search'
        ELSE 'Did not'
      END AS `Cohort`,
      ROUND(APPROX_QUANTILES(annual_bill_savings, 100 IGNORE NULLS)[OFFSET(50)], 2)
        AS `Median annual savings ($)`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND annual_bill_savings IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
      [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    GROUP BY `Week`, `Cohort`
    HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "COUNT(*)")}
    ORDER BY `Week`, `Cohort`
  SQL

  # ── Story 7: the savings range under the median ─────────────────────────────
  # Debra asked for the median on the chart with p20-p80 available underneath.
  # Same population and cohort split as the trend above, rendered as a table so
  # the range reads as a range rather than four more lines on the chart.
  #
  # The low/high columns are the ends of the range REM showed that household, so
  # a weekly figure here is "the typical low end" and "the typical high end", not
  # a spread across screenings. The mart already flipped the sign, and the ends
  # swap when it does — low end of the SAVING comes from the p80 bill delta.
  hp_sql_savings_range = <<-SQL
    SELECT
      event_week AS `Week`,
      CASE WHEN reached_contractor_search
        THEN 'Went to a contractor search'
        ELSE 'Did not'
      END AS `Cohort`,
      ROUND(APPROX_QUANTILES(annual_bill_savings_low, 100 IGNORE NULLS)[OFFSET(50)], 2)
        AS `Low end of range ($)`,
      ROUND(APPROX_QUANTILES(annual_bill_savings, 100 IGNORE NULLS)[OFFSET(50)], 2)
        AS `Median ($)`,
      ROUND(APPROX_QUANTILES(annual_bill_savings_high, 100 IGNORE NULLS)[OFFSET(50)], 2)
        AS `High end of range ($)`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND annual_bill_savings IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
      [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    GROUP BY `Week`, `Cohort`
    HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "COUNT(*)")}
    ORDER BY `Week`, `Cohort`
  SQL

  # ── Story 7: annual emissions reduction trend ───────────────────────────────
  # Metric tons CO2e, Debra's requested unit. Same weekly median + cohort split.
  hp_sql_emissions_trend = <<-SQL
    SELECT
      event_week AS `Week`,
      CASE WHEN reached_contractor_search
        THEN 'Went to a contractor search'
        ELSE 'Did not'
      END AS `Cohort`,
      ROUND(APPROX_QUANTILES(annual_emissions_reduction_tons, 100 IGNORE NULLS)[OFFSET(50)], 2)
        AS `Median annual reduction (metric tons CO2e)`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND annual_emissions_reduction_tons IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
      [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    GROUP BY `Week`, `Cohort`
    HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "COUNT(*)")}
    ORDER BY `Week`, `Cohort`
  SQL

  # ── Story 7: headline equivalency ───────────────────────────────────────────
  # The number a program manager quotes. Same EPA equivalency the results page
  # shows ("acres of U.S. forests in one year"), totalled over the date range.
  hp_sql_emissions_equivalency = <<-SQL
    SELECT
      ROUND(SUM(annual_emissions_forest_acres), 1) AS `Acres of U.S. forest (one year)`
    FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
    WHERE ${local.hp_state_filter}
      AND annual_emissions_forest_acres IS NOT NULL
      AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
      [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
      [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
      [[AND income_band = {{income_band}}]]
      [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
      [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
      [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "COUNT(*)")}
  SQL

  # ── Headline numbers, month over month ──────────────────────────────────────
  # The partner asked for weekly trends with a WoW/MoM comparison. Delivered as
  # MONTHLY on the three numbers she would actually quote, with weekly WoW
  # deferred until traffic supports it — the same call she made on the Story 5
  # ranked path list. At current volume a week-over-week percentage is mostly
  # noise: the first day of data was 12 real events, and the tab defaults to
  # below-200%-FPL on top of that.
  #
  # Rendered as a table rather than delta badges on purpose. Showing "this month"
  # and "prior month" beside the percentage keeps the base visible, so a large
  # change on a tiny denominator reads as what it is instead of as a finding.
  hp_sql_headline_mom = <<-SQL
    WITH journey AS (
      SELECT
        DATE_TRUNC(first_event_date, MONTH) AS m,
        CAST(COUNTIF(reached_contractor_search) AS FLOAT64) AS contractor,
        CAST(COUNTIF(saw_calculator_results) AS FLOAT64) AS results
      FROM `${local.bq_dataset}.mart_heat_pump_user_journey`
      WHERE ${local.hp_state_filter}
        AND first_event_date >= DATE('${local.screener_analytics_epoch}')
        [[AND first_event_date >= CAST({{start_date}} AS DATE)]]
        [[AND first_event_date <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
        [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
      GROUP BY m
      HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "COUNT(*)")}
    ),
    impact AS (
      SELECT
        DATE_TRUNC(event_date_parsed, MONTH) AS m,
        SUM(annual_emissions_forest_acres) AS acres,
        COUNT(*) AS screenings
      FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
      WHERE ${local.hp_state_filter}
        AND annual_emissions_forest_acres IS NOT NULL
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
        [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
      GROUP BY m
      HAVING TRUE ${replace(local.hp_suppress_when_segmented, "__N__", "COUNT(*)")}
    ),
    -- `base` is the screening count behind the metric, which is what the floor
    -- has to be evaluated against. For the two counts it equals the value; for
    -- forest acres it does not, and applying a household floor of 10 to a
    -- quantity of acres withheld the change for a 40-screening month totalling
    -- 6 acres while showing it for a 3-screening month totalling 14.
    metrics AS (
      SELECT m, 'Reached a contractor search' AS metric, contractor AS value, contractor AS base, 1 AS o FROM journey
      UNION ALL
      SELECT m, 'Saw calculator results', results, results, 2 FROM journey
      UNION ALL
      SELECT m, 'Emissions impact (forest acres)', ROUND(acres, 1), screenings, 3 FROM impact
    ),
    lagged AS (
      SELECT m, metric, value, base, o,
        LAG(m) OVER (PARTITION BY metric ORDER BY m) AS prior_m,
        LAG(value) OVER (PARTITION BY metric ORDER BY m) AS prior_value,
        LAG(base) OVER (PARTITION BY metric ORDER BY m) AS prior_base
      FROM metrics
    ),
    -- LAG walks to the previous PRESENT row, which after a month with no data or
    -- one dropped by the suppression above can be two or three months back. At
    -- CESN volume with the below-200% default on, that is the expected case, so
    -- anything not exactly one month back is not a prior month and is dropped
    -- rather than silently mislabelled.
    adjacent AS (
      SELECT m, metric, value, base, o,
        CASE WHEN DATE_DIFF(m, prior_m, MONTH) = 1 THEN prior_value END AS prior_value,
        CASE WHEN DATE_DIFF(m, prior_m, MONTH) = 1 THEN prior_base END AS prior_base
      FROM lagged
    )
    SELECT
      FORMAT_DATE('%Y-%m', m) AS `Month`,
      metric AS `Metric`,
      value AS `This month`,
      prior_value AS `Prior month`,
      CASE
        WHEN prior_base >= ${local.hp_min_mom_base} AND prior_value > 0
          THEN ROUND((value - prior_value) * 100.0 / prior_value, 1)
      END AS `Change vs prior month (%)`
    FROM adjacent
    ORDER BY m DESC, o
  SQL

  # ── Story 7: does a bigger estimate drive action? ───────────────────────────
  # Debra's follow-up question. Buckets screenings by the size of the saving they
  # were shown, then reports what share of each bucket went on to a contractor
  # search. Buckets under hp_min_group_size are suppressed.
  hp_sql_savings_band_conversion = <<-SQL
    WITH banded AS (
      SELECT
        CASE
          WHEN annual_bill_savings < 0    THEN 'No saving (costs more)'
          WHEN annual_bill_savings < 250  THEN 'Under $250'
          WHEN annual_bill_savings < 500  THEN '$250–$499'
          WHEN annual_bill_savings < 1000 THEN '$500–$999'
          ELSE '$1,000+'
        END AS band,
        CASE
          WHEN annual_bill_savings < 0    THEN 1
          WHEN annual_bill_savings < 250  THEN 2
          WHEN annual_bill_savings < 500  THEN 3
          WHEN annual_bill_savings < 1000 THEN 4
          ELSE 5
        END AS band_sort,
        reached_contractor_search
      FROM `${local.bq_dataset}.mart_heat_pump_calculator_results`
      WHERE ${local.hp_state_filter}
        AND annual_bill_savings IS NOT NULL
        AND event_date_parsed >= DATE('${local.screener_analytics_epoch}')
        [[AND event_date_parsed >= CAST({{start_date}} AS DATE)]]
        [[AND event_date_parsed <= CAST({{end_date}} AS DATE)]]
        [[AND income_band = {{income_band}}]]
        [[AND region_memberships LIKE CONCAT('%,', {{region}}, ',%')]]
        [[AND {{utility}} = 'Xcel' AND is_xcel_customer]]
        [[AND {{below_200}} = 'Below 200% FPL' AND is_below_200_fpl]]
    )
    SELECT
      band AS `Estimated annual saving`,
      COUNT(*) AS `Screenings`,
      ROUND(COUNTIF(reached_contractor_search) * 100.0 / NULLIF(COUNT(*), 0), 1)
        AS `% who searched for a contractor`
    FROM banded
    GROUP BY band, band_sort
    HAVING COUNT(*) >= ${local.hp_min_group_size}
    ORDER BY band_sort
  SQL
}

# ── Cards ─────────────────────────────────────────────────────────────────────

resource "metabase_card" "hp_headline_mom" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Headline Numbers, Month over Month"
    description         = "The three figures worth quoting, by month, against the month before. Monthly rather than weekly because CESN volume makes a week-over-week percentage mostly noise; the raw counts sit beside the change so the base is always visible. A change is withheld when the prior month is under ${local.hp_min_mom_base}."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_headline_mom
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display                = "table"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

resource "metabase_card" "hp_engagement" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "HVAC Page Engagement"
    description         = "Clicks and unique users per interaction on the heat-pump journey: the 'Learn more' / 'Learn how to apply' links, the Calculate impact and Connect now CTAs, the two contractor searches, and the contractor-tips PDF broken out page by page."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_engagement
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Interaction"]
      "graph.metrics"     = ["Clicks", "Users"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_click_through_rate" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "HVAC Page Click-Through Rate"
    description         = "Of the users who saw each section, the percent who clicked its link or CTA. Denominator is the section-view impression, so this is a true click-through rate, not a share of clicks."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_click_through_rate
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Interaction"]
      "graph.metrics"     = ["% of viewers who clicked"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_page_funnel" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Heat Pump Journey Drop-Off"
    description         = "Distinct screenings reaching each milestone of the HVAC page journey, in order, so you can see where people fall away on the path toward contacting a contractor. Counted once per screening."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_page_funnel
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["Stage"]
      "graph.metrics"    = ["Screenings"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_journey_start_end" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Where Journeys Start and End"
    description         = "The section each screening engaged with first, and the last section it touched before leaving. Read alongside the drop-off chart: a section that is often the last one touched is where people give up."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_journey_start_end
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Section", "Position"]
      "graph.metrics"     = ["Screenings"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_calculator_funnel" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Impact Calculator Funnel"
    description         = "Unique users reaching each step of the impact calculator, in order: household type → address → heating fuel → water heating → project type → Calculate impact → results shown → edit after results. The drop between 'Clicked Calculate impact' and 'Passed validation' is submissions that failed validation."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_calculator_funnel
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "funnel"
    visualization_settings = {
      "graph.dimensions" = ["Stage"]
      "graph.metrics"    = ["Users"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_calculator_errors" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Impact Calculator Errors by Type"
    description         = "Calculator errors thrown, broken out by type: unsupported address, invalid response from the calculator, form validation, or other error."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_calculator_errors
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Error"]
      "graph.metrics"     = ["Errors", "Users"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_contractor_correlation" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Contractor-Search Users: Info Consumed"
    description         = "Of screenings that reached a contractor search (Power Ahead Colorado or Love Electric), the share that also clicked 'Learn more', engaged the impact calculator, saw results, or opened the contractor-tips PDF."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_contractor_correlation
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Cohort"]
      "graph.metrics"     = ["% of contractor-search users"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_savings_trend" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Estimated Annual Bill Savings (weekly median)"
    description         = "Weekly median of the calculator's estimated annual bill saving, split by whether the screening went on to a contractor search. A gap between the two lines means the size of the estimate is influencing whether people act on it."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_savings_trend
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "line"
    visualization_settings = {
      "graph.dimensions" = ["Week", "Cohort"]
      "graph.metrics"    = ["Median annual savings ($)"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_savings_range" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Estimated Annual Bill Savings — Range (p20–p80)"
    description         = "The low and high ends of the savings range each household was shown, weekly, beside the median from the chart above. Same cohort split, so the range can be read against the trend."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_savings_range
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display                = "table"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

resource "metabase_card" "hp_emissions_trend" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Estimated Annual Emissions Reduction (weekly median)"
    description         = "Weekly median of the calculator's estimated annual emissions reduction in metric tons of CO2e, split by whether the screening went on to a contractor search. Converted from the pounds the calculator returns using the EPA factor the results page uses (2,204.62 lb per metric ton)."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_emissions_trend
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "line"
    visualization_settings = {
      "graph.dimensions" = ["Week", "Cohort"]
      "graph.metrics"    = ["Median annual reduction (metric tons CO2e)"]
    }
    parameter_mappings = []
    parameters         = []
  })
}

resource "metabase_card" "hp_emissions_equivalency" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Total Emissions Impact (forest acres)"
    description         = "Every estimated annual emissions reduction in the selected period, added up and expressed as the EPA equivalency the results page shows users: acres of average U.S. forest sequestering carbon for one year. This is modelled potential impact from the calculator, not verified installations."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_emissions_equivalency
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display                = "scalar"
    visualization_settings = {}
    parameter_mappings     = []
    parameters             = []
  })
}

resource "metabase_card" "hp_savings_band_conversion" {
  for_each = { for k, v in local.ga_tenants_enabled : k => v if local.tenant_has_tab[k]["heat_pump_energy_journey"] }
  json = jsonencode({
    name                = "Does a Bigger Estimate Drive Action?"
    description         = "Screenings bucketed by the size of the annual saving they were shown, and the share of each bucket that went on to search for a contractor. Buckets with fewer than ${local.hp_min_group_size} screenings are hidden."
    collection_id       = tonumber(local.tenant_collection_map[each.key].id)
    collection_position = null
    cache_ttl           = null
    query_type          = "native"
    dataset_query = {
      database = tonumber(metabase_database.bigquery[0].id)
      type     = "native"
      native = {
        query         = local.hp_sql_savings_band_conversion
        template-tags = merge(local.ga_date_tags, local.hp_segment_tags)
      }
    }
    display = "bar"
    visualization_settings = {
      "graph.dimensions"  = ["Estimated annual saving"]
      "graph.metrics"     = ["% who searched for a contractor"]
      "graph.show_values" = true
    }
    parameter_mappings = []
    parameters         = []
  })
}

# ── Layout (placed on tab 11 for cesn only) ─────────────────────────────────────
#
# Every card is date-filtered, so each dashcard maps the shared
# ga_start_date_filter / ga_end_date_filter parameters onto its start_date /
# end_date template-tags — same wiring as the screener tabs. Without these the
# cards silently ignore the dashboard date picker and always read all-time.
#
# Cards must be ordered by dashboard_tab_id then row ascending to avoid the
# provider "inconsistent result" error on cards_json round-trip comparison.

locals {
  # Reused on every dashcard below; Terraform has no functions, so the pair is
  # built per card from its own id.
  tenant_dashboard_heat_pump_layout = concat(
    # Row 0: "data starts <epoch>" banner, matching the other analytics tabs.
    [local.tenant_screener_epoch_note_card[11]],
    [
      # Row 2: headline numbers month over month, above the detail cards.
      {
        card_id          = tonumber(metabase_card.hp_headline_mom["cesn"].id)
        dashboard_tab_id = 11
        row              = 2
        col              = 0
        size_x           = 24
        size_y           = 6
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_headline_mom["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_headline_mom["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_headline_mom["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_headline_mom["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_headline_mom["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_headline_mom["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 8: HVAC page engagement (left) | calculator errors (right)
      {
        card_id          = tonumber(metabase_card.hp_engagement["cesn"].id)
        dashboard_tab_id = 11
        row              = 8
        col              = 0
        size_x           = 18
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_engagement["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
        dashboard_tab_id = 11
        row              = 8
        col              = 18
        size_x           = 6
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_calculator_errors["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 9: click-through rate (full width)
      {
        card_id          = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
        dashboard_tab_id = 11
        row              = 15
        col              = 0
        size_x           = 24
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_click_through_rate["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 16: page drop-off (left) | where journeys start and end (right)
      {
        card_id          = tonumber(metabase_card.hp_page_funnel["cesn"].id)
        dashboard_tab_id = 11
        row              = 22
        col              = 0
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_page_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
        dashboard_tab_id = 11
        row              = 22
        col              = 12
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_journey_start_end["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 24: impact calculator funnel (left) | contractor correlation (right)
      {
        card_id          = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
        dashboard_tab_id = 11
        row              = 30
        col              = 0
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_calculator_funnel["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
        dashboard_tab_id = 11
        row              = 30
        col              = 12
        size_x           = 12
        size_y           = 8
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_contractor_correlation["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 32: savings trend (left) | emissions trend (right)
      {
        card_id          = tonumber(metabase_card.hp_savings_trend["cesn"].id)
        dashboard_tab_id = 11
        row              = 38
        col              = 0
        size_x           = 12
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_savings_trend["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
        dashboard_tab_id = 11
        row              = 38
        col              = 12
        size_x           = 12
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_emissions_trend["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      # Row 39: savings-band conversion (left) | forest-acre equivalency (right)
      # Row 39: the p20-p80 range, directly under the savings median chart.
      {
        card_id          = tonumber(metabase_card.hp_savings_range["cesn"].id)
        dashboard_tab_id = 11
        row              = 45
        col              = 0
        size_x           = 12
        size_y           = 6
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_range["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_range["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_savings_range["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_savings_range["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_savings_range["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_savings_range["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
        dashboard_tab_id = 11
        row              = 51
        col              = 0
        size_x           = 18
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_savings_band_conversion["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
      {
        card_id          = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
        dashboard_tab_id = 11
        row              = 51
        col              = 18
        size_x           = 6
        size_y           = 7
        parameter_mappings = [
          {
            parameter_id = local._ga_start_date_param_id
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "start_date"]]
          },
          {
            parameter_id = local._ga_end_date_param_id
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "end_date"]]
          },
          {
            parameter_id = "hp_income_band_filter"
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "income_band"]]
          },
          {
            parameter_id = "hp_region_filter"
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "region"]]
          },
          {
            parameter_id = "hp_utility_filter"
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "utility"]]
          },
          {
            parameter_id = "hp_below_200_filter"
            card_id      = tonumber(metabase_card.hp_emissions_equivalency["cesn"].id)
            target       = ["variable", ["template-tag", "below_200"]]
          }
        ]
        series                 = []
        visualization_settings = {}
      },
    ]
  )
}
