-- # This will create the 'data' materialized view on which the dashboards are based.

-- # Get the latest eligibility snapshot for each screener
CREATE MATERIALIZED VIEW
data AS

WITH snapshots_count AS (
    SELECT
        screen_id,
        COUNT(DISTINCT id) AS snapshots
    FROM screener_eligibilitysnapshot
    GROUP BY screen_id
),

latest_eligibility_snapshot_by_screen_id AS NOT MATERIALIZED (
    SELECT
        sc.screen_id,
        sc.snapshots,
        (
            SELECT id
            FROM screener_eligibilitysnapshot AS sel
            WHERE sel.screen_id = sc.screen_id
            ORDER BY sel.submission_date DESC
            LIMIT 1
        ) AS latest_snapshot_id
    FROM snapshots_count AS sc
    GROUP BY sc.screen_id, sc.snapshots
    ORDER BY sc.screen_id DESC
),

-- # Create a list of all unique referrer codes to reference
all_referrer_codes AS NOT MATERIALIZED (
    SELECT DISTINCT referrer_code
    FROM screener_screen
    WHERE referrer_code IS NOT null AND referrer_code <> ''
),

-- # Monthly Income
monthly_income_by_screener_id AS NOT MATERIALIZED (
    SELECT
        screen_id,
        SUM(CASE
            WHEN frequency = 'yearly' THEN amount / 12
            WHEN frequency = 'monthly' THEN amount
            WHEN frequency = 'weekly' THEN (amount * 52) / 12
            WHEN frequency = 'hourly' THEN (amount * 40 * 52) / 12
            WHEN frequency = 'biweekly' THEN (amount * 26) / 12
            WHEN frequency = 'semimonthly' THEN (amount * 24) / 12
        END) AS monthly_income
    FROM screener_incomestream
    GROUP BY screen_id
    ORDER BY screen_id
),

-- Monthly Expenses
monthly_expenses_by_screener_id AS NOT MATERIALIZED (
    SELECT
        screen_id,
        SUM(CASE
            WHEN frequency = 'yearly' THEN amount / 12
            WHEN frequency = 'monthly' THEN amount
            WHEN frequency = 'weekly' THEN (amount * 52) / 12
            WHEN frequency = 'hourly' THEN (amount * 40 * 52) / 12
            WHEN frequency = 'biweekly' THEN (amount * 26) / 12
            WHEN frequency = 'semimonthly' THEN (amount * 24) / 12
        END) AS monthly_expenses
    FROM screener_expense
    GROUP BY screen_id
    ORDER BY screen_id
),

