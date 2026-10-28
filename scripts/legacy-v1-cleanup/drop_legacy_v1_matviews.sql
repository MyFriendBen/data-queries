-- MFB-1192: one-time cleanup of the legacy v1 ("Looker Studio") materialized views.
--
-- Run once against prod (cobenefits-api) as the owning role, then never again.
-- Looker Studio is retired and the dbt pipeline (analytics_internal / analytics
-- schemas) replaced these views.
--
-- Prod state when this was written (verified on the GRAY replica):
--   * Only these four matviews remain in `public`. `data`, `reference_data_*`,
--     `data_current_benefits`, `data_householdmembers`, `data_immediate_needs`,
--     `data_income`, `data_expenses` and the `data_tenant` view are already gone.
--   * Nothing depends on them, no role other than the owner can read them, and
--     no Metabase card, segment or snippet references them.
--
-- Deliberately no CASCADE: if something unexpectedly depends on a view, Postgres
-- refuses the drop instead of silently removing the dependent.
--
-- Before running:
--   1. Delete the `manage.py refresh_views` jobs in Heroku Scheduler.
--   2. Confirm a recent prod backup exists (`heroku pg:backups -a cobenefits-api`).
-- After running:
--   SELECT matviewname FROM pg_matviews WHERE schemaname = 'public';  -- expect 0 rows
--
-- Recovery: see recovery.sql in this folder (data_dates, data_referrer_codes_nc).
-- data_programs and data_referrer_codes are in git history before the MFB-1192
-- cleanup commit (data-queries/data_programs.sql, data_referrer_codes.sql).

BEGIN;

DROP MATERIALIZED VIEW IF EXISTS public.data_programs;
DROP MATERIALIZED VIEW IF EXISTS public.data_referrer_codes_nc;
DROP MATERIALIZED VIEW IF EXISTS public.data_referrer_codes;
DROP MATERIALIZED VIEW IF EXISTS public.data_dates;

COMMIT;
