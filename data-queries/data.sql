-- # This will create the 'data' materialized view on which the dashboards are based.

-- # Get the latest eligibility snapshot for each screener
create materialized view
    data as

with snapshots_count as (
    select
        screen_id
        ,COUNT(distinct id) AS snapshots
    from screener_eligibilitysnapshot
    group by screen_id
    ),


latest_eligibility_snapshot_by_screen_id as not materialized (
    select
        sc.screen_id
        ,(SELECT id
            FROM screener_eligibilitysnapshot sel
            WHERE sel.screen_id = sc.screen_id
            ORDER BY sel.submission_date DESC
            LIMIT 1) AS latest_snapshot_id
        ,sc.snapshots
    from snapshots_count sc
    group by sc.screen_id, sc.snapshots
    order by sc.screen_id desc
    ),


-- # Create a list of all unique referrer codes to reference
all_referrer_codes as not materialized (
    select distinct referrer_code
    from data_referrer_codes
    where referrer_code is not null and referrer_code <> ''
    ),


-- # Monthly Income
monthly_income_by_screener_id as not materialized (
    select
        screen_id,
        sum(case
           when frequency = 'yearly' then amount / 12
           when frequency = 'monthly' then amount
           when frequency = 'weekly' then (amount * 52) / 12
           when frequency = 'hourly' then (amount * 40 * 52) / 12
           when frequency = 'biweekly' then (amount * 26) / 12
           when frequency = 'semimonthly' then (amount * 24) / 12
       end) as monthly_income
    from screener_incomestream
    group by screen_id
    order by screen_id
    ),


-- Monthly Expenses
monthly_expenses_by_screener_id as not materialized (
    select
        screen_id,
        sum(case
           when frequency = 'yearly' then amount / 12
           when frequency = 'monthly' then amount
           when frequency = 'weekly' then (amount * 52) / 12
           when frequency = 'hourly' then (amount * 40 * 52) / 12
           when frequency = 'biweekly' then (amount * 26) / 12
           when frequency = 'semimonthly' then (amount * 24) / 12
       end) as monthly_expenses
    from screener_expense
    group by screen_id
    order by screen_id
    ),

