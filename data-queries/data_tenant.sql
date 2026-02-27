-- Recreate the data_tenant view with row-level security
CREATE VIEW public.data_tenant
WITH (security_barrier = TRUE)        -- thwarts OR-1=1 tricks
AS
SELECT *
FROM public.data                    -- your existing MV
WHERE
    white_label_id
    = regexp_replace(current_user, '[^0-9]', '', 'g')::int;

-- Restore permissions (adjust role names as needed based on your environment)
GRANT USAGE ON SCHEMA public TO wl_nc_5_ro;
GRANT SELECT ON public.data_tenant TO wl_nc_5_ro;
