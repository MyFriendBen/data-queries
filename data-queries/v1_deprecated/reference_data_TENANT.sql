-- # Reference Data query with CTEs #
-- This is the source view of all reference data in the dashboards.
-- This combines total income and expenses by screener_id
-- All things that are true for all partners should be defined here.
-- Ex. All data should only be of complete screeners then you should put is_complete=true in this query

-- # Drop Previous Version #
-- Uncomment next line to drop the view before replacing it. It's sometimes best to do this if the data type of
-- a column might change, for example.
drop materialized view if exists
    reference_data cascade
--     reference_data_non_partner cascade
--     reference_data_211co cascade
--     reference_data_bia cascade
--     reference_data_brightbytext cascade
--     reference_data_eaglecounty cascade
--     reference_data_cch cascade
--     reference_data_cedp cascade
--     reference_data_dhs cascade
--     reference_data_gac cascade
--     reference_data_jeffcohs cascade
--     reference_data_lgs cascade
--     reference_data_salud cascade
--     reference_data_villageexchange cascade

-- # Create or Replace View #
-- Uncomment next line and ';' at the end of this query to create the view
create materialized view
    -- reference_data as
    reference_data_achd as
--     reference_data_non_partner as
--     reference_data_211co as
--     reference_data_bia as
--     reference_data_brightbytext as
--     reference_data_cch as
--     reference_data_cedp as
--     reference_data_dhs as
--     reference_data_eaglecounty as
--     reference_data_gac as
--     reference_data_jeffcohs as
--     reference_data_lgs as
--     reference_data_salud as
--     reference_data_villageexchange as

--Latest Eligibility Snapshot by Screen ID
with latest_eligibility_snapshot_by_screen_id as not materialized (
    select
        distinct screen_id,
        max(id) over (partition by screen_id order by submission_date desc) as id
    from screener_eligibilitysnapshot
    group by screen_id, id
    order by screen_id asc
    ),