-- # Program eligibility based on latest eligibility snapshot
latest_program_eligibility AS NOT MATERIALIZED (
    SELECT
        spes.eligibility_snapshot_id,
        -- # Add lines like below for every new benefit in screener_program_eligibilitysnapshot
        SUM(CASE WHEN spes.name_abbreviated = 'acp' THEN spes.estimated_value ELSE 0 END) AS acp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'andcs' THEN spes.estimated_value ELSE 0 END) AS andcs_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'awd_medicaid' THEN spes.estimated_value ELSE 0 END)
            AS awd_medicaid_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'bca' THEN spes.estimated_value ELSE 0 END) AS bca_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'cccap' THEN spes.estimated_value ELSE 0 END) AS cccap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'cdhcs' THEN spes.estimated_value ELSE 0 END) AS cdhcs_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'cfhc' THEN spes.estimated_value ELSE 0 END) AS cfhc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'chp' THEN spes.estimated_value ELSE 0 END) AS chp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'chs' THEN spes.estimated_value ELSE 0 END) AS chs_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'cocb' THEN spes.estimated_value ELSE 0 END) AS cocb_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'coctc' THEN spes.estimated_value ELSE 0 END) AS coctc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'coeitc' THEN spes.estimated_value ELSE 0 END) AS coeitc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_bheap' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_bheap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_bhgap' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_bhgap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_care' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_care_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_cngba' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_cngba_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_cowap' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_cowap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_cpcr' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_cpcr_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_ea' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_ea_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_energy_ebt' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_energy_ebt_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_eoc' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_eoc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_eoccip' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_eoccip_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_eocs' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_eocs_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_leap' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_leap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_poipp' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_poipp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_ubp' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_ubp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_xceleap' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_xceleap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_energy_calculator_xcelgap' THEN spes.estimated_value ELSE 0 END)
            AS co_energy_calculator_xcelgap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_medicaid' THEN spes.estimated_value ELSE 0 END) AS co_medicaid_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_snap' THEN spes.estimated_value ELSE 0 END) AS co_snap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_tanf' THEN spes.estimated_value ELSE 0 END) AS co_tanf_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'co_wic' THEN spes.estimated_value ELSE 0 END) AS co_wic_annual,
        SUM(CASE WHEN spes.name_abbreviated = '_dev_ineligible' THEN spes.estimated_value ELSE 0 END)
            AS _dev_ineligible_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'cowap' THEN spes.estimated_value ELSE 0 END) AS cowap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'cpcr' THEN spes.estimated_value ELSE 0 END) AS cpcr_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ctc' THEN spes.estimated_value ELSE 0 END) AS ctc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'cwd_medicaid' THEN spes.estimated_value ELSE 0 END)
            AS cwd_medicaid_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'dpp' THEN spes.estimated_value ELSE 0 END) AS dpp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'dptr' THEN spes.estimated_value ELSE 0 END) AS dptr_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'dsr' THEN spes.estimated_value ELSE 0 END) AS dsr_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'dtr' THEN spes.estimated_value ELSE 0 END) AS dtr_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ede' THEN spes.estimated_value ELSE 0 END) AS ede_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'eitc' THEN spes.estimated_value ELSE 0 END) AS eitc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'emergency_medicaid' THEN spes.estimated_value ELSE 0 END)
            AS emergency_medicaid_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'erap' THEN spes.estimated_value ELSE 0 END) AS erap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'erc' THEN spes.estimated_value ELSE 0 END) AS erc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'fatc' THEN spes.estimated_value ELSE 0 END) AS fatc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'fps' THEN spes.estimated_value ELSE 0 END) AS fps_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'leap' THEN spes.estimated_value ELSE 0 END) AS leap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'lifeline' THEN spes.estimated_value ELSE 0 END) AS lifeline_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'lwcr' THEN spes.estimated_value ELSE 0 END) AS lwcr_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_aca' THEN spes.estimated_value ELSE 0 END) AS ma_aca_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_ccdf' THEN spes.estimated_value ELSE 0 END) AS ma_ccdf_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_cfc' THEN spes.estimated_value ELSE 0 END) AS ma_cfc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_eaedc' THEN spes.estimated_value ELSE 0 END) AS ma_eaedc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_maeitc' THEN spes.estimated_value ELSE 0 END) AS ma_maeitc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_mass_health' THEN spes.estimated_value ELSE 0 END)
            AS ma_mass_health_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_mass_health_limited' THEN spes.estimated_value ELSE 0 END)
            AS ma_mass_health_limited_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_mbta' THEN spes.estimated_value ELSE 0 END) AS ma_mbta_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_snap' THEN spes.estimated_value ELSE 0 END) AS ma_snap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_ssp' THEN spes.estimated_value ELSE 0 END) AS ma_ssp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_tafdc' THEN spes.estimated_value ELSE 0 END) AS ma_tafdc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ma_wic' THEN spes.estimated_value ELSE 0 END) AS ma_wic_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'medicaid' THEN spes.estimated_value ELSE 0 END) AS medicaid_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'medicare_savings' THEN spes.estimated_value ELSE 0 END)
            AS medicare_savings_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'mydenver' THEN spes.estimated_value ELSE 0 END) AS mydenver_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'myspark' THEN spes.estimated_value ELSE 0 END) AS myspark_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nc_aca' THEN spes.estimated_value ELSE 0 END) AS nc_aca_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nccip' THEN spes.estimated_value ELSE 0 END) AS nccip_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nc_emergency_medicaid' THEN spes.estimated_value ELSE 0 END)
            AS nc_emergency_medicaid_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nc_lieap' THEN spes.estimated_value ELSE 0 END) AS nc_lieap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nc_medicaid' THEN spes.estimated_value ELSE 0 END) AS nc_medicaid_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nc_scca' THEN spes.estimated_value ELSE 0 END) AS nc_scca_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nc_snap' THEN spes.estimated_value ELSE 0 END) AS nc_snap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nc_tanf' THEN spes.estimated_value ELSE 0 END) AS nc_tanf_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ncwap' THEN spes.estimated_value ELSE 0 END) AS ncwap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nc_wic' THEN spes.estimated_value ELSE 0 END) AS nc_wic_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_aabd' THEN spes.estimated_value ELSE 0 END) AS il_aabd_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_aca' THEN spes.estimated_value ELSE 0 END) AS il_aca_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_aca_adults' THEN spes.estimated_value ELSE 0 END)
            AS il_aca_adults_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_all_kids' THEN spes.estimated_value ELSE 0 END) AS il_all_kids_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_bap' THEN spes.estimated_value ELSE 0 END) AS il_bap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_ctc' THEN spes.estimated_value ELSE 0 END) AS il_ctc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_eitc' THEN spes.estimated_value ELSE 0 END) AS il_eitc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_family_care' THEN spes.estimated_value ELSE 0 END)
            AS il_family_care_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_liheap' THEN spes.estimated_value ELSE 0 END) AS il_liheap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_medicaid' THEN spes.estimated_value ELSE 0 END) AS il_medicaid_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_moms_and_babies' THEN spes.estimated_value ELSE 0 END)
            AS il_moms_and_babies_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_nslp' THEN spes.estimated_value ELSE 0 END) AS il_nslp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_snap' THEN spes.estimated_value ELSE 0 END) AS il_snap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_tanf' THEN spes.estimated_value ELSE 0 END) AS il_tanf_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_transit_reduced_fare' THEN spes.estimated_value ELSE 0 END)
            AS il_transit_reduced_fare_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'il_wic' THEN spes.estimated_value ELSE 0 END) AS il_wic_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nf' THEN spes.estimated_value ELSE 0 END) AS nf_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nfp' THEN spes.estimated_value ELSE 0 END) AS nfp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'nslp' THEN spes.estimated_value ELSE 0 END) AS nslp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'oap' THEN spes.estimated_value ELSE 0 END) AS oap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'omnisalud' THEN spes.estimated_value ELSE 0 END) AS omnisalud_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'pell_grant' THEN spes.estimated_value ELSE 0 END) AS pell_grant_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'rag' THEN spes.estimated_value ELSE 0 END) AS rag_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'rhc' THEN spes.estimated_value ELSE 0 END) AS rhc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'rtdlive' THEN spes.estimated_value ELSE 0 END) AS rtdlive_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'shitc' THEN spes.estimated_value ELSE 0 END) AS shitc_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'sunbucks' THEN spes.estimated_value ELSE 0 END) AS sunbucks_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'snap' THEN spes.estimated_value ELSE 0 END) AS snap_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ssdi' THEN spes.estimated_value ELSE 0 END) AS ssdi_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ssi' THEN spes.estimated_value ELSE 0 END) AS ssi_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'tabor' THEN spes.estimated_value ELSE 0 END) AS tabor_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'tanf' THEN spes.estimated_value ELSE 0 END) AS tanf_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'trua' THEN spes.estimated_value ELSE 0 END) AS trua_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'ubp' THEN spes.estimated_value ELSE 0 END) AS ubp_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'upk' THEN spes.estimated_value ELSE 0 END) AS upk_annual,
        SUM(CASE WHEN spes.name_abbreviated = 'wic' THEN spes.estimated_value ELSE 0 END) AS wic_annual
    FROM screener_programeligibilitysnapshot AS spes
    WHERE spes.eligible = true
    GROUP BY spes.eligibility_snapshot_id
),

