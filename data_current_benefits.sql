--# This query will create a current_benefits table #
-- The table is used as a source for Looker Studio dashboards.
create materialized view
    data_currentbenefits as

with base as (
    select
        white_label_id
        ,partner
        ,sum(case when acp_annual > 0 then 1 else 0 end)                  as acp
        ,sum(case when andcs_annual > 0 then 1 else 0 end)               as andcs
        ,sum(case when awd_medicaid_annual > 0 then 1 else 0 end)        as awd_medicaid
        ,sum(case when bca_annual > 0 then 1 else 0 end)                 as bca
        ,sum(case when cccap_annual > 0 then 1 else 0 end)               as cccap
        ,sum(case when cdhcs_annual > 0 then 1 else 0 end)               as cdhcs
        ,sum(case when cfhc_annual > 0 then 1 else 0 end)               as cfhc
        ,sum(case when chp_annual > 0 then 1 else 0 end)               as chp
        ,sum(case when chs_annual > 0 then 1 else 0 end)               as chs
        ,sum(case when cocb_annual > 0 then 1 else 0 end)               as cocb
        ,sum(case when coctc_annual > 0 then 1 else 0 end)               as coctc
        ,sum(case when coeitc_annual > 0 then 1 else 0 end)               as coeitc
        ,sum(case when co_energy_calculator_bheap_annual > 0 then 1 else 0 end)               as co_energy_calculator_bheap
        ,sum(case when co_energy_calculator_bhgap_annual > 0 then 1 else 0 end)               as co_energy_calculator_bhgap
        ,sum(case when co_energy_calculator_care_annual > 0 then 1 else 0 end)               as co_energy_calculator_care
        ,sum(case when co_energy_calculator_cngba_annual > 0 then 1 else 0 end)               as co_energy_calculator_cngba
        ,sum(case when co_energy_calculator_cpcr_annual > 0 then 1 else 0 end)               as co_energy_calculator_cpcr
        ,sum(case when co_energy_calculator_ea_annual > 0 then 1 else 0 end)               as co_energy_calculator_ea
        ,sum(case when co_energy_calculator_energy_ebt_annual > 0 then 1 else 0 end)               as co_energy_calculator_ebt
        ,sum(case when co_energy_calculator_eoc_annual > 0 then 1 else 0 end)               as co_energy_calculator_eoc
        ,sum(case when co_energy_calculator_eoccip_annual > 0 then 1 else 0 end)               as co_energy_calculator_eoccip
        ,sum(case when co_energy_calculator_eocs_annual > 0 then 1 else 0 end)               as co_energy_calculator_eocs
        ,sum(case when co_energy_calculator_leap_annual > 0 then 1 else 0 end)               as co_energy_calculator_leap
        ,sum(case when co_energy_calculator_poipp_annual > 0 then 1 else 0 end)               as co_energy_calculator_poipp
        ,sum(case when co_energy_calculator_ubp_annual > 0 then 1 else 0 end)               as co_energy_calculator_ubp
        ,sum(case when co_energy_calculator_xceleap_annual > 0 then 1 else 0 end)               as co_energy_calculator_xceleap
        ,sum(case when co_energy_calculator_xcelgap_annual > 0 then 1 else 0 end)               as co_energy_calculator_xcelgap
        ,sum(case when co_medicaid_annual > 0 then 1 else 0 end)               as co_medicaid
        ,sum(case when co_snap_annual > 0 then 1 else 0 end)               as co_snap
        ,sum(case when co_tanf_annual > 0 then 1 else 0 end)               as co_tanf
        ,sum(case when co_wic_annual > 0 then 1 else 0 end)               as co_wic
        ,sum(case when cowap_annual > 0 then 1 else 0 end)               as cowap
        ,sum(case when cpcr_annual > 0 then 1 else 0 end)               as cpcr
        ,sum(case when ctc_annual > 0 then 1 else 0 end)               as ctc
        ,sum(case when cwd_medicaid_annual > 0 then 1 else 0 end)               as cwd_medicaid
        ,sum(case when dpp_annual > 0 then 1 else 0 end)               as dpp
        ,sum(case when dptr_annual > 0 then 1 else 0 end)               as dptr
        ,sum(case when dsr_annual > 0 then 1 else 0 end)               as dsr
        ,sum(case when dtr_annual > 0 then 1 else 0 end)               as dtr
        ,sum(case when ede_annual > 0 then 1 else 0 end)               as ede
        ,sum(case when eitc_annual > 0 then 1 else 0 end)               as eitc
        ,sum(case when emergency_medicaid_annual > 0 then 1 else 0 end)               as emergency_medicaid
        ,sum(case when erap_annual > 0 then 1 else 0 end)               as erap
        ,sum(case when erc_annual > 0 then 1 else 0 end)               as erc
        ,sum(case when fatc_annual > 0 then 1 else 0 end)               as fatc
        ,sum(case when fps_annual > 0 then 1 else 0 end)               as fps
        ,sum(case when leap_annual > 0 then 1 else 0 end)               as leap
        ,sum(case when lifeline_annual > 0 then 1 else 0 end)               as lifeline
        ,sum(case when lwcr_annual > 0 then 1 else 0 end)               as lwcr
        ,sum(case when ma_aca_annual > 0 then 1 else 0 end)               as ma_aca
        ,sum(case when ma_ccdf_annual > 0 then 1 else 0 end)               as ma_ccdf
        ,sum(case when ma_cfc_annual > 0 then 1 else 0 end)               as ma_cfc
        ,sum(case when ma_eaedc_annual > 0 then 1 else 0 end)               as ma_eaedc
        ,sum(case when ma_maeitc_annual > 0 then 1 else 0 end)               as ma_maeitc
        ,sum(case when ma_mass_health_annual > 0 then 1 else 0 end)               as ma_mass_health
        ,sum(case when ma_mass_health_limited_annual > 0 then 1 else 0 end)               as ma_mass_health_limited
        ,sum(case when ma_mbta_annual > 0 then 1 else 0 end)               as ma_mbta
        ,sum(case when ma_snap_annual > 0 then 1 else 0 end)               as ma_snap
        ,sum(case when ma_ssp_annual > 0 then 1 else 0 end)               as ma_ssp
        ,sum(case when ma_tafdc_annual > 0 then 1 else 0 end)               as ma_tafdc
        ,sum(case when ma_wic_annual > 0 then 1 else 0 end)               as ma_wic
        ,sum(case when medicaid_annual > 0 then 1 else 0 end)               as medicaid
        ,sum(case when medicare_savings_annual > 0 then 1 else 0 end)               as medicare_savings
        ,sum(case when mydenver_annual > 0 then 1 else 0 end)               as mydenver
        ,sum(case when myspark_annual > 0 then 1 else 0 end)               as myspark
        ,sum(case when nc_aca_annual > 0 then 1 else 0 end)               as nc_aca
        ,sum(case when nccip_annual > 0 then 1 else 0 end)               as nccip
        ,sum(case when nc_emergency_medicaid_annual > 0 then 1 else 0 end)               as nc_emergency_medicaid
        ,sum(case when nc_lieap_annual > 0 then 1 else 0 end)               as nc_lieap
        ,sum(case when nc_medicaid_annual > 0 then 1 else 0 end)               as nc_medicaid
        ,sum(case when nc_scca_annual > 0 then 1 else 0 end)               as nc_scca
        ,sum(case when nc_snap_annual > 0 then 1 else 0 end)               as nc_snap
        ,sum(case when nc_tanf_annual > 0 then 1 else 0 end)               as nc_tanf
        ,sum(case when ncwap_annual > 0 then 1 else 0 end)               as nc_wap
        ,sum(case when nc_wic_annual > 0 then 1 else 0 end)               as nc_wic
        ,sum(case when il_aabd_annual > 0 then 1 else 0 end)               as il_aabd
        ,sum(case when il_aca_annual > 0 then 1 else 0 end)               as il_aca
        ,sum(case when il_aca_adults_annual > 0 then 1 else 0 end)               as il_aca_adults
        ,sum(case when il_all_kids_annual > 0 then 1 else 0 end)               as il_all_kids
        ,sum(case when il_bap_annual > 0 then 1 else 0 end)               as il_bap
        ,sum(case when il_ctc_annual > 0 then 1 else 0 end)               as il_ctc
        ,sum(case when il_eitc_annual > 0 then 1 else 0 end)               as il_eitc
        ,sum(case when il_family_care_annual > 0 then 1 else 0 end)               as il_family_care
        ,sum(case when il_liheap_annual > 0 then 1 else 0 end)               as il_liheap
        ,sum(case when il_medicaid_annual > 0 then 1 else 0 end)               as il_medicaid
        ,sum(case when il_moms_and_babies_annual > 0 then 1 else 0 end)               as il_moms_and_babies
        ,sum(case when il_nslp_annual > 0 then 1 else 0 end)               as il_nslp
        ,sum(case when il_snap_annual > 0 then 1 else 0 end)               as il_snap
        ,sum(case when il_tanf_annual > 0 then 1 else 0 end)               as il_tanf
        ,sum(case when il_transit_reduced_fare_annual > 0 then 1 else 0 end)               as il_transit_reduced_fare
        ,sum(case when il_wic_annual > 0 then 1 else 0 end)               as il_wic
        ,sum(case when nf_annual > 0 then 1 else 0 end)               as nf
        ,sum(case when nfp_annual > 0 then 1 else 0 end)               as nfp
        ,sum(case when nslp_annual > 0 then 1 else 0 end)               as nslp
        ,sum(case when oap_annual > 0 then 1 else 0 end)               as oap
        ,sum(case when omnisalud_annual > 0 then 1 else 0 end)               as omnisalud
        ,sum(case when pell_grant_annual > 0 then 1 else 0 end)               as pell_grant
        ,sum(case when rag_annual > 0 then 1 else 0 end)               as rag
        ,sum(case when rhc_annual > 0 then 1 else 0 end)               as rhc
        ,sum(case when rtdlive_annual > 0 then 1 else 0 end)               as rtdlive
        ,sum(case when shitc_annual > 0 then 1 else 0 end)               as shitc
        ,sum(case when sunbucks_annual > 0 then 1 else 0 end)               as sunbucks
        ,sum(case when snap_annual > 0 then 1 else 0 end)               as snap
        ,sum(case when ssdi_annual > 0 then 1 else 0 end)               as ssdi
        ,sum(case when ssi_annual > 0 then 1 else 0 end)               as ssi
        ,sum(case when tabor_annual > 0 then 1 else 0 end)               as tabor
        ,sum(case when tanf_annual > 0 then 1 else 0 end)               as tanf
        ,sum(case when trua_annual > 0 then 1 else 0 end)               as trua
        ,sum(case when ubp_annual > 0 then 1 else 0 end)               as ubp
        ,sum(case when wic_annual > 0 then 1 else 0 end)               as wic
    from data
    group by white_label_id, partner
    )