-- # Program eligibility based on latest eligibility snapshot
latest_program_eligibility as not materialized (
    select
        spes.eligibility_snapshot_id
-- # Add lines like below for every new benefit in screener_program_eligibilitysnapshot
         ,sum(case when spes.name_abbreviated = 'acp' then spes.estimated_value ELSE 0 end)            as acp_annual
         ,sum(case when spes.name_abbreviated = 'andcs' then spes.estimated_value ELSE 0 end)          as andcs_annual
         ,sum(case when spes.name_abbreviated = 'awd_medicaid' then spes.estimated_value ELSE 0 end)   as awd_medicaid_annual
         ,sum(case when spes.name_abbreviated = 'bca' then spes.estimated_value ELSE 0 end)            as bca_annual
         ,sum(case when spes.name_abbreviated = 'cccap' then spes.estimated_value ELSE 0 end)          as cccap_annual
         ,sum(case when spes.name_abbreviated = 'cdhcs' then spes.estimated_value ELSE 0 end)          as cdhcs_annual
         ,sum(case when spes.name_abbreviated = 'cfhc' then spes.estimated_value ELSE 0 end)           as cfhc_annual
         ,sum(case when spes.name_abbreviated = 'chp' then spes.estimated_value ELSE 0 end)            as chp_annual
         ,sum(case when spes.name_abbreviated = 'chs' then spes.estimated_value ELSE 0 end)            as chs_annual
         ,sum(case when spes.name_abbreviated = 'cocb' then spes.estimated_value ELSE 0 end)           as cocb_annual
         ,sum(case when spes.name_abbreviated = 'coctc' then spes.estimated_value ELSE 0 end)          as coctc_annual
         ,sum(case when spes.name_abbreviated = 'coeitc' then spes.estimated_value ELSE 0 end)         as coeitc_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_bheap' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_bheap_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_bhgap' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_bhgap_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_care' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_care_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_cngba' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_cngba_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_cowap' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_cowap_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_cpcr' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_cpcr_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_ea' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_ea_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_energy_ebt' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_energy_ebt_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_eoc' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_eoc_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_eoccip' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_eoccip_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_eocs' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_eocs_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_leap' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_leap_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_poipp' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_poipp_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_ubp' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_ubp_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_xceleap' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_xceleap_annual
         ,sum(case when spes.name_abbreviated = 'co_energy_calculator_xcelgap' then spes.estimated_value ELSE 0 end)         as co_energy_calculator_xcelgap_annual
         ,sum(case when spes.name_abbreviated = 'co_medicaid' then spes.estimated_value ELSE 0 end)         as co_medicaid_annual
         ,sum(case when spes.name_abbreviated = 'co_snap' then spes.estimated_value ELSE 0 end)         as co_snap_annual
         ,sum(case when spes.name_abbreviated = 'co_tanf' then spes.estimated_value ELSE 0 end)         as co_tanf_annual
         ,sum(case when spes.name_abbreviated = 'co_wic' then spes.estimated_value ELSE 0 end)         as co_wic_annual
         ,sum(case when spes.name_abbreviated = '_dev_ineligible' then spes.estimated_value ELSE 0 end)         as _dev_ineligible_annual
         ,sum(case when spes.name_abbreviated = 'cowap' then spes.estimated_value ELSE 0 end)           as cowap_annual
         ,sum(case when spes.name_abbreviated = 'cpcr' then spes.estimated_value ELSE 0 end)           as cpcr_annual
         ,sum(case when spes.name_abbreviated = 'ctc' then spes.estimated_value ELSE 0 end)            as ctc_annual
         ,sum(case when spes.name_abbreviated = 'cwd_medicaid' then spes.estimated_value ELSE 0 end)            as cwd_medicaid_annual
         ,sum(case when spes.name_abbreviated = 'dpp' then spes.estimated_value ELSE 0 end)            as dpp_annual
         ,sum(case when spes.name_abbreviated = 'dptr' then spes.estimated_value ELSE 0 end)         as dptr_annual
         ,sum(case when spes.name_abbreviated = 'dsr' then spes.estimated_value ELSE 0 end)         as dsr_annual
         ,sum(case when spes.name_abbreviated = 'dtr' then spes.estimated_value ELSE 0 end)         as dtr_annual
         ,sum(case when spes.name_abbreviated = 'ede' then spes.estimated_value ELSE 0 end)            as ede_annual
         ,sum(case when spes.name_abbreviated = 'eitc' then spes.estimated_value ELSE 0 end)           as eitc_annual
         ,sum(case when spes.name_abbreviated = 'emergency_medicaid' then spes.estimated_value ELSE 0 end)           as emergency_medicaid_annual
         ,sum(case when spes.name_abbreviated = 'erap' then spes.estimated_value ELSE 0 end)         as erap_annual
         ,sum(case when spes.name_abbreviated = 'erc' then spes.estimated_value ELSE 0 end)            as erc_annual
         ,sum(case when spes.name_abbreviated = 'fatc' then spes.estimated_value ELSE 0 end)         as fatc_annual
         ,sum(case when spes.name_abbreviated = 'fps' then spes.estimated_value ELSE 0 end)            as fps_annual
         ,sum(case when spes.name_abbreviated = 'leap' then spes.estimated_value ELSE 0 end)           as leap_annual
         ,sum(case when spes.name_abbreviated = 'lifeline' then spes.estimated_value ELSE 0 end)       as lifeline_annual
         ,sum(case when spes.name_abbreviated = 'lwcr' then spes.estimated_value ELSE 0 end)           as lwcr_annual
         ,sum(case when spes.name_abbreviated = 'ma_aca' then spes.estimated_value ELSE 0 end)         as ma_aca_annual
         ,sum(case when spes.name_abbreviated = 'ma_ccdf' then spes.estimated_value ELSE 0 end)         as ma_ccdf_annual
         ,sum(case when spes.name_abbreviated = 'ma_cfc' then spes.estimated_value ELSE 0 end)         as ma_cfc_annual
         ,sum(case when spes.name_abbreviated = 'ma_eaedc' then spes.estimated_value ELSE 0 end)         as ma_eaedc_annual
         ,sum(case when spes.name_abbreviated = 'ma_maeitc' then spes.estimated_value ELSE 0 end)         as ma_maeitc_annual
         ,sum(case when spes.name_abbreviated = 'ma_mass_health' then spes.estimated_value ELSE 0 end)         as ma_mass_health_annual
         ,sum(case when spes.name_abbreviated = 'ma_mass_health_limited' then spes.estimated_value ELSE 0 end)         as ma_mass_health_limited_annual
         ,sum(case when spes.name_abbreviated = 'ma_mbta' then spes.estimated_value ELSE 0 end)         as ma_mbta_annual
         ,sum(case when spes.name_abbreviated = 'ma_snap' then spes.estimated_value ELSE 0 end)         as ma_snap_annual
         ,sum(case when spes.name_abbreviated = 'ma_ssp' then spes.estimated_value ELSE 0 end)         as ma_ssp_annual
         ,sum(case when spes.name_abbreviated = 'ma_tafdc' then spes.estimated_value ELSE 0 end)         as ma_tafdc_annual
         ,sum(case when spes.name_abbreviated = 'ma_wic' then spes.estimated_value ELSE 0 end)         as ma_wic_annual
         ,sum(case when spes.name_abbreviated = 'medicaid' then spes.estimated_value ELSE 0 end)       as medicaid_annual
         ,sum(case when spes.name_abbreviated = 'medicare_savings' then spes.estimated_value ELSE 0 end)       as medicare_savings_annual
         ,sum(case when spes.name_abbreviated = 'mydenver' then spes.estimated_value ELSE 0 end)       as mydenver_annual
         ,sum(case when spes.name_abbreviated = 'myspark' then spes.estimated_value ELSE 0 end)         as myspark_annual
         ,sum(case when spes.name_abbreviated = 'nc_aca' then spes.estimated_value ELSE 0 end)         as nc_aca_annual
         ,sum(case when spes.name_abbreviated = 'nccip' then spes.estimated_value ELSE 0 end)         as nccip_annual
         ,sum(case when spes.name_abbreviated = 'nc_emergency_medicaid' then spes.estimated_value ELSE 0 end)         as nc_emergency_medicaid_annual
         ,sum(case when spes.name_abbreviated = 'nc_lieap' then spes.estimated_value ELSE 0 end)         as nc_lieap_annual
         ,sum(case when spes.name_abbreviated = 'nc_medicaid' then spes.estimated_value ELSE 0 end)         as nc_medicaid_annual
         ,sum(case when spes.name_abbreviated = 'nc_scca' then spes.estimated_value ELSE 0 end)         as nc_scca_annual
         ,sum(case when spes.name_abbreviated = 'nc_snap' then spes.estimated_value ELSE 0 end)         as nc_snap_annual
         ,sum(case when spes.name_abbreviated = 'nc_tanf' then spes.estimated_value ELSE 0 end)         as nc_tanf_annual
         ,sum(case when spes.name_abbreviated = 'ncwap' then spes.estimated_value ELSE 0 end)         as ncwap_annual
         ,sum(case when spes.name_abbreviated = 'nc_wic' then spes.estimated_value ELSE 0 end)         as nc_wic_annual
         ,sum(case when spes.name_abbreviated = 'il_aabd' then spes.estimated_value ELSE 0 end)         as il_aabd_annual
         ,sum(case when spes.name_abbreviated = 'il_aca' then spes.estimated_value ELSE 0 end)         as il_aca_annual
         ,sum(case when spes.name_abbreviated = 'il_aca_adults' then spes.estimated_value ELSE 0 end)         as il_aca_adults_annual
         ,sum(case when spes.name_abbreviated = 'il_all_kids' then spes.estimated_value ELSE 0 end)         as il_all_kids_annual
         ,sum(case when spes.name_abbreviated = 'il_bap' then spes.estimated_value ELSE 0 end)         as il_bap_annual
         ,sum(case when spes.name_abbreviated = 'il_ctc' then spes.estimated_value ELSE 0 end)         as il_ctc_annual
         ,sum(case when spes.name_abbreviated = 'il_eitc' then spes.estimated_value ELSE 0 end)         as il_eitc_annual
         ,sum(case when spes.name_abbreviated = 'il_family_care' then spes.estimated_value ELSE 0 end)         as il_family_care_annual
         ,sum(case when spes.name_abbreviated = 'il_liheap' then spes.estimated_value ELSE 0 end)         as il_liheap_annual
         ,sum(case when spes.name_abbreviated = 'il_medicaid' then spes.estimated_value ELSE 0 end)         as il_medicaid_annual
         ,sum(case when spes.name_abbreviated = 'il_moms_and_babies' then spes.estimated_value ELSE 0 end)         as il_moms_and_babies_annual
         ,sum(case when spes.name_abbreviated = 'il_nslp' then spes.estimated_value ELSE 0 end)         as il_nslp_annual
         ,sum(case when spes.name_abbreviated = 'il_snap' then spes.estimated_value ELSE 0 end)         as il_snap_annual
         ,sum(case when spes.name_abbreviated = 'il_tanf' then spes.estimated_value ELSE 0 end)         as il_tanf_annual
         ,sum(case when spes.name_abbreviated = 'il_transit_reduced_fare' then spes.estimated_value ELSE 0 end)         as il_transit_reduced_fare_annual
         ,sum(case when spes.name_abbreviated = 'il_wic' then spes.estimated_value ELSE 0 end)         as il_wic_annual
         ,sum(case when spes.name_abbreviated = 'nf' then spes.estimated_value ELSE 0 end)         as nf_annual
         ,sum(case when spes.name_abbreviated = 'nfp' then spes.estimated_value ELSE 0 end)         as nfp_annual
         ,sum(case when spes.name_abbreviated = 'nslp' then spes.estimated_value ELSE 0 end)           as nslp_annual
         ,sum(case when spes.name_abbreviated = 'oap' then spes.estimated_value ELSE 0 end)            as oap_annual
         ,sum(case when spes.name_abbreviated = 'omnisalud' then spes.estimated_value ELSE 0 end)      as omnisalud_annual
         ,sum(case when spes.name_abbreviated = 'pell_grant' then spes.estimated_value ELSE 0 end)      as pell_grant_annual
         ,sum(case when spes.name_abbreviated = 'rag' then spes.estimated_value ELSE 0 end)            as rag_annual
         ,sum(case when spes.name_abbreviated = 'rhc' then spes.estimated_value ELSE 0 end)            as rhc_annual
         ,sum(case when spes.name_abbreviated = 'rtdlive' then spes.estimated_value ELSE 0 end)        as rtdlive_annual
         ,sum(case when spes.name_abbreviated = 'shitc' then spes.estimated_value ELSE 0 end)         as shitc_annual
         ,sum(case when spes.name_abbreviated = 'sunbucks' then spes.estimated_value ELSE 0 end)         as sunbucks_annual
         ,sum(case when spes.name_abbreviated = 'snap' then spes.estimated_value ELSE 0 end)           as snap_annual
         ,sum(case when spes.name_abbreviated = 'ssdi' then spes.estimated_value ELSE 0 end)            as ssdi_annual
         ,sum(case when spes.name_abbreviated = 'ssi' then spes.estimated_value ELSE 0 end)            as ssi_annual
         ,sum(case when spes.name_abbreviated = 'tabor' then spes.estimated_value ELSE 0 end)           as tabor_annual
         ,sum(case when spes.name_abbreviated = 'tanf' then spes.estimated_value ELSE 0 end)           as tanf_annual
         ,sum(case when spes.name_abbreviated = 'trua' then spes.estimated_value ELSE 0 end)           as trua_annual
         ,sum(case when spes.name_abbreviated = 'ubp' then spes.estimated_value ELSE 0 end)            as ubp_annual
         ,sum(case when spes.name_abbreviated = 'upk' then spes.estimated_value ELSE 0 end)            as upk_annual
         ,sum(case when spes.name_abbreviated = 'wic' then spes.estimated_value ELSE 0 end)            as wic_annual
    from screener_programeligibilitysnapshot spes
    where eligible = true
    group by spes.eligibility_snapshot_id
    ),

