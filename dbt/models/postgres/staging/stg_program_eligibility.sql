{{
  config(
    materialized='view',
    description='Program eligibility aggregated by snapshot'
  )
}}

SELECT
    eligibility_snapshot_id,
    sum(CASE WHEN name_abbreviated = 'acp' THEN estimated_value ELSE 0 END) AS acp_annual,
    sum(CASE WHEN name_abbreviated = 'andcs' THEN estimated_value ELSE 0 END) AS andcs_annual,
    sum(CASE WHEN name_abbreviated = 'awd_medicaid' THEN estimated_value ELSE 0 END) AS awd_medicaid_annual,
    sum(CASE WHEN name_abbreviated = 'bca' THEN estimated_value ELSE 0 END) AS bca_annual,
    sum(CASE WHEN name_abbreviated = 'ccap' THEN estimated_value ELSE 0 END) AS ccap_annual,
    sum(CASE WHEN name_abbreviated = 'cdhcs' THEN estimated_value ELSE 0 END) AS cdhcs_annual,
    sum(CASE WHEN name_abbreviated = 'cfhc' THEN estimated_value ELSE 0 END) AS cfhc_annual,
    sum(CASE WHEN name_abbreviated = 'chp' THEN estimated_value ELSE 0 END) AS chp_annual,
    sum(CASE WHEN name_abbreviated = 'chs' THEN estimated_value ELSE 0 END) AS chs_annual,
    sum(CASE WHEN name_abbreviated = 'cocb' THEN estimated_value ELSE 0 END) AS cocb_annual,
    sum(CASE WHEN name_abbreviated = 'coctc' THEN estimated_value ELSE 0 END) AS coctc_annual,
    sum(CASE WHEN name_abbreviated = 'coeitc' THEN estimated_value ELSE 0 END) AS coeitc_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_bheap' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_bheap_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_bhgap' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_bhgap_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_care' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_care_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_cngba' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_cngba_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_cowap' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_cowap_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_cpcr' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_cpcr_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_ea' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_ea_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_energy_ebt' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_energy_ebt_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_eoc' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_eoc_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_eoccip' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_eoccip_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_eocs' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_eocs_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_leap' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_leap_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_poipp' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_poipp_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_ubp' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_ubp_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_xceleap' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_xceleap_annual,
    sum(CASE WHEN name_abbreviated = 'co_energy_calculator_xcelgap' THEN estimated_value ELSE 0 END)
        AS co_energy_calculator_xcelgap_annual,
    sum(CASE WHEN name_abbreviated = 'co_medicaid' THEN estimated_value ELSE 0 END) AS co_medicaid_annual,
    sum(CASE WHEN name_abbreviated = 'co_snap' THEN estimated_value ELSE 0 END) AS co_snap_annual,
    sum(CASE WHEN name_abbreviated = 'co_tanf' THEN estimated_value ELSE 0 END) AS co_tanf_annual,
    sum(CASE WHEN name_abbreviated = 'co_wic' THEN estimated_value ELSE 0 END) AS co_wic_annual,
    sum(CASE WHEN name_abbreviated = '_dev_ineligible' THEN estimated_value ELSE 0 END) AS _dev_ineligible_annual,
    sum(CASE WHEN name_abbreviated = 'cowap' THEN estimated_value ELSE 0 END) AS cowap_annual,
    sum(CASE WHEN name_abbreviated = 'cpcr' THEN estimated_value ELSE 0 END) AS cpcr_annual,
    sum(CASE WHEN name_abbreviated = 'ctc' THEN estimated_value ELSE 0 END) AS ctc_annual,
    sum(CASE WHEN name_abbreviated = 'cwd_medicaid' THEN estimated_value ELSE 0 END) AS cwd_medicaid_annual,
    sum(CASE WHEN name_abbreviated = 'dpp' THEN estimated_value ELSE 0 END) AS dpp_annual,
    sum(CASE WHEN name_abbreviated = 'dptr' THEN estimated_value ELSE 0 END) AS dptr_annual,
    sum(CASE WHEN name_abbreviated = 'dsr' THEN estimated_value ELSE 0 END) AS dsr_annual,
    sum(CASE WHEN name_abbreviated = 'dtr' THEN estimated_value ELSE 0 END) AS dtr_annual,
    sum(CASE WHEN name_abbreviated = 'ede' THEN estimated_value ELSE 0 END) AS ede_annual,
    sum(CASE WHEN name_abbreviated = 'eitc' THEN estimated_value ELSE 0 END) AS eitc_annual,
    sum(CASE WHEN name_abbreviated = 'emergency_medicaid' THEN estimated_value ELSE 0 END) AS emergency_medicaid_annual,
    sum(CASE WHEN name_abbreviated = 'erap' THEN estimated_value ELSE 0 END) AS erap_annual,
    sum(CASE WHEN name_abbreviated = 'erc' THEN estimated_value ELSE 0 END) AS erc_annual,
    sum(CASE WHEN name_abbreviated = 'fatc' THEN estimated_value ELSE 0 END) AS fatc_annual,
    sum(CASE WHEN name_abbreviated = 'fps' THEN estimated_value ELSE 0 END) AS fps_annual,
    sum(CASE WHEN name_abbreviated = 'leap' THEN estimated_value ELSE 0 END) AS leap_annual,
    sum(CASE WHEN name_abbreviated = 'lifeline' THEN estimated_value ELSE 0 END) AS lifeline_annual,
    sum(CASE WHEN name_abbreviated = 'lwcr' THEN estimated_value ELSE 0 END) AS lwcr_annual,
    sum(CASE WHEN name_abbreviated = 'ma_aca' THEN estimated_value ELSE 0 END) AS ma_aca_annual,
    sum(CASE WHEN name_abbreviated = 'ma_ccdf' THEN estimated_value ELSE 0 END) AS ma_ccdf_annual,
    sum(CASE WHEN name_abbreviated = 'ma_cfc' THEN estimated_value ELSE 0 END) AS ma_cfc_annual,
    sum(CASE WHEN name_abbreviated = 'ma_eaedc' THEN estimated_value ELSE 0 END) AS ma_eaedc_annual,
    sum(CASE WHEN name_abbreviated = 'ma_maeitc' THEN estimated_value ELSE 0 END) AS ma_maeitc_annual,
    sum(CASE WHEN name_abbreviated = 'ma_mass_health' THEN estimated_value ELSE 0 END) AS ma_mass_health_annual,
    sum(CASE WHEN name_abbreviated = 'ma_mass_health_limited' THEN estimated_value ELSE 0 END)
        AS ma_mass_health_limited_annual,
    sum(CASE WHEN name_abbreviated = 'ma_mbta' THEN estimated_value ELSE 0 END) AS ma_mbta_annual,
    sum(CASE WHEN name_abbreviated = 'ma_snap' THEN estimated_value ELSE 0 END) AS ma_snap_annual,
    sum(CASE WHEN name_abbreviated = 'ma_ssp' THEN estimated_value ELSE 0 END) AS ma_ssp_annual,
    sum(CASE WHEN name_abbreviated = 'ma_tafdc' THEN estimated_value ELSE 0 END) AS ma_tafdc_annual,
    sum(CASE WHEN name_abbreviated = 'ma_wic' THEN estimated_value ELSE 0 END) AS ma_wic_annual,
    sum(CASE WHEN name_abbreviated = 'medicaid' THEN estimated_value ELSE 0 END) AS medicaid_annual,
    sum(CASE WHEN name_abbreviated = 'medicare_savings' THEN estimated_value ELSE 0 END) AS medicare_savings_annual,
    sum(CASE WHEN name_abbreviated = 'mydenver' THEN estimated_value ELSE 0 END) AS mydenver_annual,
    sum(CASE WHEN name_abbreviated = 'myspark' THEN estimated_value ELSE 0 END) AS myspark_annual,
    sum(CASE WHEN name_abbreviated = 'nc_aca' THEN estimated_value ELSE 0 END) AS nc_aca_annual,
    sum(CASE WHEN name_abbreviated = 'nccip' THEN estimated_value ELSE 0 END) AS nccip_annual,
    sum(CASE WHEN name_abbreviated = 'nc_emergency_medicaid' THEN estimated_value ELSE 0 END)
        AS nc_emergency_medicaid_annual,
    sum(CASE WHEN name_abbreviated = 'nc_lieap' THEN estimated_value ELSE 0 END) AS nc_lieap_annual,
    sum(CASE WHEN name_abbreviated = 'nc_medicaid' THEN estimated_value ELSE 0 END) AS nc_medicaid_annual,
    sum(CASE WHEN name_abbreviated = 'nc_scca' THEN estimated_value ELSE 0 END) AS nc_scca_annual,
    sum(CASE WHEN name_abbreviated = 'nc_snap' THEN estimated_value ELSE 0 END) AS nc_snap_annual,
    sum(CASE WHEN name_abbreviated = 'nc_tanf' THEN estimated_value ELSE 0 END) AS nc_tanf_annual,
    sum(CASE WHEN name_abbreviated = 'ncwap' THEN estimated_value ELSE 0 END) AS ncwap_annual,
    sum(CASE WHEN name_abbreviated = 'nc_wic' THEN estimated_value ELSE 0 END) AS nc_wic_annual,
    sum(CASE WHEN name_abbreviated = 'il_aabd' THEN estimated_value ELSE 0 END) AS il_aabd_annual,
    sum(CASE WHEN name_abbreviated = 'il_aca' THEN estimated_value ELSE 0 END) AS il_aca_annual,
    sum(CASE WHEN name_abbreviated = 'il_aca_adults' THEN estimated_value ELSE 0 END) AS il_aca_adults_annual,
    sum(CASE WHEN name_abbreviated = 'il_all_kids' THEN estimated_value ELSE 0 END) AS il_all_kids_annual,
    sum(CASE WHEN name_abbreviated = 'il_bap' THEN estimated_value ELSE 0 END) AS il_bap_annual,
    sum(CASE WHEN name_abbreviated = 'il_ctc' THEN estimated_value ELSE 0 END) AS il_ctc_annual,
    sum(CASE WHEN name_abbreviated = 'il_eitc' THEN estimated_value ELSE 0 END) AS il_eitc_annual,
    sum(CASE WHEN name_abbreviated = 'il_family_care' THEN estimated_value ELSE 0 END) AS il_family_care_annual,
    sum(CASE WHEN name_abbreviated = 'il_liheap' THEN estimated_value ELSE 0 END) AS il_liheap_annual,
    sum(CASE WHEN name_abbreviated = 'il_medicaid' THEN estimated_value ELSE 0 END) AS il_medicaid_annual,
    sum(CASE WHEN name_abbreviated = 'il_moms_and_babies' THEN estimated_value ELSE 0 END) AS il_moms_and_babies_annual,
    sum(CASE WHEN name_abbreviated = 'il_nslp' THEN estimated_value ELSE 0 END) AS il_nslp_annual,
    sum(CASE WHEN name_abbreviated = 'il_snap' THEN estimated_value ELSE 0 END) AS il_snap_annual,
    sum(CASE WHEN name_abbreviated = 'il_tanf' THEN estimated_value ELSE 0 END) AS il_tanf_annual,
    sum(CASE WHEN name_abbreviated = 'il_transit_reduced_fare' THEN estimated_value ELSE 0 END)
        AS il_transit_reduced_fare_annual,
    sum(CASE WHEN name_abbreviated = 'il_wic' THEN estimated_value ELSE 0 END) AS il_wic_annual,
    sum(CASE WHEN name_abbreviated = 'nf' THEN estimated_value ELSE 0 END) AS nf_annual,
    sum(CASE WHEN name_abbreviated = 'nfp' THEN estimated_value ELSE 0 END) AS nfp_annual,
    sum(CASE WHEN name_abbreviated = 'nslp' THEN estimated_value ELSE 0 END) AS nslp_annual,
    sum(CASE WHEN name_abbreviated = 'oap' THEN estimated_value ELSE 0 END) AS oap_annual,
    sum(CASE WHEN name_abbreviated = 'omnisalud' THEN estimated_value ELSE 0 END) AS omnisalud_annual,
    sum(CASE WHEN name_abbreviated = 'pell_grant' THEN estimated_value ELSE 0 END) AS pell_grant_annual,
    sum(CASE WHEN name_abbreviated = 'rag' THEN estimated_value ELSE 0 END) AS rag_annual,
    sum(CASE WHEN name_abbreviated = 'rhc' THEN estimated_value ELSE 0 END) AS rhc_annual,
    sum(CASE WHEN name_abbreviated = 'rtdlive' THEN estimated_value ELSE 0 END) AS rtdlive_annual,
    sum(CASE WHEN name_abbreviated = 'shitc' THEN estimated_value ELSE 0 END) AS shitc_annual,
    sum(CASE WHEN name_abbreviated = 'sunbucks' THEN estimated_value ELSE 0 END) AS sunbucks_annual,
    sum(CASE WHEN name_abbreviated = 'snap' THEN estimated_value ELSE 0 END) AS snap_annual,
    sum(CASE WHEN name_abbreviated = 'ssdi' THEN estimated_value ELSE 0 END) AS ssdi_annual,
    sum(CASE WHEN name_abbreviated = 'ssi' THEN estimated_value ELSE 0 END) AS ssi_annual,
    sum(CASE WHEN name_abbreviated = 'tabor' THEN estimated_value ELSE 0 END) AS tabor_annual,
    sum(CASE WHEN name_abbreviated = 'tanf' THEN estimated_value ELSE 0 END) AS tanf_annual,
    sum(CASE WHEN name_abbreviated = 'trua' THEN estimated_value ELSE 0 END) AS trua_annual,
    sum(CASE WHEN name_abbreviated = 'ubp' THEN estimated_value ELSE 0 END) AS ubp_annual,
    sum(CASE WHEN name_abbreviated = 'upk' THEN estimated_value ELSE 0 END) AS upk_annual,
    sum(CASE WHEN name_abbreviated = 'wic' THEN estimated_value ELSE 0 END) AS wic_annual
FROM {{ source('django_apps', 'screener_programeligibilitysnapshot') }}
WHERE eligible = TRUE
GROUP BY eligibility_snapshot_id