-- Benefits by Eligibility Snapshot ID
benefits_by_eligibility_snapshot_id_2 as not materialized
         (
                select
                 spes.eligibility_snapshot_id,
                 case when name_abbreviated = 'acp' then spes.estimated_value ELSE 0 end            as acp_annual,
                 case when name_abbreviated = 'acp' then spes.estimated_value / 12 end              as acp_monthly,
                 case when name_abbreviated = 'andcs' then spes.estimated_value ELSE 0 end          as andcs_annual,
                 case when name_abbreviated = 'andcs' then spes.estimated_value / 12 ELSE 0 end     as andcs_monthly,
                 case when name_abbreviated = 'awd_medicaid' then spes.estimated_value ELSE 0 end   as awd_medicaid_annual,
                 case when name_abbreviated = 'awd_medicaid' then spes.estimated_value /12 ELSE 0 end   as awd_medicaid_monthly,
                 case when name_abbreviated = 'bca' then spes.estimated_value ELSE 0 end            as bca_annual,
                 case when name_abbreviated = 'bca' then spes.estimated_value /12 ELSE 0 end        as bca_monthly,
                 case when name_abbreviated = 'cccap' then spes.estimated_value ELSE 0 end          as cccap_annual,
                 case when name_abbreviated = 'cccap' then spes.estimated_value / 12 ELSE 0 end     as cccap_monthly,
                 case when name_abbreviated = 'cdhcs' then spes.estimated_value ELSE 0 end          as cdhcs_annual,
                 case when name_abbreviated = 'cdhcs' then spes.estimated_value / 12 ELSE 0 end     as cdhcs_monthly,
                 case when name_abbreviated = 'cfhc' then spes.estimated_value ELSE 0 end           as cfhc_annual,
                 case when name_abbreviated = 'cfhc' then spes.estimated_value / 12 ELSE 0 end      as cfhc_monthly,
                 case when name_abbreviated = 'chp' then spes.estimated_value ELSE 0 end            as chp_annual,
                 case when name_abbreviated = 'chp' then spes.estimated_value / 12 ELSE 0 end       as chp_monthly,
                 case when name_abbreviated = 'chs' then spes.estimated_value ELSE 0 end            as chs_annual,
                 case when name_abbreviated = 'chs' then spes.estimated_value / 12 ELSE 0 end       as chs_monthly,
                 case when name_abbreviated = 'cocb' then spes.estimated_value ELSE 0 end           as cocb_annual,
                 case when name_abbreviated = 'cocb' then spes.estimated_value / 12 ELSE 0 end      as cocb_monthly,
                 case when name_abbreviated = 'coctc' then spes.estimated_value ELSE 0 end          as coctc_annual,
                 case when name_abbreviated = 'coctc' then spes.estimated_value / 12 ELSE 0 end     as coctc_monthly,
                 case when name_abbreviated = 'coeitc' then spes.estimated_value ELSE 0 end         as coeitc_annual,
                 case when name_abbreviated = 'coeitc' then spes.estimated_value / 12 ELSE 0 end    as coeitc_monthly,
                 case when name_abbreviated = 'cowap' then spes.estimated_value ELSE 0 end           as cowap_annual,
                 case when name_abbreviated = 'cowap' then spes.estimated_value / 12 ELSE 0 end      as cowap_monthly,
                 case when name_abbreviated = 'cpcr' then spes.estimated_value ELSE 0 end           as cpcr_annual,
                 case when name_abbreviated = 'cpcr' then spes.estimated_value / 12 ELSE 0 end      as cpcr_monthly,
                 case when name_abbreviated = 'ctc' then spes.estimated_value ELSE 0 end            as ctc_annual,
                 case when name_abbreviated = 'ctc' then spes.estimated_value / 12 ELSE 0 end       as ctc_monthly,
                 case when name_abbreviated = 'cwd_medicaid' then spes.estimated_value ELSE 0 end            as cwd_medicaid_annual,
                 case when name_abbreviated = 'cwd_medicaid' then spes.estimated_value / 12 ELSE 0 end       as cwd_medicaid_monthly,
                 case when name_abbreviated = 'dpp' then spes.estimated_value ELSE 0 end            as dpp_annual,
                 case when name_abbreviated = 'dpp' then spes.estimated_value / 12 ELSE 0 end       as dpp_monthly,
                 case when name_abbreviated = 'ede' then spes.estimated_value ELSE 0 end            as ede_annual,
                 case when name_abbreviated = 'ede' then spes.estimated_value / 12 ELSE 0 end       as ede_monthly,
                 case when name_abbreviated = 'eitc' then spes.estimated_value ELSE 0 end           as eitc_annual,
                 case when name_abbreviated = 'eitc' then spes.estimated_value / 12 ELSE 0 end      as eitc_monthly,
                 case when name_abbreviated = 'emergency_medicaid' then spes.estimated_value ELSE 0 end           as emergency_medicaid_annual,
                 case when name_abbreviated = 'emergency_medicaid' then spes.estimated_value / 12 ELSE 0 end      as emergency_medicaid_monthly,
                 case when name_abbreviated = 'erc' then spes.estimated_value ELSE 0 end            as erc_annual,
                 case when name_abbreviated = 'erc' then spes.estimated_value / 12 ELSE 0 end       as erc_monthly,
                 case when name_abbreviated = 'fps' then spes.estimated_value ELSE 0 end            as fps_annual,
                 case when name_abbreviated = 'fps' then spes.estimated_value / 12 ELSE 0 end       as fps_monthly,
                 case when name_abbreviated = 'leap' then spes.estimated_value ELSE 0 end           as leap_annual,
                 case when name_abbreviated = 'leap' then spes.estimated_value / 12 ELSE 0 end      as leap_monthly,
                 case when name_abbreviated = 'lifeline' then spes.estimated_value ELSE 0 end       as lifeline_annual,
                 case when name_abbreviated = 'lifeline' then spes.estimated_value / 12 ELSE 0 end  as lifeline_monthly,
                 case when name_abbreviated = 'lwcr' then spes.estimated_value ELSE 0 end           as lwcr_annual,
                 case when name_abbreviated = 'lwcr' then spes.estimated_value / 12 ELSE 0 end      as lwcr_monthly,
                 case when name_abbreviated = 'medicaid' then spes.estimated_value ELSE 0 end       as medicaid_annual,
                 case when name_abbreviated = 'medicaid' then spes.estimated_value / 12 ELSE 0 end  as medicaid_monthly,
                 case when name_abbreviated = 'medicare_savings' then spes.estimated_value ELSE 0 end       as medicare_savings_annual,
                 case when name_abbreviated = 'medicare_savings' then spes.estimated_value / 12 ELSE 0 end  as medicare_savings_monthly,
                 case when name_abbreviated = 'mydenver' then spes.estimated_value ELSE 0 end       as mydenver_annual,
                 case when name_abbreviated = 'mydenver' then spes.estimated_value / 12 ELSE 0 end  as mydenver_monthly,
                 case when name_abbreviated = 'myspark' then spes.estimated_value ELSE 0 end       as myspark_annual,
                 case when name_abbreviated = 'myspark' then spes.estimated_value / 12 ELSE 0 end  as myspark_monthly,
                 case when name_abbreviated = 'nslp' then spes.estimated_value ELSE 0 end           as nslp_annual,
                 case when name_abbreviated = 'nslp' then spes.estimated_value / 12 ELSE 0 end      as nslp_monthly,
                 case when name_abbreviated = 'oap' then spes.estimated_value ELSE 0 end            as oap_annual,
                 case when name_abbreviated = 'oap' then spes.estimated_value / 12 ELSE 0 end       as oap_monthly,
                 case when name_abbreviated = 'omnisalud' then spes.estimated_value ELSE 0 end      as omnisalud_annual,
                 case when name_abbreviated = 'omnisalud' then spes.estimated_value / 12 ELSE 0 end as omnisalud_monthly,
                 case when name_abbreviated = 'pell_grant' then spes.estimated_value ELSE 0 end      as pell_grant_annual,
                 case when name_abbreviated = 'pell_grant' then spes.estimated_value / 12 ELSE 0 end as pell_grant_monthly,
                 case when name_abbreviated = 'rag' then spes.estimated_value ELSE 0 end            as rag_annual,
                 case when name_abbreviated = 'rag' then spes.estimated_value / 12 ELSE 0 end       as rag_monthly,
                 case when name_abbreviated = 'rhc' then spes.estimated_value ELSE 0 end            as rhc_annual,
                 case when name_abbreviated = 'rhc' then spes.estimated_value / 12 ELSE 0 end       as rhc_monthly,
                 case when name_abbreviated = 'rtdlive' then spes.estimated_value ELSE 0 end        as rtdlive_annual,
                 case when name_abbreviated = 'rtdlive' then spes.estimated_value / 12 ELSE 0 end   as rtdlive_monthly,
                 case when name_abbreviated = 'snap' then spes.estimated_value ELSE 0 end           as snap_annual,
                 case when name_abbreviated = 'snap' then spes.estimated_value / 12 ELSE 0 end      as snap_monthly,
                 case when name_abbreviated = 'ssdi' then spes.estimated_value ELSE 0 end            as ssdi_annual,
                 case when name_abbreviated = 'ssdi' then spes.estimated_value / 12 ELSE 0 end       as ssdi_monthly,
                 case when name_abbreviated = 'ssi' then spes.estimated_value ELSE 0 end            as ssi_annual,
                 case when name_abbreviated = 'ssi' then spes.estimated_value / 12 ELSE 0 end       as ssi_monthly,
                 case when name_abbreviated = 'tabor' then spes.estimated_value ELSE 0 end           as tabor_annual,
                 case when name_abbreviated = 'tabor' then spes.estimated_value / 12 ELSE 0 end      as tabor_monthly,
                 case when name_abbreviated = 'tanf' then spes.estimated_value ELSE 0 end           as tanf_annual,
                 case when name_abbreviated = 'tanf' then spes.estimated_value / 12 ELSE 0 end      as tanf_monthly,
                 case when name_abbreviated = 'trua' then spes.estimated_value ELSE 0 end           as trua_annual,
                 case when name_abbreviated = 'trua' then spes.estimated_value / 12 ELSE 0 end      as trua_monthly,
                 case when name_abbreviated = 'ubp' then spes.estimated_value ELSE 0 end            as ubp_annual,
                 case when name_abbreviated = 'ubp' then spes.estimated_value / 12 ELSE 0 end       as ubp_monthly,
                 case when name_abbreviated = 'upk' then spes.estimated_value ELSE 0 end            as upk_annual,
                 case when name_abbreviated = 'upk' then spes.estimated_value / 12 ELSE 0 end       as upk_monthly,
                 case when name_abbreviated = 'wic' then spes.estimated_value ELSE 0 end            as wic_annual,
                 case when name_abbreviated = 'wic' then spes.estimated_value / 12 ELSE 0 end       as wic_monthly
          from screener_programeligibilitysnapshot spes
          where eligible = true
          group by eligibility_snapshot_id, name_abbreviated, estimated_value
),

