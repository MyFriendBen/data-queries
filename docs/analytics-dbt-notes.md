# Analytics — dbt / Metabase Implementation Notes

Running notes for building the dbt models + Metabase dashboards on top of the
app-emitted GA4 events (MFB-1268). Companion to `gtm-ga4-handoff.md` (the GTM/GA4
relay spec). Event schema source of truth:
`benefits-calculator/src/Assets/analytics/events.ts`.

These are the non-obvious things that will bite whoever builds the models if not
accounted for. Grouped by the model area they affect.

## Keys & joins

- **Group program metrics by `program_id`, not `program_name`.** `program_name`
  is the English display label (`default_message`) and can vary in spelling for
  the same program (we saw `SNAP (Supplemental…)` vs `Supplemental… (SNAP)` in
  the old data). `program_id` is the stable key. Pattern: group by `program_id`,
  pick any one `program_name` per id as the display label. Affects: apply,
  more-info, visit-website, phone, document, required-program, eligibility-tags.

- **The drop-off funnel joins `screener_form_step` view↔complete on
  `screener_step_name`.** Every real step resolves a stable slug (the step-id map
  is a total `Record<QuestionName,string>`, compile-enforced). Two caveats:
  - **`select-state` has a null `screener_step_number`** (it's a pre-numbered
    page). Join on name; don't assume a non-null step number for every row.
  - Pre-directory steps use slugs `language`, `disclaimer`, `select-state`
    (see `PRE_DIRECTORY_STEP_IDS` in `stepIds.ts`).

- **⚠️ Funnel dedup key is the GA4 SESSION, not `screener_uid`.** `screener_uid`
  is the app-minted screening UUID and does not exist until **step 3** (zip/county
  creates the Screen record → URL gets `/:uuid`). It is null on `form_start`,
  language, disclaimer, and select-state. Verified in prod (2026-07-15):
  `screener_uid` is ~4% populated on `form_start`, ~5% on `form_back`, ~13% on
  `form_error` — recovering to ~97% by `form_complete`. So **`COUNT(DISTINCT
  screener_uid)` collapses the top-of-funnel denominator to near-zero.** Dedup
  funnel/drop-off metrics on the GA4 session key
  `TO_JSON_STRING(STRUCT(user_pseudo_id, ga_session_id))` instead — it is present
  on 100% of events from the first pageview, and it's the same key the old
  `mart_ga_kpi_summary` uses. `mart_screener_form_funnel` was fixed to do this
  (2026-07-15); columns keep the `screenings_*` names (sibling-mart consistency)
  but are session-deduped. Use `screener_uid` only for **screening-level** joins
  (results revisits, conversion), never as the funnel denominator.

- **Do NOT drop rows on null `screener_uid`.** Because uid is null pre-step-3, any
  model that inner-joins on uid or filters `uid is not null` loses the start of
  the funnel. Left-join / tolerate nulls.

## Counting semantics (avoid inflation)

- **`screener_income_source` deletes can outnumber adds — this is expected, not
  a data bug.** `action:'add'` fires only on a user clicking "+ Add an Income
  Source"; `action:'delete'` fires on any trash-click. But the form
  auto-appends an empty income row for 16+ members (a UX convenience), which is
  intentionally NOT tracked as an add. If the user trashes that auto-row, a
  `delete` fires with no matching `add`. Treat add and delete as two independent
  engagement metrics — do NOT expect them to reconcile 1:1.

- **`screener_form_start` fires once per screening** (guarded by a per-uuid
  sessionStorage flag), so one session ≈ one start — a clean funnel denominator
  when deduped on the **session key** (NOT uid, which is null here; see above).

- **`screener_form_step` (`step_action='view'`) fires once per step view**,
  including re-views after back-nav — that's intentional (drop-off wants views).
  For a "distinct sessions that reached step X" funnel, `COUNT(DISTINCT
  session_key)` per step (NOT `COUNT(DISTINCT screener_uid)` — uid is null on
  early steps), and NOT raw event count. Same dedupe discipline as
  `mart_ga_kpi_summary`.

- **`screener_results_loaded.program_count`** = `apiResults.programs.length`.
  ⚠️ OPEN QUESTION for the team: in MFB the `/results` API returns eligible
  programs, so this is effectively the eligible count. Confirm whether partners
  want "eligible" vs "total incl. ineligible" — if a separate ineligible set
  exists, we should split into `program_count` + `eligible_count` in the FE.
  Until confirmed, treat `program_count` as eligible-programs-found.

- **Impressions are ref-guarded per mount** (`screener_eligibility_tags_shown`,
  `screener_notification_popup:shown`, `screener_share_popup_shown`) so they
  don't re-fire on re-render. Still dedupe by `screener_uid` for "distinct
  screenings shown X".

## Cutover / double-counting

- **`screener_additional_resource_click` coexists with the pre-existing
  `outbound_click`** (NeedCard fires both during cutover). Post-cutover, the old
  `outbound_click`-based tracking must be removed (see the delete-list in
  `gtm-ga4-handoff.md`) or resource clicks double-count.

- General rule: until the contractor deletes the old DOM-scrape triggers, expect
  BOTH old (`screener_results_page_*`, `screener_step_*`, etc.) and new
  (`screener_*`) events in BigQuery. Build models on the NEW names; verify the
  old ones stop arriving after cutover (a good post-cutover check: query for any
  event_name not in the new schema still arriving).

## Dashboard structure (per white-label, templated by state)

Built in data-queries PR #110 (dbt models + Metabase cards, unapplied until the
GTM→GA4 relay lands data in BigQuery). Marts feeding each tab:

- Tab 1 Overview: existing KPIs + 5-stage macro funnel (Visitors→Started→Saw
  Results→More Info→Apply) + language distribution (`mart_screener_language`).
- Tab 2 Form Journey: detailed per-step drop-off funnel + errors-by-step +
  back-nav-by-step, all from `mart_screener_form_funnel` (dedupe by GA4 session
  key, NOT uid — see the ⚠️ note above);
  step-interaction cards from `mart` on `stg_ga_screener_step_interactions`.
- Tab 3 Results: apply-conversion-rate (apply/more_info) + more-info-vs-apply +
  scatter + outcome KPIs, from `mart_screener_program_interactions` /
  `mart_screener_results_outcomes` (group by program_id, program_name as label);
  Resources sub-section (tab-split long_term_benefits vs additional_resources +
  top resources clicked) from `mart_screener_resource_engagement`.
- Tab 4 Sharing & Saving: side-by-side Popup vs Footer share conversion funnels +
  shares-by-channel (`mart_screener_shares`); save funnel + channel
  (`mart_screener_saves`).

Marts: `mart_screener_form_funnel`, `_program_interactions`, `_results_outcomes`,
`_shares`, `_saves`, `_resource_engagement`, `_language`.

Deferred cards pending MFB-1306 events: help-clicks by step, resource
website-vs-phone split, navigator-per-program, results scroll depth.

## Deferred / not-yet-emitted (don't build on these yet)

- `screener_form_field_engaged` — not emitted (needs shared field wrapper).
- `screener_form_submit_failed` — not emitted (needs central submit handler).
- No `save_action:'error'` / share failure event yet — send-failure is not
  distinguished from send-attempt for save/share. Flag if partners need it.