household_totals_and_percentages as not materialized(
    select
        shou.screen_id
        ,coalesce(sum(case when age<=17 then 1 else 0 end),0) as "<18 (#)"
        ,coalesce(sum(case when (age >17 and age <=24) then 1 else 0 end),0) as "18-24 (#)"
        ,coalesce(sum(case when (age >24 and age<=34) then 1 else 0 end),0) as "25-34 (#)"
        ,coalesce(sum(case when (age >34 and age<=49) then 1 else 0 end),0) as "35-49 (#)"
        ,coalesce(sum(case when (age >49 and age<=64) then 1 else 0 end),0) as "50-64 (#)"
        ,coalesce(sum(case when (age >64 and age<=84) then 1 else 0 end),0) as "65-84 (#)"
        ,coalesce(sum(case when age >84 then 1 else 0 end),0) as ">84 (#)"
        ,coalesce(round(cast((sum(case when age<=17 then 1 else 0 end)/count(*)::float) as numeric),2),0) as "<18 (%)"
        ,coalesce(round(cast((sum(case when (age >17 and age <=24) then 1 else 0 end)/count(*)::float) as numeric),2),0) as "18-24 (%)"
        ,coalesce(round(cast((sum(case when (age >24 and age<=34) then 1 else 0 end)/count(*)::float) as numeric),2),0) as "25-34 (%)"
        ,coalesce(round(cast((sum(case when (age >34 and age<=49) then 1 else 0 end)/count(*)::float) as numeric),2),0) as "35-49 (%)"
        ,coalesce(round(cast((sum(case when (age >49 and age<=64) then 1 else 0 end)/count(*)::float) as numeric),2),0) "50-64 (%)"
        ,coalesce(round(cast((sum(case when (age >64 and age<=84) then 1 else 0 end)/count(*)::float) as numeric),2),0) as "65-84 (%)"
        ,coalesce(round(cast((sum(case when age >84 then 1 else 0 end)/count(*)::float) as numeric),2),0) as ">84 (%)"
    from screener_householdmember shou
    left join screener_screen sscr on shou.screen_id = sscr.id
    group by shou.screen_id
),

