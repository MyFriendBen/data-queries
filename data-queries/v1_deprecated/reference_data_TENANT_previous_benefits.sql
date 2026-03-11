-- # Drop Previous Version #
-- Uncomment next line to drop the view before replacing it. It's sometimes best to do this if the data type of
-- a column might change, for example.

drop view if exists
    reference_data_previous_benefits_2
--     reference_data_211co_previous_benefits
--     reference_data_bia_previous_benefits
--     reference_data_brightbytext_previous_benefits
--     reference_data_cch_previous_benefits
--     reference_data_cedp_previous_benefits
--     reference_data_dhs_previous_benefits
--     reference_data_eaglecounty_previous_benefits
--     reference_data_gac_previous_benefits
--     reference_data_jeffcohs_previous_benefits
--     reference_data_lgs_previous_benefits
--     reference_data_salud_previous_benefits
--     reference_data_villageexchange_previous_benefits

-- # Create or Replace View #
-- Uncomment next line and ';' at the end of this query to create the view
create view
    reference_data_previous_benefits_2 as
--     reference_data_211co_previous_benefits as
--     reference_data_bia_previous_benefits as
--     reference_data_brightbytext_previous_benefits as
--     reference_data_cch_previous_benefits as
--     reference_data_cedp_previous_benefits as
--     reference_data_dhs_previous_benefits as
--     reference_data_eaglecounty_previous_benefits as
--     reference_data_gac_previous_benefits as
--     reference_data_jeffcohs_previous_benefits as
--     reference_data_lgs_previous_benefits as
--     reference_data_salud_previous_benefits as
--     reference_data_villageexchange_previous_benefits as

select
    rdpb.benefits
    ,rdpb.count
    ,rdpb.count / Round((SELECT count FROM reference_data_previous_benefits WHERE benefits='benefits_true'),4) as percent_of_total
from reference_data_previous_benefits rdpb
group by rdpb.benefits, rdpb.count