benefits_by_eligibility_snapshot_id as not materialized (
    select
        distinct bbesi2.eligibility_snapshot_id,
        sum(bbesi2.acp_annual) as acp_annual,
        sum(bbesi2.acp_monthly) as acp_monthly,
        sum(bbesi2.andcs_annual) as andcs_annual,
        sum(bbesi2.andcs_monthly) as andcs_monthly,
        sum(bbesi2.awd_medicaid_annual) as awd_medicaid_annual,
        sum(bbesi2.awd_medicaid_monthly) as awd_medicaid_monthly,
        sum(bbesi2.bca_annual) as bca_annual,
        sum(bbesi2.bca_monthly) as bca_monthly,
        sum(bbesi2.cccap_annual) as cccap_annual,
        sum(bbesi2.cccap_monthly) as cccap_monthly,
        sum(bbesi2.cdhcs_annual) as cdhcs_annual,
        sum(bbesi2.cdhcs_monthly) as cdhcs_monthly,
        sum(bbesi2.cfhc_annual) as cfhc_annual,
        sum(bbesi2.cfhc_monthly) as cfhc_monthly,
        sum(bbesi2.chp_annual) as chp_annual,
        sum(bbesi2.chp_monthly) as chp_monthly,
        sum(bbesi2.chs_annual) as chs_annual,
        sum(bbesi2.chs_monthly) as chs_monthly,
        sum(bbesi2.cocb_annual) as cocb_annual,
        sum(bbesi2.cocb_monthly) as cocb_monthly,
        sum(bbesi2.coctc_annual) as coctc_annual,
        sum(bbesi2.coctc_monthly) as coctc_monthly,
        sum(bbesi2.coeitc_annual) as coeitc_annual,
        sum(bbesi2.coeitc_monthly) as coeitc_monthly,
        sum(bbesi2.cowap_annual) as cowap_annual,
        sum(bbesi2.cowap_monthly) as cowap_monthly,
        sum(bbesi2.cpcr_annual) as cpcr_annual,
        sum(bbesi2.cpcr_monthly) as cpcr_monthly,
        sum(bbesi2.ctc_annual) as ctc_annual,
        sum(bbesi2.ctc_monthly) as ctc_monthly,
        sum(bbesi2.cwd_medicaid_annual) as cwd_medicaid_annual,
        sum(bbesi2.cwd_medicaid_monthly) as cwd_medicaid_monthly,
        sum(bbesi2.dpp_annual) as dpp_annual,
        sum(bbesi2.dpp_monthly) as dpp_monthly,
        sum(bbesi2.ede_annual) as ede_annual,
        sum(bbesi2.ede_monthly) as ede_monthly,
        sum(bbesi2.eitc_annual) as eitc_annual,
        sum(bbesi2.eitc_monthly) as eitc_monthly,
        sum(bbesi2.erc_annual) as erc_annual,
        sum(bbesi2.erc_monthly) as erc_monthly,
        sum(bbesi2.emergency_medicaid_annual) as emergency_medicaid_annual,
        sum(bbesi2.emergency_medicaid_monthly) as emergency_medicaid_monthly,
        sum(bbesi2.fps_annual) as fps_annual,
        sum(bbesi2.fps_monthly) as fps_monthly,
        sum(bbesi2.leap_annual) as leap_annual,
        sum(bbesi2.leap_monthly) as leap_monthly,
        sum(bbesi2.lifeline_annual) as lifeline_annual,
        sum(bbesi2.lifeline_monthly) as lifeline_monthly,
        sum(bbesi2.lwcr_annual) as lwcr_annual,
        sum(bbesi2.lwcr_monthly) as lwcr_monthly,
        sum(bbesi2.medicaid_annual) as medicaid_annual,
        sum(bbesi2.medicaid_monthly) as medicaid_monthly,
        sum(bbesi2.medicare_savings_annual) as medicare_savings_annual,
        sum(bbesi2.medicare_savings_monthly) as medicare_savings_monthly,
        sum(bbesi2.mydenver_annual) as mydenver_annual,
        sum(bbesi2.mydenver_monthly) as mydenver_monthly,
        sum(bbesi2.myspark_annual) as myspark_annual,
        sum(bbesi2.myspark_monthly) as myspark_monthly,
        sum(bbesi2.nslp_annual) as nslp_annual,
        sum(bbesi2.nslp_monthly) as nslp_monthly,
        sum(bbesi2.oap_annual) as oap_annual,
        sum(bbesi2.oap_monthly) as oap_monthly,
        sum(bbesi2.omnisalud_annual) as omnisalud_annual,
        sum(bbesi2.omnisalud_monthly) as omnisalud_monthly,
        sum(bbesi2.pell_grant_annual) as pell_grant_annual,
        sum(bbesi2.pell_grant_monthly) as pell_grant_monthly,
        sum(bbesi2.rag_annual) as rag_annual,
        sum(bbesi2.rag_monthly) as rag_monthly,
        sum(bbesi2.rhc_annual) as rhc_annual,
        sum(bbesi2.rhc_monthly) as rhc_monthly,
        sum(bbesi2.rtdlive_annual) as rtdlive_annual,
        sum(bbesi2.rtdlive_monthly) as rtdlive_monthly,
        sum(bbesi2.snap_annual) as snap_annual,
        sum(bbesi2.snap_monthly) as snap_monthly,
        sum(bbesi2.ssdi_annual) as ssdi_annual,
        sum(bbesi2.ssdi_monthly) as ssdi_monthly,
        sum(bbesi2.ssi_annual) as ssi_annual,
        sum(bbesi2.ssi_monthly) as ssi_monthly,
        sum(bbesi2.tabor_annual) as tabor_annual,
        sum(bbesi2.tabor_monthly) as tabor_monthly,
        sum(bbesi2.tanf_annual) as tanf_annual,
        sum(bbesi2.tanf_monthly) as tanf_monthly,
        sum(bbesi2.trua_annual) as trua_annual,
        sum(bbesi2.trua_monthly) as trua_monthly,
        sum(bbesi2.ubp_annual) as ubp_annual,
        sum(bbesi2.ubp_monthly) as ubp_monthly,
        sum(bbesi2.upk_annual) as upk_annual,
        sum(bbesi2.upk_monthly) as upk_monthly,
        sum(bbesi2.wic_annual) as wic_annual,
        sum(bbesi2.wic_monthly) as wic_monthly
    from benefits_by_eligibility_snapshot_id_2 bbesi2
    group by bbesi2.eligibility_snapshot_id
    order by eligibility_snapshot_id asc
),