base_table_1 as not materialized (
    select
        ss.id
        ,lesbsi.latest_snapshot_id
        ,ss.user_id
        ,ss.external_id
        ,ss.uuid
        ,ss.white_label_id
        ,ss.path
        ,ss.alternate_path
        ,lesbsi.snapshots
        -- # Infer the referral partner(s) that brought the head of household to MFB
        ,case
            when ss.referral_source ~* '^(testOrProspect|stagingTest|test)$' then 'Test'
            when ss.referrer_code is null or trim(ss.referrer_code) = '' then
                case
                    when ss.referral_source is null or trim(ss.referral_source) = '' then 'No Partner'
                    when ss.referral_source is not null and ss.referral_source in (select * from all_referrer_codes) then drc2.partner
                    else 'Other'
                end
            when ss.referrer_code is not null and trim(ss.referrer_code) <> '' then
                case
                    when ss.referral_source is null or trim(ss.referral_source) = '' then drc1.partner
                    when trim(ss.referral_source) = trim(ss.referrer_code) and trim(ss.referral_source) in (select * from all_referrer_codes) then drc1.partner
                    when trim(ss.referral_source) <> trim(ss.referrer_code) then
                        case
                            when trim(ss.referral_source) in (select * from all_referrer_codes) then concat(drc1.partner,', ',drc2.partner)
                            when trim(ss.referrer_code) in (select * from all_referrer_codes) then drc1.partner
                            else 'Other'
                        end
                    else 'Other'
                end
            else 'Other'
        end as partner
        ,ss.is_test
        ,ss.is_test_data
        ,ss.is_verified
        ,ss.completed
        ,ss.start_date as start_timestamp
        ,ss.start_date::date as start_date
        ,to_char(start_date, 'ID') as start_day
        ,to_char(start_date, 'HH24') as start_hour
        ,ss.submission_date as submission_timestamp
        ,ss.submission_date::date as submission_date
        ,to_char(submission_date, 'ID') as submission_day
        ,to_char(submission_date, 'HH24') as submission_hour
        ,ss.agree_to_tos
        ,ss.referrer_code
        ,ss.referral_source
        ,ss.utm_id
        ,ss.utm_source
        ,ss.utm_medium
        ,ss.utm_campaign
        ,ss.utm_content
        ,ss.utm_term
        ,CASE
            WHEN ss.request_language_code='af' THEN 'Afrikaans'
            WHEN ss.request_language_code='ar' THEN 'Arabic'
            WHEN ss.request_language_code='ar-dz' THEN 'Algerian Arabic'
            WHEN ss.request_language_code='ast' THEN 'Asturian'
            WHEN ss.request_language_code='az' THEN 'Azerbaijani'
            WHEN ss.request_language_code='bg' THEN 'Bulgarian'
            WHEN ss.request_language_code='be' THEN 'Belarusian'
            WHEN ss.request_language_code='bn' THEN 'Bengali'
            WHEN ss.request_language_code='br' THEN 'Breton'
            WHEN ss.request_language_code='bs' THEN 'Bosnian'
            WHEN ss.request_language_code='ca' THEN 'Catalan'
            WHEN ss.request_language_code='ckb' THEN 'Central Kurdish (Sorani)'
            WHEN ss.request_language_code='cs' THEN 'Czech'
            WHEN ss.request_language_code='cy' THEN 'Welsh'
            WHEN ss.request_language_code='da' THEN 'Danish'
            WHEN ss.request_language_code='de' THEN 'German'
            WHEN ss.request_language_code='dsb' THEN 'Lower Sorbian'
            WHEN ss.request_language_code='el' THEN 'Greek'
            WHEN ss.request_language_code='en' THEN 'English'
            WHEN ss.request_language_code='en-us' THEN 'English'
            WHEN ss.request_language_code='en-au' THEN 'Australian English'
            WHEN ss.request_language_code='en-gb' THEN 'British English'
            WHEN ss.request_language_code='eo' THEN 'Esperanto'
            WHEN ss.request_language_code='es' THEN 'Spanish'
            WHEN ss.request_language_code='es-ar' THEN 'Argentinian Spanish'
            WHEN ss.request_language_code='es-co' THEN 'Colombian Spanish'
            WHEN ss.request_language_code='es-mx' THEN 'Mexican Spanish'
            WHEN ss.request_language_code='es-ni' THEN 'Nicaraguan Spanish'
            WHEN ss.request_language_code='es-ve' THEN 'Venezuelan Spanish'
            WHEN ss.request_language_code='et' THEN 'Estonian'
            WHEN ss.request_language_code='eu' THEN 'Basque'
            WHEN ss.request_language_code='fa' THEN 'Persian'
            WHEN ss.request_language_code='fi' THEN 'Finnish'
            WHEN ss.request_language_code='fr' THEN 'French'
            WHEN ss.request_language_code='fy' THEN 'Frisian'
            WHEN ss.request_language_code='ga' THEN 'Irish'
            WHEN ss.request_language_code='gd' THEN 'Scottish Gaelic'
            WHEN ss.request_language_code='gl' THEN 'Galician'
            WHEN ss.request_language_code='he' THEN 'Hebrew'
            WHEN ss.request_language_code='hi' THEN 'Hindi'
            WHEN ss.request_language_code='hr' THEN 'Croatian'
            WHEN ss.request_language_code='hsb' THEN 'Upper Sorbian'
            WHEN ss.request_language_code='hu' THEN 'Hungarian'
            WHEN ss.request_language_code='hy' THEN 'Armenian'
            WHEN ss.request_language_code='ia' THEN 'Interlingua'
            WHEN ss.request_language_code='id' THEN 'Indonesian'
            WHEN ss.request_language_code='ig' THEN 'Igbo'
            WHEN ss.request_language_code='io' THEN 'Ido'
            WHEN ss.request_language_code='is' THEN 'Icelandic'
            WHEN ss.request_language_code='it' THEN 'Italian'
            WHEN ss.request_language_code='ja' THEN 'Japanese'
            WHEN ss.request_language_code='ka' THEN 'Georgian'
            WHEN ss.request_language_code='kab' THEN 'Kabyle'
            WHEN ss.request_language_code='kk' THEN 'Kazakh'
            WHEN ss.request_language_code='km' THEN 'Khmer'
            WHEN ss.request_language_code='kn' THEN 'Kannada'
            WHEN ss.request_language_code='ko' THEN 'Korean'
            WHEN ss.request_language_code='ky' THEN 'Kyrgyz'
            WHEN ss.request_language_code='lb' THEN 'Luxembourgish'
            WHEN ss.request_language_code='lt' THEN 'Lithuanian'
            WHEN ss.request_language_code='lv' THEN 'Latvian'
            WHEN ss.request_language_code='mk' THEN 'Macedonian'
            WHEN ss.request_language_code='ml' THEN 'Malayalam'
            WHEN ss.request_language_code='mn' THEN 'Mongolian'
            WHEN ss.request_language_code='mr' THEN 'Marathi'
            WHEN ss.request_language_code='ms' THEN 'Malay'
            WHEN ss.request_language_code='my' THEN 'Burmese'
            WHEN ss.request_language_code='nb' THEN 'Norwegian Bokmål'
            WHEN ss.request_language_code='ne' THEN 'Nepali'
            WHEN ss.request_language_code='nl' THEN 'Dutch'
            WHEN ss.request_language_code='nn' THEN 'Norwegian Nynorsk'
            WHEN ss.request_language_code='os' THEN 'Ossetic'
            WHEN ss.request_language_code='pa' THEN 'Punjabi'
            WHEN ss.request_language_code='pl' THEN 'Polish'
            WHEN ss.request_language_code='pt' THEN 'Portuguese'
            WHEN ss.request_language_code='pt-br' THEN 'Brazilian Portuguese'
            WHEN ss.request_language_code='ro' THEN 'Romanian'
            WHEN ss.request_language_code='ru' THEN 'Russian'
            WHEN ss.request_language_code='sk' THEN 'Slovak'
            WHEN ss.request_language_code='sl' THEN 'Slovenian'
            WHEN ss.request_language_code='sq' THEN 'Albanian'
            WHEN ss.request_language_code='sr' THEN 'Serbian'
            WHEN ss.request_language_code='sr-latn' THEN 'Serbian Latin'
            WHEN ss.request_language_code='sv' THEN 'Swedish'
            WHEN ss.request_language_code='sw' THEN 'Swahili'
            WHEN ss.request_language_code='ta' THEN 'Tamil'
            WHEN ss.request_language_code='te' THEN 'Telugu'
            WHEN ss.request_language_code='tg' THEN 'Tajik'
            WHEN ss.request_language_code='th' THEN 'Thai'
            WHEN ss.request_language_code='tk' THEN 'Turkmen'
            WHEN ss.request_language_code='tr' THEN 'Turkish'
            WHEN ss.request_language_code='tt' THEN 'Tatar'
            WHEN ss.request_language_code='udm' THEN 'Udmurt'
            WHEN ss.request_language_code='ug' THEN 'Uyghur'
            WHEN ss.request_language_code='uk' THEN 'Ukrainian'
            WHEN ss.request_language_code='ur' THEN 'Urdu'
            WHEN ss.request_language_code='uz' THEN 'Uzbek'
            WHEN ss.request_language_code='vi' THEN 'Vietnamese'
            WHEN ss.request_language_code='zh-hans' THEN 'Simplified Chinese'
            WHEN ss.request_language_code='zh-hant' THEN 'Traditional Chinese'
            ELSE '(blank)'
        END as request_language_code
        ,ss.is_13_or_older
        ,ss.last_tax_filing_year
        ,ss.zipcode
        ,ss.county
        ,ss.household_assets
        ,ss.housing_situation
        ,ss.household_size
        ,htap."<18 (#)"
        ,htap."<18 (%)"
        ,htap."18-24 (#)"
        ,htap."18-24 (%)"
        ,htap."25-34 (#)"
        ,htap."25-34 (%)"
        ,htap."35-49 (#)"
        ,htap."35-49 (%)"
        ,htap."50-64 (#)"
        ,htap."50-64 (%)"
        ,htap."65-84 (#)"
        ,htap."65-84 (%)"
        ,htap.">84 (#)"
        ,htap.">84 (%)"
        ,mibsi.monthly_income
        ,mebsi.monthly_expenses

        -- # Health Insurance
        ,ss.has_ssdi
        ,ss.has_chp_hi
        ,ss.has_employer_hi
        ,ss.has_medicaid_hi
        ,ss.has_medicare_hi
        ,ss.has_no_hi
        ,ss.has_private_hi

         -- # Benefits
        ,ss.has_benefits
        ,ss.has_acp
        ,ss.has_andcs
        ,ss.has_ccb
        ,ss.has_ccap
        ,ss.has_ccdf
        ,ss.has_cdhcs
        ,ss.has_chp
        ,ss.has_chs
        ,ss.has_co_andso
        ,ss.has_coctc
        ,ss.has_coeitc
        ,ss.has_cowap
        ,ss.has_cpcr
        ,ss.has_csfp
        ,ss.has_ctc
        ,ss.has_dpp
        ,ss.has_ede
        ,ss.has_eitc
        ,ss.has_erc
        ,ss.has_fatc
        ,ss.has_leap
        ,ss.has_lifeline
        ,ss.has_ma_eaedc
        ,ss.has_ma_macfc
        ,ss.has_ma_maeitc
        ,ss.has_ma_mbta
        ,ss.has_ma_ssp
        ,ss.has_medicaid
        ,ss.has_mydenver
        ,ss.has_nc_lieap
        ,ss.has_nccip
        ,ss.has_ncscca
        ,ss.has_ncwap
        ,ss.has_nfp
        ,ss.has_nslp
        ,ss.has_oap
        ,ss.has_pell_grant
        ,ss.has_rag
        ,ss.has_rtdlive
        ,ss.has_section_8
        ,ss.has_snap
        ,ss.has_ssi
        ,ss.has_sunbucks
        ,ss.has_tanf
        ,ss.has_ubp
        ,ss.has_upk
        ,ss.has_va
        ,ss.has_wic

        -- # Immediate Needs
        ,ss.needs_baby_supplies
        ,ss.needs_child_dev_help
        ,ss.needs_food
        ,ss.needs_funeral_help
        ,ss.needs_housing_help
        ,ss.needs_mental_health_help
        ,ss.needs_family_planning_help
        ,ss.needs_dental_care
        ,ss.needs_job_resources
        ,ss.needs_legal_services
        ,ss.needs_college_savings
        ,ss.needs_veteran_services

-- # Add new benefits here and in the latest program eligibility table above # --
        ,lpe.acp_annual
        ,lpe.andcs_annual
        ,lpe.awd_medicaid_annual
        ,lpe.bca_annual
        ,lpe.cccap_annual
        ,lpe.cdhcs_annual
        ,lpe.cfhc_annual
        ,lpe.chp_annual
        ,lpe.chs_annual
        ,lpe.cocb_annual
        ,lpe.coctc_annual -- tax credit
        ,lpe.coeitc_annual -- tax credit
        ,lpe.co_energy_calculator_bheap_annual
        ,lpe.co_energy_calculator_bhgap_annual
        ,lpe.co_energy_calculator_care_annual
        ,lpe.co_energy_calculator_cngba_annual
        ,lpe.co_energy_calculator_cowap_annual
        ,lpe.co_energy_calculator_cpcr_annual
        ,lpe.co_energy_calculator_ea_annual
        ,lpe.co_energy_calculator_energy_ebt_annual
        ,lpe.co_energy_calculator_eoc_annual
        ,lpe.co_energy_calculator_eoccip_annual
        ,lpe.co_energy_calculator_eocs_annual
        ,lpe.co_energy_calculator_leap_annual
        ,lpe.co_energy_calculator_poipp_annual
        ,lpe.co_energy_calculator_ubp_annual
        ,lpe.co_energy_calculator_xceleap_annual
        ,lpe.co_energy_calculator_xcelgap_annual
        ,lpe.co_medicaid_annual
        ,lpe.co_snap_annual
        ,lpe.co_tanf_annual
        ,lpe.co_wic_annual
        ,lpe._dev_ineligible_annual
        ,lpe.cowap_annual
        ,lpe.cpcr_annual
        ,lpe.ctc_annual
        ,lpe.cwd_medicaid_annual
        ,lpe.dpp_annual
        ,lpe.dptr_annual
        ,lpe.dsr_annual
        ,lpe.dtr_annual
        ,lpe.ede_annual
        ,lpe.eitc_annual -- tax credit
        ,lpe.emergency_medicaid_annual
        ,lpe.erap_annual
        ,lpe.erc_annual
        ,lpe.fatc_annual -- tax credit
        ,lpe.fps_annual
        ,lpe.leap_annual
        ,lpe.lifeline_annual
        ,lpe.lwcr_annual
        ,lpe.ma_aca_annual
        ,lpe.ma_ccdf_annual
        ,lpe.ma_cfc_annual
        ,lpe.ma_eaedc_annual
        ,lpe.ma_maeitc_annual -- tax credit
        ,lpe.ma_mass_health_annual
        ,lpe.ma_mass_health_limited_annual
        ,lpe.ma_mbta_annual
        ,lpe.ma_snap_annual
        ,lpe.ma_ssp_annual
        ,lpe.ma_tafdc_annual
        ,lpe.ma_wic_annual
        ,lpe.medicaid_annual
        ,lpe.medicare_savings_annual
        ,lpe.mydenver_annual
        ,lpe.myspark_annual
        ,lpe.nc_aca_annual
        ,lpe.nccip_annual
        ,lpe.nc_emergency_medicaid_annual
        ,lpe.nc_lieap_annual
        ,lpe.nc_medicaid_annual
        ,lpe.nc_scca_annual
        ,lpe.nc_snap_annual
        ,lpe.nc_tanf_annual
        ,lpe.ncwap_annual
        ,lpe.nc_wic_annual
        ,lpe.il_aabd_annual
        ,lpe.il_aca_annual
        ,lpe.il_aca_adults_annual
        ,lpe.il_all_kids_annual
        ,lpe.il_bap_annual
        ,lpe.il_ctc_annual
        ,lpe.il_eitc_annual
        ,lpe.il_family_care_annual
        ,lpe.il_liheap_annual
        ,lpe.il_medicaid_annual
        ,lpe.il_moms_and_babies_annual
        ,lpe.il_nslp_annual
        ,lpe.il_snap_annual
        ,lpe.il_tanf_annual
        ,lpe.il_transit_reduced_fare_annual
        ,lpe.il_wic_annual
        ,lpe.nf_annual
        ,lpe.nfp_annual
        ,lpe.nslp_annual
        ,lpe.oap_annual
        ,lpe.omnisalud_annual
        ,lpe.pell_grant_annual
        ,lpe.rag_annual
        ,lpe.rhc_annual
        ,lpe.rtdlive_annual
        ,lpe.shitc_annual -- tax credit
        ,lpe.sunbucks_annual
        ,lpe.snap_annual
        ,lpe.ssdi_annual
        ,lpe.ssi_annual
        ,lpe.tabor_annual -- tax credit
        ,lpe.tanf_annual
        ,lpe.trua_annual
        ,lpe.ubp_annual
        ,lpe.wic_annual
        ,secs.is_home_owner
        ,secs.is_renter
        ,secs.electric_provider
        ,secs.gas_provider as gas_heat_provider
        ,secs.electricity_is_disconnected
        ,secs.has_past_due_energy_bills
        ,secs.has_old_car
        ,secs.needs_dryer
        ,secs.needs_hvac
        ,secs.needs_stove
        ,secs.needs_water_heater
    from screener_screen ss
    left join data_referrer_codes drc1 on ss.referrer_code = drc1.referrer_code
    left join data_referrer_codes drc2 on ss.referral_source = drc2.referrer_code
    left join latest_eligibility_snapshot_by_screen_id lesbsi on ss.id=lesbsi.screen_id
    left join latest_program_eligibility lpe on lesbsi.latest_snapshot_id=lpe.eligibility_snapshot_id
    left join monthly_income_by_screener_id mibsi on ss.id=mibsi.screen_id
    left join monthly_expenses_by_screener_id mebsi on ss.id=mebsi.screen_id
    left join household_totals_and_percentages htap on ss.id=htap.screen_id
    left join screener_energycalculatorscreen secs on ss.id = secs.screen_id
    ),


