-- Recreate the data_tenant view with row-level security
CREATE VIEW public.data_tenant
WITH (security_barrier = TRUE)        -- thwarts OR-1=1 tricks
AS
SELECT *
FROM public.data                    -- your existing MV
WHERE
    white_label_id
    = (regexp_match(current_user, '^wl_[a-z_]+_([0-9]+)_ro$'))[1]::int;

-- Grant permissions to each tenant role (repeat for every wl_<state>_<id>_ro credential)
-- Example for NC (white_label_id=5):
GRANT USAGE ON SCHEMA public TO wl_nc_5_ro;
GRANT SELECT ON public.data_tenant TO wl_nc_5_ro;
-- Example for CO (white_label_id=1):
-- GRANT USAGE ON SCHEMA public TO wl_co_1_ro;
-- GRANT SELECT ON public.data_tenant TO wl_co_1_ro;