household_totals_and_percentages AS NOT MATERIALIZED (
    SELECT
        shou.screen_id,
        COALESCE(SUM(CASE WHEN age <= 17 THEN 1 ELSE 0 END), 0) AS "<18 (#)",
        COALESCE(SUM(CASE WHEN (age > 17 AND age <= 24) THEN 1 ELSE 0 END), 0) AS "18-24 (#)",
        COALESCE(SUM(CASE WHEN (age > 24 AND age <= 34) THEN 1 ELSE 0 END), 0) AS "25-34 (#)",
        COALESCE(SUM(CASE WHEN (age > 34 AND age <= 49) THEN 1 ELSE 0 END), 0) AS "35-49 (#)",
        COALESCE(SUM(CASE WHEN (age > 49 AND age <= 64) THEN 1 ELSE 0 END), 0) AS "50-64 (#)",
        COALESCE(SUM(CASE WHEN (age > 64 AND age <= 84) THEN 1 ELSE 0 END), 0) AS "65-84 (#)",
        COALESCE(SUM(CASE WHEN age > 84 THEN 1 ELSE 0 END), 0) AS ">84 (#)",
        COALESCE(
            ROUND(CAST((SUM(CASE WHEN age <= 17 THEN 1 ELSE 0 END) / CAST(COUNT(*) AS float)) AS numeric), 2), 0
        ) AS "<18 (%)",
        COALESCE(
            ROUND(
                CAST((SUM(CASE WHEN (age > 17 AND age <= 24) THEN 1 ELSE 0 END) / CAST(COUNT(*) AS float)) AS numeric),
                2
            ),
            0
        ) AS "18-24 (%)",
        COALESCE(
            ROUND(
                CAST((SUM(CASE WHEN (age > 24 AND age <= 34) THEN 1 ELSE 0 END) / CAST(COUNT(*) AS float)) AS numeric),
                2
            ),
            0
        ) AS "25-34 (%)",
        COALESCE(
            ROUND(
                CAST((SUM(CASE WHEN (age > 34 AND age <= 49) THEN 1 ELSE 0 END) / CAST(COUNT(*) AS float)) AS numeric),
                2
            ),
            0
        ) AS "35-49 (%)",
        COALESCE(
            ROUND(
                CAST((SUM(CASE WHEN (age > 49 AND age <= 64) THEN 1 ELSE 0 END) / CAST(COUNT(*) AS float)) AS numeric),
                2
            ),
            0
        ) AS "50-64 (%)",
        COALESCE(
            ROUND(
                CAST((SUM(CASE WHEN (age > 64 AND age <= 84) THEN 1 ELSE 0 END) / CAST(COUNT(*) AS float)) AS numeric),
                2
            ),
            0
        ) AS "65-84 (%)",
        COALESCE(ROUND(CAST((SUM(CASE WHEN age > 84 THEN 1 ELSE 0 END) / CAST(COUNT(*) AS float)) AS numeric), 2), 0)
            AS ">84 (%)"
    FROM screener_householdmember AS shou
    LEFT JOIN screener_screen AS sscr ON shou.screen_id = sscr.id
    GROUP BY shou.screen_id
),