-- # All Bemefits + Tax Credis added
base_table_2 as not materialized (
    select *
        ,coalesce(bt1.acp_annual, 0)
            + coalesce(bt1.andcs_annual, 0)
            + coalesce(bt1.awd_medicaid_annual, 0)
            + coalesce(bt1.bca_annual, 0)
            + coalesce(bt1.cccap_annual, 0)
            + coalesce(bt1.cdhcs_annual, 0)
            + coalesce(bt1.cfhc_annual, 0)
            + coalesce(bt1.chp_annual, 0)
            + coalesce(bt1.chs_annual, 0)
            + coalesce(bt1.cocb_annual, 0)
--             + coalesce(bt1.coctc_annual, 0) -- tax credit
--             + coalesce(bt1.coeitc_annual, 0) -- tax credit
            + coalesce(bt1.co_energy_calculator_bheap_annual, 0)
            + coalesce(bt1.co_energy_calculator_bhgap_annual, 0)
            + coalesce(bt1.co_energy_calculator_care_annual, 0)
            + coalesce(bt1.co_energy_calculator_cngba_annual, 0)
            + coalesce(bt1.co_energy_calculator_cowap_annual, 0)
            + coalesce(bt1.co_energy_calculator_cpcr_annual, 0)
            + coalesce(bt1.co_energy_calculator_ea_annual, 0)
            + coalesce(bt1.co_energy_calculator_energy_ebt_annual, 0)
            + coalesce(bt1.co_energy_calculator_eoc_annual, 0)
            + coalesce(bt1.co_energy_calculator_eoccip_annual, 0)
            + coalesce(bt1.co_energy_calculator_eocs_annual, 0)
            + coalesce(bt1.co_energy_calculator_leap_annual, 0)
            + coalesce(bt1.co_energy_calculator_poipp_annual, 0)
            + coalesce(bt1.co_energy_calculator_ubp_annual, 0)
            + coalesce(bt1.co_energy_calculator_xceleap_annual, 0)
            + coalesce(bt1.co_energy_calculator_xcelgap_annual, 0)
            + coalesce(bt1.co_medicaid_annual, 0)
            + coalesce(bt1.co_snap_annual, 0)
            + coalesce(bt1.co_tanf_annual, 0)
            + coalesce(bt1.co_wic_annual, 0)
            + coalesce(bt1._dev_ineligible_annual, 0)
            + coalesce(bt1.cowap_annual, 0)
            + coalesce(bt1.cpcr_annual, 0)
            + coalesce(bt1.ctc_annual, 0)
            + coalesce(bt1.cwd_medicaid_annual, 0)
            + coalesce(bt1.dpp_annual, 0)
            + coalesce(bt1.dptr_annual, 0)
            + coalesce(bt1.dsr_annual, 0)
            + coalesce(bt1.dtr_annual, 0)
            + coalesce(bt1.ede_annual, 0)
            + coalesce(bt1.emergency_medicaid_annual, 0)
            + coalesce(bt1.erap_annual, 0)
            + coalesce(bt1.erc_annual, 0)
            + coalesce(bt1.fps_annual, 0)
            + coalesce(bt1.leap_annual, 0)
            + coalesce(bt1.lifeline_annual, 0)
            + coalesce(bt1.lwcr_annual, 0)
            + coalesce(bt1.ma_aca_annual, 0)
            + coalesce(bt1.ma_ccdf_annual, 0)
            + coalesce(bt1.ma_cfc_annual, 0)
            + coalesce(bt1.ma_eaedc_annual, 0)
            + coalesce(bt1.ma_mass_health_annual, 0)
            + coalesce(bt1.ma_mass_health_limited_annual, 0)
            + coalesce(bt1.ma_mbta_annual, 0)
            + coalesce(bt1.ma_snap_annual, 0)
            + coalesce(bt1.ma_ssp_annual, 0)
            + coalesce(bt1.ma_tafdc_annual, 0)
            + coalesce(bt1.ma_wic_annual, 0)
            + coalesce(bt1.medicaid_annual, 0)
            + coalesce(bt1.medicare_savings_annual, 0)
            + coalesce(bt1.mydenver_annual, 0)
            + coalesce(bt1.myspark_annual, 0)
            + coalesce(bt1.nc_aca_annual, 0)
            + coalesce(bt1.nccip_annual, 0)
            + coalesce(bt1.nc_emergency_medicaid_annual, 0)
            + coalesce(bt1.nc_lieap_annual, 0)
            + coalesce(bt1.nc_medicaid_annual, 0)
            + coalesce(bt1.nc_scca_annual, 0)
            + coalesce(bt1.nc_snap_annual, 0)
            + coalesce(bt1.nc_tanf_annual, 0)
            + coalesce(bt1.ncwap_annual, 0)
            + coalesce(bt1.nc_wic_annual, 0)
            + coalesce(bt1.il_aabd_annual, 0)
            + coalesce(bt1.il_aca_annual, 0)
            + coalesce(bt1.il_aca_adults_annual, 0)
            + coalesce(bt1.il_all_kids_annual, 0)
            + coalesce(bt1.il_bap_annual, 0)
            + coalesce(bt1.il_family_care_annual, 0)
            + coalesce(bt1.il_liheap_annual, 0)
            + coalesce(bt1.il_medicaid_annual, 0)
            + coalesce(bt1.il_moms_and_babies_annual, 0)
            + coalesce(bt1.il_nslp_annual, 0)
            + coalesce(bt1.il_snap_annual, 0)
            + coalesce(bt1.il_tanf_annual, 0)
            + coalesce(bt1.il_transit_reduced_fare_annual, 0)
            + coalesce(bt1.il_wic_annual, 0)
            + coalesce(bt1.nf_annual, 0)
            + coalesce(bt1.nfp_annual, 0)
            + coalesce(bt1.nslp_annual, 0)
            + coalesce(bt1.oap_annual, 0)
            + coalesce(bt1.omnisalud_annual, 0)
            + coalesce(bt1.pell_grant_annual, 0)
            + coalesce(bt1.rag_annual, 0)
            + coalesce(bt1.rhc_annual, 0)
            + coalesce(bt1.rtdlive_annual, 0)
            + coalesce(bt1.sunbucks_annual, 0)
            + coalesce(bt1.snap_annual, 0)
            + coalesce(bt1.ssdi_annual, 0)
            + coalesce(bt1.ssi_annual, 0)
            + coalesce(bt1.tabor_annual, 0)
            + coalesce(bt1.tanf_annual, 0)
            + coalesce(bt1.trua_annual, 0)
            + coalesce(bt1.ubp_annual, 0)
            + coalesce(bt1.wic_annual, 0) as non_tax_credit_benefits_annual
        , coalesce(bt1.coctc_annual, 0)
            + coalesce(bt1.coeitc_annual, 0)
            + coalesce(bt1.eitc_annual, 0)
            + coalesce(bt1.fatc_annual, 0)
            + coalesce(bt1.il_ctc_annual, 0)
            + coalesce(bt1.il_eitc_annual, 0)
            + coalesce(bt1.ma_maeitc_annual, 0)
            + coalesce(bt1.shitc_annual, 0) as tax_credits_annual
    from base_table_1 bt1
    )


select *
    ,non_tax_credit_benefits_annual/12 as non_tax_credit_benefits_monthly
    ,tax_credits_annual/12 as tax_credits_monthly
from base_table_2
where completed=true
    and is_test=false
    and is_test_data=false
    and partner IS DISTINCT FROM 'Test'
--     and white_label_id=4
order by id