select
    unnest(array[
        'ACP'
        ,'ANDCS'
        ,'AWD Medicaid'
        ,'BCA'
        ,'CCCAP'
        ,'CDHCS'
        ,'CFHC'
        ,'CHP'
        ,'CHS'
        ,'COCB'
        ,'COCTC'
        ,'COEITC'
        ,'CO Energy Calculator BHEAP'
        ,'CO Energy Calculator BHGAP'
        ,'CO Energy Calculator Care'
        ,'CO Energy Calculator CNGBA'
        ,'CO Energy Calculator CPCR'
        ,'CO Energy Calculator EA'
        ,'CO Energy Calculator EBT'
        ,'CO Energy Calculator EOC'
        ,'CO Energy Calculator EOC CIP'
        ,'CO Energy Calculator EOCS'
        ,'CO Energy Calculator LEAP'
        ,'CO Energy Calculator POIPP'
        ,'CO Energy Calculator UBP'
        ,'CO Energy Calculator XCELEAP'
        ,'CO Energy Calculator XCELGAP'
        ,'CO Medicaid'
        ,'CO SNAP'
        ,'CO TANF'
        ,'CO WIC'
        ,'COWAP'
        ,'CPCR'
        ,'CTC'
        ,'CWD Medicaid'
        ,'DPP'
        ,'DPTR'
        ,'DSR'
        ,'DTR'
        ,'EDE'
        ,'EITC'
        ,'Emergency Medicaid'
        ,'ERAP'
        ,'ERC'
        ,'FATC'
        ,'FPS'
        ,'LEAP'
        ,'Lifeline'
        ,'LWCR'
        ,'MA ACA'
        ,'MA CCDF'
        ,'MA CFC'
        ,'MA EAEDC'
        ,'MA EITC'
        ,'MA Mass Health'
        ,'MA Mass Health Limited Annual'
        ,'MA MBTA'
        ,'MA SNAP'
        ,'MA SSP'
        ,'MA TAFDC'
        ,'MA WIC'
        ,'Medicaid'
        ,'Medicare Savings'
        ,'My Denver'
        ,'My Spark'
        ,'NC ACA'
        ,'NCCIP'
        ,'NC Emergency Medicaid'
        ,'NC LIEAP'
        ,'NC Medicaid'
        ,'NC SCCA'
        ,'NC SNAP'
        ,'NC TANF'
        ,'NC WAP'
        ,'NC WIC'
        ,'IL AABD'
        ,'IL ACA'
        ,'IL ACA Adults'
        ,'IL All Kids'
        ,'IL BAP'
        ,'IL CTC'
        ,'IL EITC'
        ,'IL Family Care'
        ,'IL LIHEAP'
        ,'IL Medicaid'
        ,'IL Moms and Babies'
        ,'IL NSLP'
        ,'IL SNAP'
        ,'IL TANF'
        ,'IL Transit Reduced Fare'
        ,'IL WIC'
        ,'NF'
        ,'MFP'
        ,'NSLP'
        ,'OAP'
        ,'Omnisalud'
        ,'Pell Grant'
        ,'RAG'
        ,'RHC'
        ,'RTD Live'
        ,'SHITC'
        ,'Sunbucks'
        ,'SNAP'
        ,'SSDI'
        ,'SSI'
        ,'Tabor'
        ,'TANF'
        ,'TRUA'
        ,'UBP'
        ,'WIC'
        ]) as Benefit
    ,unnest(array[
        acp
        ,andcs
        ,awd_medicaid
        ,bca
        ,cccap
        ,cdhcs
        ,cfhc
        ,chp
        ,chs
        ,cocb
        ,coctc
        ,coeitc
        ,co_energy_calculator_bheap
        ,co_energy_calculator_bhgap
        ,co_energy_calculator_care
        ,co_energy_calculator_cngba
        ,co_energy_calculator_cpcr
        ,co_energy_calculator_ea
        ,co_energy_calculator_ebt
        ,co_energy_calculator_eoc
        ,co_energy_calculator_eoccip
        ,co_energy_calculator_eocs
        ,co_energy_calculator_leap
        ,co_energy_calculator_poipp
        ,co_energy_calculator_ubp
        ,co_energy_calculator_xceleap
        ,co_energy_calculator_xcelgap
        ,co_medicaid
        ,co_snap
        ,co_tanf
        ,co_wic
        ,cowap
        ,cpcr
        ,ctc
        ,cwd_medicaid
        ,dpp
        ,dptr
        ,dsr
        ,dtr
        ,ede
        ,eitc
        ,emergency_medicaid
        ,erap
        ,erc
        ,fatc
        ,fps
        ,leap
        ,lifeline
        ,lwcr
        ,ma_aca
        ,ma_ccdf
        ,ma_cfc
        ,ma_eaedc
        ,ma_maeitc
        ,ma_mass_health
        ,ma_mass_health_limited
        ,ma_mbta
        ,ma_snap
        ,ma_ssp
        ,ma_ssp
        ,ma_tafdc
        ,ma_wic
        ,medicaid
        ,medicare_savings
        ,mydenver
        ,myspark
        ,nc_aca
        ,nccip
        ,nc_emergency_medicaid
        ,nc_lieap
        ,nc_medicaid
        ,nc_scca
        ,nc_snap
        ,nc_tanf
        ,nc_wap
        ,nc_wic
        ,il_aabd
        ,il_aca
        ,il_aca_adults
        ,il_all_kids
        ,il_bap
        ,il_ctc
        ,il_eitc
        ,il_family_care
        ,il_liheap
        ,il_medicaid
        ,il_moms_and_babies
        ,il_nslp
        ,il_snap
        ,il_tanf
        ,il_transit_reduced_fare
        ,il_wic
        ,nf
        ,nfp
        ,nslp
        ,oap
        ,omnisalud
        ,pell_grant
        ,rag
        ,rhc
        ,rtdlive
        ,shitc
        ,sunbucks
        ,snap
        ,ssdi
        ,ssi
        ,tabor
        ,tanf
        ,trua
        ,ubp
        ,wic
        ]) as Count
    ,white_label_id
    ,partner
from base;
