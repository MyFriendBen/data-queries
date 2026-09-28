{{ config(materialized='table') }}

-- Per-screening household size (MFB-1573). Powers the Household Member
-- Actions card's per-action denominators — Add/Delete/Edit need 2+ members,
-- Delete-from-summary needs 3+.
--
-- No `household_size` event param exists. Derived from member_index (FE
-- #2163, 0-based), emitted on the member-details step's VIEW event, one page
-- per member: household_size = MAX(member_index) + 1, the highest
-- member-detail page a screening ever viewed. Not emitted on
-- screener_household_member action events, so there's no second source to
-- union in here — the card adds its own action-based self-evidence on top of
-- this proxy (see screener_sql_household_member_engagement).
--
-- Known, accepted limitation: exact for anyone who views every member's
-- detail page (the normal wizard path); understates size for screenings that
-- add/delete a member on the roster page and then abandon before opening
-- that member's own page.
--
-- member_index is client-supplied — clamped to 0-49 so a corrupt/spoofed
-- event can't overflow MAX()+1 or inflate a household size (observed range
-- tops out at 7). event_date_parsed floors at the dashboard's usual epoch to
-- stay in scope with the card's own windowing.
--
-- Grain: one row per screener_uid — a lifetime/peak fact, not day-windowed
-- (the card windows its population separately, via viewer_ids).

select
    screener_uid,
    max(member_index) + 1 as household_size,
    max(screener_state) as screener_state,
    current_timestamp() as updated_at

from {{ ref('stg_ga_screener_form_funnel') }}
where event_name = 'screener_form_step'
    and step_action = 'view'
    and screener_step_name = 'member-details'
    and screener_uid is not null
    and member_index between 0 and 49
    and event_date_parsed >= parse_date('%Y%m%d', '{{ var("screener_analytics_epoch_suffix") }}')

group by screener_uid