-- Combines the last 2 CTEs with the previous 1
benefits_by_screen_id as not materialized (
select *
from latest_eligibility_snapshot_by_screen_id lesbsi
left join benefits_by_eligibility_snapshot_id bbesi on lesbsi.id=bbesi.eligibility_snapshot_id
),


-- Monthly income by screener id
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

-- Monthly expenses by screener id
monthly_expenses_by_screener_id as not materialized
    (select
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
    order by screen_id),

-- Valid screeners
-- Complete / Non-test data
screener_screen as not materialized(
       select
       ss.white_label_id,
       ss.completed,
       ss.id,
       ss.start_date,
       CASE
           WHEN ss.start_date<'2023-02-18 00:00:00.000000 +00:00'
           THEN ss.start_date + (10||'minutes')::interval
           ELSE ss.submission_date
       END as submission_date,
       extract(epoch from (ss.submission_date-ss.start_date)) as completion_time,
       ss.zipcode,
       ss.county,
       (case when ss.referral_source = '' is not false then '(blank)' else lower(ss.referral_source) end) as referral_source,
       (case when ss.referrer_code = '' is not false then '(blank)' else lower(ss.referrer_code) end) as referrer_code,
        -- translate ISO language codes to readable Language Names
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
       ss.household_size,
       ss.household_assets,
       (case when ss.housing_situation='' is not false then '(blank)' else ss.housing_situation end) as housing_situation,
       ss.last_email_request_date,
       ss.user_id,
       ss.external_id,
       (case when (ss.last_tax_filing_year='') is not false then '(blank)' else ss.last_tax_filing_year end) as last_tax_filing_year,
       ss.has_acp,
       ss.has_ccb,
       ss.has_cccap,
       ss.has_chp,
       ss.has_coeitc,
       ss.has_ctc,
       ss.has_eitc,
       ss.has_lifeline,
       ss.has_medicaid,
       ss.has_mydenver,
       ss.has_nslp,
       ss.has_rtdlive,
       ss.has_snap,
       ss.has_tanf,
       ss.has_wic,
       ss.has_ssi,
       ss.has_chp_hi,
       ss.has_employer_hi,
       ss.has_medicaid_hi,
       ss.has_no_hi,
       ss.has_private_hi,
       ss.needs_baby_supplies,
       ss.needs_child_dev_help,
       ss.needs_food,
       ss.needs_funeral_help,
       ss.needs_housing_help,
       ss.needs_mental_health_help,
       case when
            (sum(case when ss.needs_baby_supplies=true then 1 else 0 end)
            + sum(case when ss.needs_child_dev_help=true then 1 else 0 end)
            + sum(case when ss.needs_food=true then 1 else 0 end)
            + sum(case when ss.needs_funeral_help=true then 1 else 0 end)
            + sum(case when ss.needs_housing_help=true then 1 else 0 end)
            + sum(case when ss.needs_mental_health_help=true then 1 else 0 end))>0
       then true else false end as immediate_needs,
       ss.has_medicare_hi,
       ss.is_verified,
       ss.needs_family_planning_help,
       ss.has_andcs,
       ss.has_benefits,
       ss.has_cdhcs,
       ss.has_chs,
       ss.has_cpcr,
       ss.has_dpp,
       ss.has_ede,
       ss.has_erc,
       ss.has_leap,
       ss.has_oap,
       ss.has_coctc,
       ss.has_upk,
       (mibsi.monthly_income * 12) as annual_income,
       mibsi.monthly_income as monthly_income,
       mebsi.monthly_expenses as monthly_expenses
    from screener_screen ss
        left join monthly_income_by_screener_id mibsi on ss.id = mibsi.screen_id
        left join monthly_expenses_by_screener_id mebsi on ss.id = mebsi.screen_id
    where
        -- Remove test data
        is_test = false
        -- Include only completed screeners
--         Include both complete and incomplete for LGS
        and completed = true
        -- Remove test data
        and is_test_data = false
        --# Include only those who agree to the terms of service
        and agree_to_tos = true
        --# Add the partner code and other restrictions here for partner views
        --# Non-Partner
--         and (referral_source not in('211co','bia')
--             or referral_source ilike not in('%211co%','%bia%')
--             or referrer_code not in('211co','bia')
--             or referrer_code ilike not in('%211co%','%bia%'))
        --# 211co
--         and (referral_source='211co' or referral_source ilike '%211co%' or referrer_code='211co' or referrer_code ilike '%211co%')
--         and start_date>='2023-09-06 00:00:00.000000 +00:00'
        --# BIA
--         and (referral_source='bia' or referral_source ilike '%bia%' or referrer_code='bia' or referrer_code ilike '%bia%')
--         and start_date>='2023-02-01 00:00:00.000000 +00:00'
        --# BrightByText
--         and (referrer_code in('bright by text','brightbytext','Bright by text','Bright by Text','Bright By Text','Bright texts')
--             or referrer_code ilike any(array['bright by text','brightbytext','Bright by text','Bright by Text','Bright By Text','Bright texts'])
--             or referral_source in('bright by text','brightbytext','Bright by text','Bright by Text','Bright By Text','Bright texts')
--             or referral_source ilike any(array['bright by text','brightbytext','Bright by text','Bright by Text','Bright By Text','Bright texts']))
--         and start_date>='2023-10-05 00:00:00.000000 +00:00'
        --# cch
--         and (referral_source='cch' or referral_source ilike '%cch%' or referrer_code='cch' or referrer_code ilike '%cch%')
--         and start_date>='2023-11-14 00:00:00.000000 +00:00'
--       --# cedp
--         and (referral_source='cedp' or referral_source ilike '%cedp%' or referrer_code='cedp' or referrer_code ilike '%cedp%')
--         and start_date>='2023-09-06 00:00:00.000000 +00:00'
        --# dhs
--         and (referral_source='dhs' or referral_source ilike '%dhs%' or referrer_code='dhs' or referrer_code ilike '%dhs%')
--         and start_date>='2024-09-09 00:00:00.000000 +00:00'
        --# eaglecounty
--         and (referral_source='eaglecounty' or referral_source ilike '%eaglecounty%' or referrer_code='eaglecounty' or referrer_code ilike '%eaglecounty%')
        --# gac
--         and (referral_source='gac' or referral_source ilike '%gac%' or referrer_code='gac' or referrer_code ilike '%gac%')
--         and start_date>='2024-01-01 00:00:00.000000 +00:00'
        --# jeffcohs
--         and (referral_source='jeffcohs' or referral_source ilike '%jeffcohs%' or referrer_code='jeffcohs' or referrer_code ilike '%jeffcohs%')
--         and start_date>='2023-09-01 00:00:00.000000 +00:00'
--         --# lgs
--         and (referral_source='lgs' or referral_source ilike '%lgs%' or referrer_code='lgs' or referrer_code ilike '%lgs%')
--         and submission_date>='2024-01-30 00:00:00.000000 +00:00'
        --# salud
--         and (referral_source='salud' or referral_source ilike '%salud%' or referrer_code='salud' or referrer_code ilike '%salud%')
--         and submission_date>='2024-01-30 00:00:00.000000 +00:00'
--          # villageexchange
--         and (referral_source='villageexchange' or referral_source ilike '%villageexchange%' or referrer_code='villageexchange' or referrer_code ilike '%villageexchange%')
--         and start_date>='2023-09-15 00:00:00.000000 +00:00'

    group by ss.id, ss.submission_date, ss.zipcode, ss.county, ss.referral_source,
        ss.referrer_code, ss.request_language_code, ss.household_size,
        ss.household_assets, ss.housing_situation, ss.last_email_request_date,
        ss.user_id, ss.start_date, ss.external_id, ss.last_tax_filing_year,
        ss.has_acp, ss.has_ccb, ss.has_cccap, ss.has_chp, ss.has_coeitc,
        ss.has_ctc, ss.has_eitc, ss.has_lifeline, ss.has_medicaid,
        ss.has_mydenver, ss.has_nslp, ss.has_rtdlive, ss.has_snap, ss.has_tanf,
        ss.has_wic, ss.has_ssi, ss.has_chp_hi, ss.has_employer_hi,
        ss.has_medicaid_hi, ss.has_no_hi, ss.has_private_hi,
        ss.needs_baby_supplies, ss.needs_child_dev_help, ss.needs_food,
        ss.needs_funeral_help, ss.needs_housing_help, ss.needs_mental_health_help,
        ss.has_medicare_hi, ss.is_verified, ss.needs_family_planning_help,
        ss.has_andcs, ss.has_benefits, ss.has_cdhcs, ss.has_chs, ss.has_cpcr,
        ss.has_dpp, ss.has_ede, ss.has_erc, ss.has_leap, ss.has_oap, ss.has_coctc,
        ss.has_upk, mibsi.monthly_income, mebsi.monthly_expenses
    order by ss.id asc),

