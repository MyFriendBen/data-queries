{{ config(
    materialized='view',
    description='Complete screener data with eligibility calculations, broken into base tables for clarity'
) }}

with base_table_1 as (
    select
        ss.id,
        les.latest_snapshot_id,
        ss.user_id,
        ss.external_id,
        ss.uuid,
        ss.white_label_id,
        ss.path,
        ss.alternate_path,
        les.snapshots,

        -- Partner inference logic
        case
            when ss.referral_source ~* '^(testOrProspect|stagingTest|test)$' then 'Test'
            when ss.referrer_code is null or trim(ss.referrer_code) = '' then
                case
                    when ss.referral_source is null or trim(ss.referral_source) = '' then 'No Partner'
                    when drc2.referrer_code is not null then drc2.partner
                    else 'Other'
                end
            when ss.referrer_code is not null and trim(ss.referrer_code) <> '' then
                case
                    when ss.referral_source is null or trim(ss.referral_source) = '' then drc1.partner
                    when trim(ss.referral_source) = trim(ss.referrer_code) then coalesce(drc1.partner, 'Other')
                    when trim(ss.referral_source) <> trim(ss.referrer_code) then
                        case
                            when drc2.referrer_code is not null then concat(drc1.partner,', ',drc2.partner)
                            when drc1.referrer_code is not null then drc1.partner
                            else 'Other'
                        end
                    else 'Other'
                end
            else 'Other'
        end as partner,
        
        ss.is_test,
        ss.is_test_data,
        ss.is_verified,
        ss.completed,
        ss.start_date as start_timestamp,
        ss.start_date::date as start_date,
        to_char(ss.start_date, 'ID') as start_day,
        to_char(ss.start_date, 'HH24') as start_hour,
        ss.submission_date as submission_timestamp,
        ss.submission_date::date as submission_date,
        to_char(ss.submission_date, 'ID') as submission_day,
        to_char(ss.submission_date, 'HH24') as submission_hour,
        ss.agree_to_tos,
        ss.referrer_code,
        ss.referral_source,
        ss.utm_id,
        ss.utm_source,
        ss.utm_medium,
        ss.utm_campaign,
        ss.utm_content,
        ss.utm_term,
        
        -- Language code mapping - matches data.sql exactly
        CASE
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
        END as request_language_code,
        
        ss.is_13_or_older,
        ss.last_tax_filing_year,
        ss.zipcode,
        ss.county,
        ss.household_assets,
        ss.housing_situation,
        ss.household_size,
        
        -- Household demographics
        hd."<18 (#)",
        hd."<18 (%)",
        hd."18-24 (#)",
        hd."18-24 (%)",
        hd."25-34 (#)",
        hd."25-34 (%)",
        hd."35-49 (#)",
        hd."35-49 (%)",
        hd."50-64 (#)",
        hd."50-64 (%)",
        hd."65-84 (#)",
        hd."65-84 (%)",
        hd.">84 (#)",
        hd.">84 (%)",
        mi.monthly_income,
        me.monthly_expenses,
        
        -- Health Insurance
        ss.has_ssdi,
        ss.has_chp_hi,
        ss.has_employer_hi,
        ss.has_medicaid_hi,
        ss.has_medicare_hi,
        ss.has_no_hi,
        ss.has_private_hi,
        
        -- Benefits
        ss.has_benefits,
        ss.has_acp,
        ss.has_andcs,
        ss.has_ccb,
        ss.has_ccap,
        ss.has_ccdf,
        ss.has_cdhcs,
        ss.has_chp,
        ss.has_chs,
        ss.has_co_andso,
        ss.has_coctc,
        ss.has_coeitc,
        ss.has_cowap,
        ss.has_cpcr,
        ss.has_csfp,
        ss.has_ctc,
        ss.has_dpp,
        ss.has_ede,
        ss.has_eitc,
        ss.has_erc,
        ss.has_fatc,
        ss.has_leap,
        ss.has_lifeline,
        ss.has_ma_eaedc,
        ss.has_ma_macfc,
        ss.has_ma_maeitc,
        ss.has_ma_mbta,
        ss.has_ma_ssp,
        ss.has_medicaid,
        ss.has_mydenver,
        ss.has_nc_lieap,
        ss.has_nccip,
        ss.has_ncscca,
        ss.has_ncwap,
        ss.has_nfp,
        ss.has_nslp,
        ss.has_oap,
        ss.has_pell_grant,
        ss.has_rag,
        ss.has_rtdlive,
        ss.has_section_8,
        ss.has_snap,
        ss.has_ssi,
        ss.has_sunbucks,
        ss.has_tanf,
        ss.has_ubp,
        ss.has_upk,
        ss.has_va,
        ss.has_wic,
        
        -- Immediate Needs
        ss.needs_baby_supplies,
        ss.needs_child_dev_help,
        ss.needs_food,
        ss.needs_funeral_help,
        ss.needs_housing_help,
        ss.needs_mental_health_help,
        ss.needs_family_planning_help,
        ss.needs_dental_care,
        ss.needs_job_resources,
        ss.needs_legal_services,
        ss.needs_college_savings,
        ss.needs_veteran_services,
        
        -- Program eligibility annual values
        pe.acp_annual,
        pe.andcs_annual,
        pe.awd_medicaid_annual,
        pe.bca_annual,
        pe.ccap_annual,
        pe.cdhcs_annual,
        pe.cfhc_annual,
        pe.chp_annual,
        pe.chs_annual,
        pe.cocb_annual,
        pe.coctc_annual, -- tax credit
        pe.coeitc_annual, -- tax credit
        pe.co_energy_calculator_bheap_annual,
        pe.co_energy_calculator_bhgap_annual,
        pe.co_energy_calculator_care_annual,
        pe.co_energy_calculator_cngba_annual,
        pe.co_energy_calculator_cowap_annual,
        pe.co_energy_calculator_cpcr_annual,
        pe.co_energy_calculator_ea_annual,
        pe.co_energy_calculator_energy_ebt_annual,
        pe.co_energy_calculator_eoc_annual,
        pe.co_energy_calculator_eoccip_annual,
        pe.co_energy_calculator_eocs_annual,
        pe.co_energy_calculator_leap_annual,
        pe.co_energy_calculator_poipp_annual,
        pe.co_energy_calculator_ubp_annual,
        pe.co_energy_calculator_xceleap_annual,
        pe.co_energy_calculator_xcelgap_annual,
        pe.co_medicaid_annual,
        pe.co_snap_annual,
        pe.co_tanf_annual,
        pe.co_wic_annual,
        pe._dev_ineligible_annual,
        pe.cowap_annual,
        pe.cpcr_annual,
        pe.ctc_annual,
        pe.cwd_medicaid_annual,
        pe.dpp_annual,
        pe.dptr_annual,
        pe.dsr_annual,
        pe.dtr_annual,
        pe.ede_annual,
        pe.eitc_annual,
        pe.emergency_medicaid_annual,
        pe.erap_annual,
        pe.erc_annual,
        pe.fatc_annual,
        pe.fps_annual,
        pe.leap_annual,
        pe.lifeline_annual,
        pe.lwcr_annual,
        pe.ma_aca_annual,
        pe.ma_ccdf_annual,
        pe.ma_cfc_annual,
        pe.ma_eaedc_annual,
        pe.ma_maeitc_annual,
        pe.ma_mass_health_annual,
        pe.ma_mass_health_limited_annual,
        pe.ma_mbta_annual,
        pe.ma_snap_annual,
        pe.ma_ssp_annual,
        pe.ma_tafdc_annual,
        pe.ma_wic_annual,
        pe.medicaid_annual,
        pe.medicare_savings_annual,
        pe.mydenver_annual,
        pe.myspark_annual,
        pe.nc_aca_annual,
        pe.nccip_annual,
        pe.nc_emergency_medicaid_annual,
        pe.nc_lieap_annual,
        pe.nc_medicaid_annual,
        pe.nc_scca_annual,
        pe.nc_snap_annual,
        pe.nc_tanf_annual,
        pe.ncwap_annual,
        pe.nc_wic_annual,
        pe.il_aabd_annual,
        pe.il_aca_annual,
        pe.il_aca_adults_annual,
        pe.il_all_kids_annual,
        pe.il_bap_annual,
        pe.il_ctc_annual,
        pe.il_eitc_annual,
        pe.il_family_care_annual,
        pe.il_liheap_annual,
        pe.il_medicaid_annual,
        pe.il_moms_and_babies_annual,
        pe.il_nslp_annual,
        pe.il_snap_annual,
        pe.il_tanf_annual,
        pe.il_transit_reduced_fare_annual,
        pe.il_wic_annual,
        pe.nf_annual,
        pe.nfp_annual,
        pe.nslp_annual,
        pe.oap_annual,
        pe.omnisalud_annual,
        pe.pell_grant_annual,
        pe.rag_annual,
        pe.rhc_annual,
        pe.rtdlive_annual,
        pe.shitc_annual,
        pe.sunbucks_annual,
        pe.snap_annual,
        pe.ssdi_annual,
        pe.ssi_annual,
        pe.tabor_annual,
        pe.tanf_annual,
        pe.trua_annual,
        pe.ubp_annual,
        pe.upk_annual,
        pe.wic_annual,
        
        -- Energy calculator fields
        secs.is_home_owner,
        secs.is_renter,
        secs.electric_provider,
        secs.gas_provider as gas_heat_provider,
        secs.electricity_is_disconnected,
        secs.has_past_due_energy_bills,
        secs.has_old_car,
        secs.needs_dryer,
        secs.needs_hvac,
        secs.needs_stove,
        secs.needs_water_heater
        
    from {{ source('django_apps', 'screener_screen') }} ss
    left join {{ ref('stg_referrer_codes') }} drc1 on ss.referrer_code = drc1.referrer_code
    left join {{ ref('stg_referrer_codes') }} drc2 on ss.referral_source = drc2.referrer_code
    left join {{ ref('stg_latest_eligibility_snapshot') }} les on ss.id = les.screen_id
    left join {{ ref('stg_program_eligibility') }} pe on les.latest_snapshot_id = pe.eligibility_snapshot_id
    left join {{ ref('stg_monthly_income') }} mi on ss.id = mi.screen_id
    left join {{ ref('stg_monthly_expenses') }} me on ss.id = me.screen_id
    left join {{ ref('stg_household_demographics') }} hd on ss.id = hd.screen_id
    left join {{ source('django_apps', 'screener_energycalculatorscreen') }} secs on ss.id = secs.screen_id
),