base_table_1 AS NOT MATERIALIZED (
    SELECT
        ss.id,
        lesbsi.latest_snapshot_id,
        ss.user_id,
        ss.external_id,
        ss.uuid,
        ss.white_label_id,
        ss.path,
        ss.alternate_path,
        lesbsi.snapshots,
        -- # Infer the referral partner(s) that brought the head of household to MFB
        ss.is_test,
        ss.is_test_data,
        ss.is_verified,
        ss.completed,
        ss.start_date AS start_timestamp,
        ss.submission_date AS submission_timestamp,
        ss.agree_to_tos,
        ss.referrer_code,
        ss.referral_source,
        ss.utm_id,
        ss.utm_source,
        ss.utm_medium,
        ss.utm_campaign,
        ss.utm_content,
        ss.utm_term,
        ss.is_13_or_older,
        ss.last_tax_filing_year,
        ss.zipcode,
        ss.county,
        ss.household_assets,
        ss.housing_situation,
        ss.household_size,
        htap."<18 (#)",
        htap."<18 (%)",
        htap."18-24 (#)",
        htap."18-24 (%)",
        htap."25-34 (#)",
        htap."25-34 (%)",
        htap."35-49 (#)",
        htap."35-49 (%)",
        htap."50-64 (#)",
        htap."50-64 (%)",
        htap."65-84 (#)",
        htap."65-84 (%)",
        htap.">84 (#)",
        htap.">84 (%)",
        mibsi.monthly_income,
        mebsi.monthly_expenses,
        ss.has_ssdi,
        ss.has_chp_hi,
        ss.has_employer_hi,
        ss.has_medicaid_hi,
        ss.has_medicare_hi,
        ss.has_no_hi,
        ss.has_private_hi,
        ss.has_benefits,

        -- # Health Insurance
        ss.has_acp,
        ss.has_andcs,
        ss.has_ccb,
        ss.has_ccap,
        ss.has_ccdf,
        ss.has_cdhcs,
        ss.has_chp,

        -- # Benefits
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
        ss.needs_baby_supplies,
        ss.needs_child_dev_help,
        ss.needs_food,
        ss.needs_funeral_help,
        ss.needs_housing_help,
        ss.needs_mental_health_help,
        ss.needs_family_planning_help,
        ss.needs_dental_care,

        -- # Immediate Needs
        ss.needs_job_resources,
        ss.needs_legal_services,
        ss.needs_college_savings,
        ss.needs_veteran_services,
        lpe.acp_annual,
        lpe.andcs_annual,
        lpe.awd_medicaid_annual,
        lpe.bca_annual,
        lpe.cccap_annual,
        lpe.cdhcs_annual,
        lpe.cfhc_annual,
        lpe.chp_annual,

        -- # Add new benefits here and in the latest program eligibility table above # --
        lpe.chs_annual,
        lpe.cocb_annual,
        lpe.coctc_annual,
        lpe.coeitc_annual,
        lpe.co_energy_calculator_bheap_annual,
        lpe.co_energy_calculator_bhgap_annual,
        lpe.co_energy_calculator_care_annual,
        lpe.co_energy_calculator_cngba_annual,
        lpe.co_energy_calculator_cowap_annual,
        lpe.co_energy_calculator_cpcr_annual,
        lpe.co_energy_calculator_ea_annual, -- tax credit
        lpe.co_energy_calculator_energy_ebt_annual, -- tax credit
        lpe.co_energy_calculator_eoc_annual,
        lpe.co_energy_calculator_eoccip_annual,
        lpe.co_energy_calculator_eocs_annual,
        lpe.co_energy_calculator_leap_annual,
        lpe.co_energy_calculator_poipp_annual,
        lpe.co_energy_calculator_ubp_annual,
        lpe.co_energy_calculator_xceleap_annual,
        lpe.co_energy_calculator_xcelgap_annual,
        lpe.co_medicaid_annual,
        lpe.co_snap_annual,
        lpe.co_tanf_annual,
        lpe.co_wic_annual,
        lpe._dev_ineligible_annual,
        lpe.cowap_annual,
        lpe.cpcr_annual,
        lpe.ctc_annual,
        lpe.cwd_medicaid_annual,
        lpe.dpp_annual,
        lpe.dptr_annual,
        lpe.dsr_annual,
        lpe.dtr_annual,
        lpe.ede_annual,
        lpe.eitc_annual,
        lpe.emergency_medicaid_annual,
        lpe.erap_annual,
        lpe.erc_annual,
        lpe.fatc_annual,
        lpe.fps_annual,
        lpe.leap_annual,
        lpe.lifeline_annual,
        lpe.lwcr_annual, -- tax credit
        lpe.ma_aca_annual,
        lpe.ma_ccdf_annual,
        lpe.ma_cfc_annual,
        lpe.ma_eaedc_annual, -- tax credit
        lpe.ma_maeitc_annual,
        lpe.ma_mass_health_annual,
        lpe.ma_mass_health_limited_annual,
        lpe.ma_mbta_annual,
        lpe.ma_snap_annual,
        lpe.ma_ssp_annual,
        lpe.ma_tafdc_annual,
        lpe.ma_wic_annual,
        lpe.medicaid_annual, -- tax credit
        lpe.medicare_savings_annual,
        lpe.mydenver_annual,
        lpe.myspark_annual,
        lpe.nc_aca_annual,
        lpe.nccip_annual,
        lpe.nc_emergency_medicaid_annual,
        lpe.nc_lieap_annual,
        lpe.nc_medicaid_annual,
        lpe.nc_scca_annual,
        lpe.nc_snap_annual,
        lpe.nc_tanf_annual,
        lpe.ncwap_annual,
        lpe.nc_wic_annual,
        lpe.il_aabd_annual,
        lpe.il_aca_annual,
        lpe.il_aca_adults_annual,
        lpe.il_all_kids_annual,
        lpe.il_bap_annual,
        lpe.il_ctc_annual,
        lpe.il_eitc_annual,
        lpe.il_family_care_annual,
        lpe.il_liheap_annual,
        lpe.il_medicaid_annual,
        lpe.il_moms_and_babies_annual,
        lpe.il_nslp_annual,
        lpe.il_snap_annual,
        lpe.il_tanf_annual,
        lpe.il_transit_reduced_fare_annual,
        lpe.il_wic_annual,
        lpe.nf_annual,
        lpe.nfp_annual,
        lpe.nslp_annual,
        lpe.oap_annual,
        lpe.omnisalud_annual,
        lpe.pell_grant_annual,
        lpe.rag_annual,
        lpe.rhc_annual,
        lpe.rtdlive_annual,
        lpe.shitc_annual,
        lpe.sunbucks_annual,
        lpe.snap_annual,
        lpe.ssdi_annual,
        lpe.ssi_annual,
        lpe.tabor_annual,
        lpe.tanf_annual,
        lpe.trua_annual,
        lpe.ubp_annual, -- tax credit
        lpe.wic_annual,
        secs.is_home_owner,
        secs.is_renter,
        secs.electric_provider,
        secs.gas_provider AS gas_heat_provider, -- tax credit
        secs.electricity_is_disconnected,
        secs.has_past_due_energy_bills,
        secs.has_old_car,
        secs.needs_dryer,
        secs.needs_hvac,
        secs.needs_stove,
        secs.needs_water_heater,
        CASE
            WHEN ss.referral_source ~* '^(testOrProspect|stagingTest|test)$' THEN 'Test'
            WHEN ss.referrer_code IS null OR TRIM(ss.referrer_code) = ''
                THEN
                    CASE
                        WHEN ss.referral_source IS null OR TRIM(ss.referral_source) = '' THEN 'No Partner'
                        WHEN
                            ss.referral_source IS NOT null AND ss.referral_source IN (SELECT * FROM all_referrer_codes)
                            THEN drc2.partner
                        ELSE 'Other'
                    END
            WHEN ss.referrer_code IS NOT null OR TRIM(ss.referrer_code) <> ''
                THEN
                    CASE
                        WHEN ss.referral_source IS null OR TRIM(ss.referral_source) = '' THEN drc1.partner
                        WHEN
                            TRIM(ss.referral_source) = TRIM(ss.referrer_code)
                            AND TRIM(ss.referral_source) IN (SELECT * FROM all_referrer_codes)
                            THEN drc1.partner
                        WHEN TRIM(ss.referral_source) <> TRIM(ss.referrer_code)
                            THEN
                                CASE
                                    WHEN
                                        TRIM(ss.referral_source) IN (SELECT * FROM all_referrer_codes)
                                        THEN CONCAT(drc1.partner, ', ', drc2.partner)
                                    WHEN TRIM(ss.referrer_code) IN (SELECT * FROM all_referrer_codes) THEN drc1.partner
                                    ELSE 'Other'
                                END
                        ELSE 'Other'
                    END
            ELSE 'Other'
        END AS partner,
        CAST(ss.start_date AS date) AS start_date,
        TO_CHAR(start_date, 'ID') AS start_day,
        TO_CHAR(start_date, 'HH24') AS start_hour,
        CAST(ss.submission_date AS date) AS submission_date,
        TO_CHAR(submission_date, 'ID') AS submission_day,
        TO_CHAR(submission_date, 'HH24') AS submission_hour,
        CASE
            WHEN ss.request_language_code = 'af' THEN 'Afrikaans'
            WHEN ss.request_language_code = 'ar' THEN 'Arabic'
            WHEN ss.request_language_code = 'ar-dz' THEN 'Algerian Arabic'
            WHEN ss.request_language_code = 'ast' THEN 'Asturian'
            WHEN ss.request_language_code = 'az' THEN 'Azerbaijani'
            WHEN ss.request_language_code = 'bg' THEN 'Bulgarian'
            WHEN ss.request_language_code = 'be' THEN 'Belarusian'
            WHEN ss.request_language_code = 'bn' THEN 'Bengali'
            WHEN ss.request_language_code = 'br' THEN 'Breton'
            WHEN ss.request_language_code = 'bs' THEN 'Bosnian'
            WHEN ss.request_language_code = 'ca' THEN 'Catalan'
            WHEN ss.request_language_code = 'ckb' THEN 'Central Kurdish (Sorani)'
            WHEN ss.request_language_code = 'cs' THEN 'Czech'
            WHEN ss.request_language_code = 'cy' THEN 'Welsh'
            WHEN ss.request_language_code = 'da' THEN 'Danish'
            WHEN ss.request_language_code = 'de' THEN 'German'
            WHEN ss.request_language_code = 'dsb' THEN 'Lower Sorbian'
            WHEN ss.request_language_code = 'el' THEN 'Greek'
            WHEN ss.request_language_code = 'en' THEN 'English'
            WHEN ss.request_language_code = 'en-us' THEN 'English'
            WHEN ss.request_language_code = 'en-au' THEN 'Australian English'
            WHEN ss.request_language_code = 'en-gb' THEN 'British English'
            WHEN ss.request_language_code = 'eo' THEN 'Esperanto'
            WHEN ss.request_language_code = 'es' THEN 'Spanish'
            WHEN ss.request_language_code = 'es-ar' THEN 'Argentinian Spanish'
            WHEN ss.request_language_code = 'es-co' THEN 'Colombian Spanish'
            WHEN ss.request_language_code = 'es-mx' THEN 'Mexican Spanish'
            WHEN ss.request_language_code = 'es-ni' THEN 'Nicaraguan Spanish'
            WHEN ss.request_language_code = 'es-ve' THEN 'Venezuelan Spanish'
            WHEN ss.request_language_code = 'et' THEN 'Estonian'
            WHEN ss.request_language_code = 'eu' THEN 'Basque'
            WHEN ss.request_language_code = 'fa' THEN 'Persian'
            WHEN ss.request_language_code = 'fi' THEN 'Finnish'
            WHEN ss.request_language_code = 'fr' THEN 'French'
            WHEN ss.request_language_code = 'fy' THEN 'Frisian'
            WHEN ss.request_language_code = 'ga' THEN 'Irish'
            WHEN ss.request_language_code = 'gd' THEN 'Scottish Gaelic'
            WHEN ss.request_language_code = 'gl' THEN 'Galician'
            WHEN ss.request_language_code = 'he' THEN 'Hebrew'
            WHEN ss.request_language_code = 'hi' THEN 'Hindi'
            WHEN ss.request_language_code = 'hr' THEN 'Croatian'
            WHEN ss.request_language_code = 'hsb' THEN 'Upper Sorbian'
            WHEN ss.request_language_code = 'hu' THEN 'Hungarian'
            WHEN ss.request_language_code = 'hy' THEN 'Armenian'
            WHEN ss.request_language_code = 'ia' THEN 'Interlingua'
            WHEN ss.request_language_code = 'id' THEN 'Indonesian'
            WHEN ss.request_language_code = 'ig' THEN 'Igbo'
            WHEN ss.request_language_code = 'io' THEN 'Ido'
            WHEN ss.request_language_code = 'is' THEN 'Icelandic'
            WHEN ss.request_language_code = 'it' THEN 'Italian'
            WHEN ss.request_language_code = 'ja' THEN 'Japanese'
            WHEN ss.request_language_code = 'ka' THEN 'Georgian'
            WHEN ss.request_language_code = 'kab' THEN 'Kabyle'
            WHEN ss.request_language_code = 'kk' THEN 'Kazakh'
            WHEN ss.request_language_code = 'km' THEN 'Khmer'
            WHEN ss.request_language_code = 'kn' THEN 'Kannada'
            WHEN ss.request_language_code = 'ko' THEN 'Korean'
            WHEN ss.request_language_code = 'ky' THEN 'Kyrgyz'
            WHEN ss.request_language_code = 'lb' THEN 'Luxembourgish'
            WHEN ss.request_language_code = 'lt' THEN 'Lithuanian'
            WHEN ss.request_language_code = 'lv' THEN 'Latvian'
            WHEN ss.request_language_code = 'mk' THEN 'Macedonian'
            WHEN ss.request_language_code = 'ml' THEN 'Malayalam'
            WHEN ss.request_language_code = 'mn' THEN 'Mongolian'
            WHEN ss.request_language_code = 'mr' THEN 'Marathi'
            WHEN ss.request_language_code = 'ms' THEN 'Malay'
            WHEN ss.request_language_code = 'my' THEN 'Burmese'
            WHEN ss.request_language_code = 'nb' THEN 'Norwegian Bokmål'
            WHEN ss.request_language_code = 'ne' THEN 'Nepali'
            WHEN ss.request_language_code = 'nl' THEN 'Dutch'
            WHEN ss.request_language_code = 'nn' THEN 'Norwegian Nynorsk'
            WHEN ss.request_language_code = 'os' THEN 'Ossetic'
            WHEN ss.request_language_code = 'pa' THEN 'Punjabi'
            WHEN ss.request_language_code = 'pl' THEN 'Polish'
            WHEN ss.request_language_code = 'pt' THEN 'Portuguese'
            WHEN ss.request_language_code = 'pt-br' THEN 'Brazilian Portuguese'
            WHEN ss.request_language_code = 'ro' THEN 'Romanian'
            WHEN ss.request_language_code = 'ru' THEN 'Russian'
            WHEN ss.request_language_code = 'sk' THEN 'Slovak'
            WHEN ss.request_language_code = 'sl' THEN 'Slovenian'
            WHEN ss.request_language_code = 'sq' THEN 'Albanian'
            WHEN ss.request_language_code = 'sr' THEN 'Serbian'
            WHEN ss.request_language_code = 'sr-latn' THEN 'Serbian Latin'
            WHEN ss.request_language_code = 'sv' THEN 'Swedish'
            WHEN ss.request_language_code = 'sw' THEN 'Swahili'
            WHEN ss.request_language_code = 'ta' THEN 'Tamil'
            WHEN ss.request_language_code = 'te' THEN 'Telugu'
            WHEN ss.request_language_code = 'tg' THEN 'Tajik'
            WHEN ss.request_language_code = 'th' THEN 'Thai'
            WHEN ss.request_language_code = 'tk' THEN 'Turkmen'
            WHEN ss.request_language_code = 'tr' THEN 'Turkish'
            WHEN ss.request_language_code = 'tt' THEN 'Tatar'
            WHEN ss.request_language_code = 'udm' THEN 'Udmurt'
            WHEN ss.request_language_code = 'ug' THEN 'Uyghur'
            WHEN ss.request_language_code = 'uk' THEN 'Ukrainian'
            WHEN ss.request_language_code = 'ur' THEN 'Urdu'
            WHEN ss.request_language_code = 'uz' THEN 'Uzbek'
            WHEN ss.request_language_code = 'vi' THEN 'Vietnamese'
            WHEN ss.request_language_code = 'zh-hans' THEN 'Simplified Chinese'
            WHEN ss.request_language_code = 'zh-hant' THEN 'Traditional Chinese'
            ELSE '(blank)'
        END AS request_language_code
    FROM screener_screen AS ss
    LEFT JOIN data_referrer_codes AS drc1 ON ss.referrer_code = drc1.referrer_code
    LEFT JOIN data_referrer_codes AS drc2 ON ss.referral_source = drc2.referrer_code
    LEFT JOIN latest_eligibility_snapshot_by_screen_id AS lesbsi ON ss.id = lesbsi.screen_id
    LEFT JOIN latest_program_eligibility AS lpe ON lesbsi.latest_snapshot_id = lpe.eligibility_snapshot_id
    LEFT JOIN monthly_income_by_screener_id AS mibsi ON ss.id = mibsi.screen_id
    LEFT JOIN monthly_expenses_by_screener_id AS mebsi ON ss.id = mebsi.screen_id
    LEFT JOIN household_totals_and_percentages AS htap ON ss.id = htap.screen_id
    LEFT JOIN screener_energycalculatorscreen AS secs ON ss.id = secs.screen_id
),