-- #Special LGS status
lgs_added_new_info as not materialized(
select
    id,
    case when completed=true
        and (county is not null
            or has_acp=true
            or has_cccap=true
            or has_chp=true
            or has_coeitc=true
            or has_ctc=true
            or has_eitc=true
            or has_lifeline=true
            or has_medicaid=true
            or has_mydenver=true
            or has_nslp=true
            or has_rtdlive=true
            or has_snap=true
            or has_tanf=true
            or has_wic=true
            or has_ssi=true
            or needs_baby_supplies=true
            or needs_child_dev_help=true
            or needs_food=true
            or needs_funeral_help=true
            or needs_housing_help=true
            or needs_mental_health_help=true
            or needs_family_planning_help=true
            or has_andcs=true
            or has_benefits != 'preferNotToAnswer'
            or has_cdhcs=true
            or has_chs=true
            or has_cpcr=true
            or has_dpp=true
            or has_ede=true
            or has_erc=true
            or has_leap=true
            or has_oap=true
            or has_coctc=true
            or has_upk=true
            or mebsi.monthly_expenses>0)
        then true else false end as added_information
    from screener_screen ss
    left join monthly_expenses_by_screener_id mebsi on ss.id=mebsi.screen_id
    where (referrer_code='lgs' or referral_source='lgs')
    and submission_date>='2024-01-30 00:00:00.000000 +00:00'
),