base_table_2 as (
    select
        *,
        -- Calculate non-tax credit benefits total
        coalesce(acp_annual, 0)
            + coalesce(andcs_annual, 0)
            + coalesce(awd_medicaid_annual, 0)
            + coalesce(bca_annual, 0)
            + coalesce(ccap_annual, 0)
            + coalesce(cdhcs_annual, 0)
            + coalesce(cfhc_annual, 0)
            + coalesce(chp_annual, 0)
            + coalesce(chs_annual, 0)
            + coalesce(cocb_annual, 0)
            -- + coalesce(coctc_annual, 0) -- tax credit
            -- + coalesce(coeitc_annual, 0) -- tax credit
            + coalesce(co_energy_calculator_bheap_annual, 0)
            + coalesce(co_energy_calculator_bhgap_annual, 0)
            + coalesce(co_energy_calculator_care_annual, 0)
            + coalesce(co_energy_calculator_cngba_annual, 0)
            + coalesce(co_energy_calculator_cowap_annual, 0)
            + coalesce(co_energy_calculator_cpcr_annual, 0)
            + coalesce(co_energy_calculator_ea_annual, 0)
            + coalesce(co_energy_calculator_energy_ebt_annual, 0)
            + coalesce(co_energy_calculator_eoc_annual, 0)
            + coalesce(co_energy_calculator_eoccip_annual, 0)
            + coalesce(co_energy_calculator_eocs_annual, 0)
            + coalesce(co_energy_calculator_leap_annual, 0)
            + coalesce(co_energy_calculator_poipp_annual, 0)
            + coalesce(co_energy_calculator_ubp_annual, 0)
            + coalesce(co_energy_calculator_xceleap_annual, 0)
            + coalesce(co_energy_calculator_xcelgap_annual, 0)
            + coalesce(co_medicaid_annual, 0)
            + coalesce(co_snap_annual, 0)
            + coalesce(co_tanf_annual, 0)
            + coalesce(co_wic_annual, 0)
            + coalesce(_dev_ineligible_annual, 0)
            + coalesce(cowap_annual, 0)
            + coalesce(cpcr_annual, 0)
            + coalesce(cwd_medicaid_annual, 0)
            + coalesce(dpp_annual, 0)
            + coalesce(dptr_annual, 0)
            + coalesce(dsr_annual, 0)
            + coalesce(dtr_annual, 0)
            + coalesce(ede_annual, 0)
            + coalesce(emergency_medicaid_annual, 0)
            + coalesce(erap_annual, 0)
            + coalesce(erc_annual, 0)
            + coalesce(fps_annual, 0)
            + coalesce(leap_annual, 0)
            + coalesce(lifeline_annual, 0)
            + coalesce(lwcr_annual, 0)
            + coalesce(ma_aca_annual, 0)
            + coalesce(ma_ccdf_annual, 0)
            + coalesce(ma_cfc_annual, 0)
            + coalesce(ma_eaedc_annual, 0)
            + coalesce(ma_mass_health_annual, 0)
            + coalesce(ma_mass_health_limited_annual, 0)
            + coalesce(ma_mbta_annual, 0)
            + coalesce(ma_snap_annual, 0)
            + coalesce(ma_ssp_annual, 0)
            + coalesce(ma_tafdc_annual, 0)
            + coalesce(ma_wic_annual, 0)
            + coalesce(medicaid_annual, 0)
            + coalesce(medicare_savings_annual, 0)
            + coalesce(mydenver_annual, 0)
            + coalesce(myspark_annual, 0)
            + coalesce(nc_aca_annual, 0)
            + coalesce(nccip_annual, 0)
            + coalesce(nc_emergency_medicaid_annual, 0)
            + coalesce(nc_lieap_annual, 0)
            + coalesce(nc_medicaid_annual, 0)
            + coalesce(nc_scca_annual, 0)
            + coalesce(nc_snap_annual, 0)
            + coalesce(nc_tanf_annual, 0)
            + coalesce(ncwap_annual, 0)
            + coalesce(nc_wic_annual, 0)
            + coalesce(il_aabd_annual, 0)
            + coalesce(il_aca_annual, 0)
            + coalesce(il_aca_adults_annual, 0)
            + coalesce(il_all_kids_annual, 0)
            + coalesce(il_bap_annual, 0)
            + coalesce(il_family_care_annual, 0)
            + coalesce(il_liheap_annual, 0)
            + coalesce(il_medicaid_annual, 0)
            + coalesce(il_moms_and_babies_annual, 0)
            + coalesce(il_nslp_annual, 0)
            + coalesce(il_snap_annual, 0)
            + coalesce(il_tanf_annual, 0)
            + coalesce(il_transit_reduced_fare_annual, 0)
            + coalesce(il_wic_annual, 0)
            + coalesce(nf_annual, 0)
            + coalesce(nfp_annual, 0)
            + coalesce(nslp_annual, 0)
            + coalesce(oap_annual, 0)
            + coalesce(omnisalud_annual, 0)
            + coalesce(pell_grant_annual, 0)
            + coalesce(rag_annual, 0)
            + coalesce(rhc_annual, 0)
            + coalesce(rtdlive_annual, 0)
            + coalesce(sunbucks_annual, 0)
            + coalesce(snap_annual, 0)
            + coalesce(ssdi_annual, 0)
            + coalesce(ssi_annual, 0)
            + coalesce(tabor_annual, 0)
            + coalesce(tanf_annual, 0)
            + coalesce(trua_annual, 0)
            + coalesce(ubp_annual, 0)
            + coalesce(upk_annual, 0)
            + coalesce(wic_annual, 0) as non_tax_credit_benefits_annual,
        
        -- Calculate tax credits total
        coalesce(coctc_annual, 0)
            + coalesce(ctc_annual, 0)
            + coalesce(coeitc_annual, 0)
            + coalesce(eitc_annual, 0)
            + coalesce(fatc_annual, 0)
            + coalesce(il_ctc_annual, 0)
            + coalesce(il_eitc_annual, 0)
            + coalesce(ma_maeitc_annual, 0)
            + coalesce(shitc_annual, 0) as tax_credits_annual
            
    from base_table_1
)

select
    *,
    non_tax_credit_benefits_annual / 12 as non_tax_credit_benefits_monthly,
    tax_credits_annual / 12 as tax_credits_monthly
from base_table_2
where completed = true
    and is_test = false
    and is_test_data = false
    and partner IS DISTINCT FROM 'Test'
    -- and white_label_id=4