-- # All Bemefits + Tax Credis added
base_table_2 AS NOT MATERIALIZED (
    SELECT
        *,
        COALESCE(bt1.acp_annual, 0)
        + COALESCE(bt1.andcs_annual, 0)
        + COALESCE(bt1.awd_medicaid_annual, 0)
        + COALESCE(bt1.bca_annual, 0)
        + COALESCE(bt1.cccap_annual, 0)
        + COALESCE(bt1.cdhcs_annual, 0)
        + COALESCE(bt1.cfhc_annual, 0)
        + COALESCE(bt1.chp_annual, 0)
        + COALESCE(bt1.chs_annual, 0)
        + COALESCE(bt1.cocb_annual, 0)
        --             + coalesce(bt1.coctc_annual, 0) -- tax credit
        --             + coalesce(bt1.coeitc_annual, 0) -- tax credit
        + COALESCE(bt1.co_energy_calculator_bheap_annual, 0)
        + COALESCE(bt1.co_energy_calculator_bhgap_annual, 0)
        + COALESCE(bt1.co_energy_calculator_care_annual, 0)
        + COALESCE(bt1.co_energy_calculator_cngba_annual, 0)
        + COALESCE(bt1.co_energy_calculator_cowap_annual, 0)
        + COALESCE(bt1.co_energy_calculator_cpcr_annual, 0)
        + COALESCE(bt1.co_energy_calculator_ea_annual, 0)
        + COALESCE(bt1.co_energy_calculator_energy_ebt_annual, 0)
        + COALESCE(bt1.co_energy_calculator_eoc_annual, 0)
        + COALESCE(bt1.co_energy_calculator_eoccip_annual, 0)
        + COALESCE(bt1.co_energy_calculator_eocs_annual, 0)
        + COALESCE(bt1.co_energy_calculator_leap_annual, 0)
        + COALESCE(bt1.co_energy_calculator_poipp_annual, 0)
        + COALESCE(bt1.co_energy_calculator_ubp_annual, 0)
        + COALESCE(bt1.co_energy_calculator_xceleap_annual, 0)
        + COALESCE(bt1.co_energy_calculator_xcelgap_annual, 0)
        + COALESCE(bt1.co_medicaid_annual, 0)
        + COALESCE(bt1.co_snap_annual, 0)
        + COALESCE(bt1.co_tanf_annual, 0)
        + COALESCE(bt1.co_wic_annual, 0)
        + COALESCE(bt1._dev_ineligible_annual, 0)
        + COALESCE(bt1.cowap_annual, 0)
        + COALESCE(bt1.cpcr_annual, 0)
        + COALESCE(bt1.ctc_annual, 0)
        + COALESCE(bt1.cwd_medicaid_annual, 0)
        + COALESCE(bt1.dpp_annual, 0)
        + COALESCE(bt1.dptr_annual, 0)
        + COALESCE(bt1.dsr_annual, 0)
        + COALESCE(bt1.dtr_annual, 0)
        + COALESCE(bt1.ede_annual, 0)
        + COALESCE(bt1.emergency_medicaid_annual, 0)
        + COALESCE(bt1.erap_annual, 0)
        + COALESCE(bt1.erc_annual, 0)
        + COALESCE(bt1.fps_annual, 0)
        + COALESCE(bt1.leap_annual, 0)
        + COALESCE(bt1.lifeline_annual, 0)
        + COALESCE(bt1.lwcr_annual, 0)
        + COALESCE(bt1.ma_aca_annual, 0)
        + COALESCE(bt1.ma_ccdf_annual, 0)
        + COALESCE(bt1.ma_cfc_annual, 0)
        + COALESCE(bt1.ma_eaedc_annual, 0)
        + COALESCE(bt1.ma_mass_health_annual, 0)
        + COALESCE(bt1.ma_mass_health_limited_annual, 0)
        + COALESCE(bt1.ma_mbta_annual, 0)
        + COALESCE(bt1.ma_snap_annual, 0)
        + COALESCE(bt1.ma_ssp_annual, 0)
        + COALESCE(bt1.ma_tafdc_annual, 0)
        + COALESCE(bt1.ma_wic_annual, 0)
        + COALESCE(bt1.medicaid_annual, 0)
        + COALESCE(bt1.medicare_savings_annual, 0)
        + COALESCE(bt1.mydenver_annual, 0)
        + COALESCE(bt1.myspark_annual, 0)
        + COALESCE(bt1.nc_aca_annual, 0)
        + COALESCE(bt1.nccip_annual, 0)
        + COALESCE(bt1.nc_emergency_medicaid_annual, 0)
        + COALESCE(bt1.nc_lieap_annual, 0)
        + COALESCE(bt1.nc_medicaid_annual, 0)
        + COALESCE(bt1.nc_scca_annual, 0)
        + COALESCE(bt1.nc_snap_annual, 0)
        + COALESCE(bt1.nc_tanf_annual, 0)
        + COALESCE(bt1.ncwap_annual, 0)
        + COALESCE(bt1.nc_wic_annual, 0)
        + COALESCE(bt1.il_aabd_annual, 0)
        + COALESCE(bt1.il_aca_annual, 0)
        + COALESCE(bt1.il_aca_adults_annual, 0)
        + COALESCE(bt1.il_all_kids_annual, 0)
        + COALESCE(bt1.il_bap_annual, 0)
        + COALESCE(bt1.il_family_care_annual, 0)
        + COALESCE(bt1.il_liheap_annual, 0)
        + COALESCE(bt1.il_medicaid_annual, 0)
        + COALESCE(bt1.il_moms_and_babies_annual, 0)
        + COALESCE(bt1.il_nslp_annual, 0)
        + COALESCE(bt1.il_snap_annual, 0)
        + COALESCE(bt1.il_tanf_annual, 0)
        + COALESCE(bt1.il_transit_reduced_fare_annual, 0)
        + COALESCE(bt1.il_wic_annual, 0)
        + COALESCE(bt1.nf_annual, 0)
        + COALESCE(bt1.nfp_annual, 0)
        + COALESCE(bt1.nslp_annual, 0)
        + COALESCE(bt1.oap_annual, 0)
        + COALESCE(bt1.omnisalud_annual, 0)
        + COALESCE(bt1.pell_grant_annual, 0)
        + COALESCE(bt1.rag_annual, 0)
        + COALESCE(bt1.rhc_annual, 0)
        + COALESCE(bt1.rtdlive_annual, 0)
        + COALESCE(bt1.sunbucks_annual, 0)
        + COALESCE(bt1.snap_annual, 0)
        + COALESCE(bt1.ssdi_annual, 0)
        + COALESCE(bt1.ssi_annual, 0)
        + COALESCE(bt1.tabor_annual, 0)
        + COALESCE(bt1.tanf_annual, 0)
        + COALESCE(bt1.trua_annual, 0)
        + COALESCE(bt1.ubp_annual, 0)
        + COALESCE(bt1.wic_annual, 0) AS non_tax_credit_benefits_annual,
        COALESCE(bt1.coctc_annual, 0)
        + COALESCE(bt1.coeitc_annual, 0)
        + COALESCE(bt1.eitc_annual, 0)
        + COALESCE(bt1.fatc_annual, 0)
        + COALESCE(bt1.il_ctc_annual, 0)
        + COALESCE(bt1.il_eitc_annual, 0)
        + COALESCE(bt1.ma_maeitc_annual, 0)
        + COALESCE(bt1.shitc_annual, 0) AS tax_credits_annual
    FROM base_table_1 AS bt1
)

SELECT
    *,
    non_tax_credit_benefits_annual / 12 AS non_tax_credit_benefits_monthly,
    tax_credits_annual / 12 AS tax_credits_monthly
FROM base_table_2
WHERE
    completed = true
    AND is_test = false
    AND is_test_data = false
--     and white_label_id=4
ORDER BY id