base_table as not materialized (
    select distinct
    -- # added_information is an lgs specific boolean
    --        added_information,
    ss2.white_label_id,
    ss2.completed,
    ss2.id,
    start_date,
    submission_date,
    completion_time,
    zipcode,
    county,
    referral_source,
    referrer_code,
    request_language_code,
    household_size,
    household_assets,
    housing_situation,
    last_email_request_date,
    user_id,
    external_id,
    last_tax_filing_year,
    has_acp,
    has_ccb,
    has_cccap,
    has_chp,
    has_coeitc,
    has_ctc,
    has_eitc,
    has_lifeline,
    has_medicaid,
    has_mydenver,
    has_nslp,
    has_rtdlive,
    has_snap,
    has_tanf,
    has_wic,
    has_ssi,
    has_chp_hi,
    has_employer_hi,
    has_medicaid_hi,
    has_no_hi,
    has_private_hi,
    needs_baby_supplies,
    needs_child_dev_help,
    needs_food,
    needs_funeral_help,
    needs_housing_help,
    needs_mental_health_help,
    immediate_needs,
    has_medicare_hi,
    is_verified,
    needs_family_planning_help,
    has_andcs,
    has_benefits,
    has_cdhcs,
    has_chs,
    has_cpcr,
    has_dpp,
    has_ede,
    has_erc,
    has_leap,
    has_oap,
    has_coctc,
    has_upk,
    coalesce(monthly_income, 0)                                                                      as monthly_income,
    coalesce(monthly_expenses, 0)                                                                    as monthly_expenses,
    coalesce(acp_annual, 0)                                                                          as acp_annual,
    coalesce(acp_monthly, 0)                                                                         as acp_monthly,
    coalesce(andcs_annual, 0)                                                                        as andcs_annual,
    coalesce(andcs_monthly, 0)                                                                       as andcs_monthly,
    coalesce(awd_medicaid_annual, 0)                                                                 as awd_medicaid_annual,
    coalesce(awd_medicaid_monthly, 0)                                                                as awd_medicaid_monthly,
    coalesce(bca_annual, 0)                                                                          as bca_annual,
    coalesce(bca_monthly, 0)                                                                         as bca_monthly,
    coalesce(cccap_annual, 0)                                                                        as cccap_annual,
    coalesce(cccap_monthly, 0)                                                                       as cccap_monthly,
    coalesce(cdhcs_annual, 0)                                                                        as cdhcs_annual,
    coalesce(cdhcs_monthly, 0)                                                                       as cdhcs_monthly,
    coalesce(cfhc_annual, 0)                                                                         as cfhc_annual,
    coalesce(cfhc_monthly, 0)                                                                        as cfhc_monthly,
    coalesce(chp_annual, 0)                                                                          as chp_annual,
    coalesce(chp_monthly, 0)                                                                         as chp_monthly,
    coalesce(chs_annual, 0)                                                                          as chs_annual,
    coalesce(chs_monthly, 0)                                                                         as chs_monthly,
    coalesce(cocb_annual, 0)                                                                         as cocb_annual,
    coalesce(cocb_monthly, 0)                                                                        as cocb_monthly,
    coalesce(coctc_annual, 0)                                                                        as coctc_annual,
    coalesce(coctc_monthly, 0)                                                                       as coctc_monthly,
    coalesce(coeitc_annual, 0)                                                                       as coeitc_annual,
    coalesce(coeitc_monthly, 0)                                                                      as coeitc_monthly,
    coalesce(cowap_annual, 0)                                                                        as cowap_annual,
    coalesce(cowap_monthly, 0)                                                                       as cowap_monthly,
    coalesce(cpcr_annual, 0)                                                                         as cpcr_annual,
    coalesce(cpcr_monthly, 0)                                                                        as cpcr_monthly,
    coalesce(ctc_annual, 0)                                                                          as ctc_annual,
    coalesce(ctc_monthly, 0)                                                                         as ctc_monthly,
    coalesce(cwd_medicaid_annual, 0)                                                                 as cwd_medicaid_annual,
    coalesce(cwd_medicaid_monthly, 0)                                                                as cwd_medicaid_monthly,
    coalesce(dpp_annual, 0)                                                                          as dpp_annual,
    coalesce(dpp_monthly, 0)                                                                         as dpp_monthly,
    coalesce(ede_annual, 0)                                                                          as ede_annual,
    coalesce(ede_monthly, 0)                                                                         as ede_monthly,
    coalesce(eitc_annual, 0)                                                                         as eitc_annual,
    coalesce(eitc_monthly, 0)                                                                        as eitc_monthly,
    coalesce(emergency_medicaid_monthly, 0)                                                          as emergency_medicaid_monthly,
    coalesce(emergency_medicaid_annual, 0)                                                           as emergency_medicaid_annual,
    coalesce(erc_annual, 0)                                                                          as erc_annual,
    coalesce(erc_monthly, 0)                                                                         as erc_monthly,
    coalesce(fps_annual, 0)                                                                          as fps_annual,
    coalesce(fps_monthly, 0)                                                                         as fps_monthly,
    coalesce(leap_annual, 0)                                                                         as leap_annual,
    coalesce(leap_monthly, 0)                                                                        as leap_monthly,
    coalesce(lifeline_annual, 0)                                                                     as lifeline_annual,
    coalesce(lifeline_monthly, 0)                                                                    as lifeline_monthly,
    coalesce(lwcr_annual, 0)                                                                         as lwcr_annual,
    coalesce(lwcr_monthly, 0)                                                                        as lwcr_monthly,
    coalesce(medicaid_annual, 0)                                                                     as medicaid_annual,
    coalesce(medicaid_monthly, 0)                                                                    as medicaid_monthly,
    coalesce(medicare_savings_annual, 0)                                                             as medicare_savings_annual,
    coalesce(medicare_savings_monthly, 0)                                                            as medicare_savings_monthly,
    coalesce(mydenver_annual, 0)                                                                     as mydenver_annual,
    coalesce(mydenver_monthly, 0)                                                                    as mydenver_monthly,
    coalesce(myspark_annual, 0)                                                                      as myspark_annual,
    coalesce(myspark_monthly, 0)                                                                     as myspark_monthly,
    coalesce(nslp_annual, 0)                                                                         as nslp_annual,
    coalesce(nslp_monthly, 0)                                                                        as nslp_monthly,
    coalesce(oap_annual, 0)                                                                          as oap_annual,
    coalesce(oap_monthly, 0)                                                                         as oap_monthly,
    coalesce(omnisalud_annual, 0)                                                                    as omnisalud_annual,
    coalesce(omnisalud_monthly, 0)                                                                   as omnisalud_monthly,
    coalesce(pell_grant_annual, 0)                                                                   as pell_grant_annual,
    coalesce(pell_grant_monthly, 0)                                                                  as pell_grant_monthly,
    coalesce(rag_annual, 0)                                                                          as rag_annual,
    coalesce(rag_monthly, 0)                                                                         as rag_monthly,
    coalesce(rhc_annual, 0)                                                                          as rhc_annual,
    coalesce(rhc_monthly, 0)                                                                         as rhc_monthly,
    coalesce(rtdlive_annual, 0)                                                                      as rtdlive_annual,
    coalesce(rtdlive_monthly, 0)                                                                     as rtdlive_monthly,
    coalesce(snap_annual, 0)                                                                         as snap_annual,
    coalesce(snap_monthly, 0)                                                                        as snap_monthly,
    coalesce(ssdi_annual, 0)                                                                         as ssdi_annual,
    coalesce(ssdi_monthly, 0)                                                                        as ssdi_monthly,
    coalesce(ssi_annual, 0)                                                                          as ssi_annual,
    coalesce(ssi_monthly, 0)                                                                         as ssi_monthly,
    coalesce(tabor_annual, 0)                                                                        as tabor_annual,
    coalesce(tabor_monthly, 0)                                                                       as tabor_monthly,
    coalesce(tanf_annual, 0)                                                                         as tanf_annual,
    coalesce(tanf_monthly, 0)                                                                        as tanf_monthly,
    coalesce(trua_annual, 0)                                                                         as trua_annual,
    coalesce(trua_monthly, 0)                                                                        as trua_monthly,
    coalesce(ubp_annual, 0)                                                                          as ubp_annual,
    coalesce(ubp_monthly, 0)                                                                         as ubp_monthly,
    coalesce(upk_annual, 0)                                                                          as upk_annual,
    coalesce(upk_monthly, 0)                                                                         as upk_monthly,
    coalesce(wic_annual, 0)                                                                          as wic_annual,
    coalesce(wic_monthly, 0)                                                                         as wic_monthly,
    coalesce(annual_income, 0)                                                                       as annual_income,
    coalesce(
                coalesce(acp_annual, 0) + coalesce(andcs_annual, 0) + coalesce(awd_medicaid_annual, 0) +
                coalesce(bca_annual, 0)
                + coalesce(cccap_annual, 0) + coalesce(cdhcs_annual, 0) + coalesce(cfhc_annual, 0) + coalesce(chp_annual, 0)
                + coalesce(chs_annual, 0) + coalesce(cocb_annual, 0) + coalesce(coctc_annual, 0)
    -- Do not include tax credits for LGS
                + coalesce(coeitc_annual, 0)
                + coalesce(cowap_annual, 0) + coalesce(cpcr_annual, 0) + coalesce(ctc_annual, 0) +
                coalesce(cwd_medicaid_annual, 0)
                + coalesce(dpp_annual, 0) + coalesce(ede_annual, 0)
    -- Do not include tax credits for LGS
                + coalesce(eitc_annual, 0)
                + coalesce(emergency_medicaid_annual, 0) + coalesce(erc_annual, 0) + coalesce(fps_annual, 0)
                + coalesce(leap_annual, 0) + coalesce(lifeline_annual, 0) + coalesce(lwcr_annual, 0) +
                coalesce(medicaid_annual, 0)
                + coalesce(medicare_savings_annual, 0) + coalesce(mydenver_annual, 0) + coalesce(myspark_annual, 0)
                + coalesce(nslp_annual, 0) + coalesce(oap_annual, 0) + coalesce(omnisalud_annual, 0) +
                coalesce(pell_grant_annual, 0)
                + coalesce(rhc_annual, 0) + coalesce(rtdlive_annual, 0) + coalesce(snap_annual, 0) +
                coalesce(ssdi_annual, 0)
                + coalesce(ssi_annual, 0) + coalesce(tabor_annual, 0) + coalesce(tanf_annual, 0) + coalesce(trua_annual, 0)
                + coalesce(ubp_annual, 0) + coalesce(upk_annual, 0) + coalesce(wic_annual, 0), 0)    as benefits_annual,
    coalesce(
                coalesce(acp_monthly, 0) + coalesce(andcs_monthly, 0) + coalesce(awd_medicaid_monthly, 0) +
                coalesce(bca_monthly, 0)
                + coalesce(cccap_monthly, 0) + coalesce(cdhcs_monthly, 0) + coalesce(cfhc_monthly, 0) +
                coalesce(chp_monthly, 0)
                + coalesce(chs_monthly, 0) + coalesce(cocb_monthly, 0) + coalesce(coctc_monthly, 0)
    -- Do not include tax credits for LGS
                + coalesce(coeitc_monthly, 0)
                + coalesce(cowap_monthly, 0) + coalesce(cpcr_monthly, 0) + coalesce(ctc_monthly, 0) +
                coalesce(cwd_medicaid_monthly, 0)
                + coalesce(dpp_monthly, 0) + coalesce(ede_monthly, 0)
    -- Do not include tax credits for LGS
                + coalesce(eitc_monthly, 0)
                + coalesce(emergency_medicaid_monthly, 0) + coalesce(erc_monthly, 0) + coalesce(fps_monthly, 0)
                + coalesce(leap_monthly, 0) + coalesce(lifeline_monthly, 0) + coalesce(lwcr_monthly, 0) +
                coalesce(medicaid_monthly, 0)
                + coalesce(medicare_savings_monthly, 0) + coalesce(mydenver_monthly, 0) + coalesce(myspark_monthly, 0)
                + coalesce(nslp_monthly, 0) + coalesce(oap_monthly, 0) + coalesce(omnisalud_monthly, 0) +
                coalesce(pell_grant_monthly, 0)
                + coalesce(rhc_monthly, 0) + coalesce(rtdlive_monthly, 0) + coalesce(snap_monthly, 0) +
                coalesce(ssdi_monthly, 0)
                + coalesce(ssi_monthly, 0) + coalesce(tabor_monthly, 0) + coalesce(tanf_monthly, 0) +
                coalesce(trua_monthly, 0)
                + coalesce(ubp_monthly, 0) + coalesce(upk_monthly, 0) + coalesce(wic_monthly, 0), 0) as benefits_monthly
    -- This was needed to identify LGS users
    --         ,ss2.external_id
               from screener_screen ss2
                        left join benefits_by_screen_id bbsi on ss2.id = bbsi.screen_id
                        left join lgs_added_new_info lani on ss2.id = lani.id
               order by ss2.id asc),

unique_referrer_codes as (
    select distinct referrer_code
    from screener_screen
        ),

base_table_2 as not materialized(
    select
        *
--         ,case when (bt.referrer_code='(blank)' or bt.referrer_code is null) and (bt.referral_source='(blank)' or bt.referral_source is null) then null
--             when (bt.referrer_code='(blank)' or bt.referrer_code is null) and (bt.referral_source is not null or referral_source<>'(blank)') then bt.referral_source
--             when bt.referrer_code is not null and (bt.referral_source='(blank)' or bt.referral_source is null) then bt.referrer_code
--             when bt.referral_source in(bt.referrer_code) and bt.referral_source is not null and bt.referral_source<>'blank' and bt.referrer_code is not null
--                 and bt.referrer_code<>'blank' then concat(bt.referrer_code, ', ', bt.referral_source)
--             else 'No Partner'
--         end as partners
        ,coeitc_annual + coctc_annual + ctc_annual + tabor_annual + eitc_annual + coeitc_annual as tax_credits_annual
    from base_table bt
--     join unique_referrer_codes urc on bt.referrer_code=urc.referrer_code
--     where bt.referral_source in(urc.referrer_code)

)

select
    *
    ,benefits_annual - tax_credits_annual as non_tax_credits_annual
from base_table_2
