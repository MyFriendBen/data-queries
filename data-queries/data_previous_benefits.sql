-- # This query will create a previous_benefits table
-- This table is used as a source for Looker Studio dashboards.
create materialized view
    data_previous_benefits as

with base as (
    select
        white_label_id
        ,partner
        ,sum(case when has_acp = true then 1 else 0 end)                     as acp
        ,sum(case when has_andcs = true then 1 else 0 end)                     as andcs
        ,sum(case when has_ccb = true then 1 else 0 end)                     as ccb
        ,sum(case when has_cccap = true then 1 else 0 end)                     as cccap
        ,sum(case when has_ccdf = true then 1 else 0 end)                     as ccdf
        ,sum(case when has_cdhcs = true then 1 else 0 end)                     as cdhcs
        ,sum(case when has_chp = true then 1 else 0 end)                     as chp
        ,sum(case when has_chs = true then 1 else 0 end)                     as chs
        ,sum(case when has_co_andso = true then 1 else 0 end)                     as co_andso
        ,sum(case when has_coctc = true then 1 else 0 end)                     as coctc
        ,sum(case when has_coeitc = true then 1 else 0 end)                     as coeitc
        ,sum(case when has_cowap = true then 1 else 0 end)                     as cowap
        ,sum(case when has_cpcr = true then 1 else 0 end)                     as cpcr
        ,sum(case when has_csfp = true then 1 else 0 end)                     as csfp
        ,sum(case when has_ctc = true then 1 else 0 end)                     as ctc
        ,sum(case when has_dpp = true then 1 else 0 end)                     as dpp
        ,sum(case when has_ede = true then 1 else 0 end)                     as ede
        ,sum(case when has_eitc = true then 1 else 0 end)                     as eitc
        ,sum(case when has_erc = true then 1 else 0 end)                     as erc
        ,sum(case when has_fatc = true then 1 else 0 end)                     as fatc
        ,sum(case when has_leap = true then 1 else 0 end)                     as leap
        ,sum(case when has_lifeline = true then 1 else 0 end)                     as lifeline
        ,sum(case when has_ma_eaedc = true then 1 else 0 end)                     as ma_eaedc
        ,sum(case when has_ma_macfc = true then 1 else 0 end)                     as ma_macfc
        ,sum(case when has_ma_maeitc = true then 1 else 0 end)                     as ma_maeitc
        ,sum(case when has_ma_mbta = true then 1 else 0 end)                     as ma_mbta
        ,sum(case when has_ma_ssp = true then 1 else 0 end)                     as ma_ssp
        ,sum(case when has_medicaid = true then 1 else 0 end)                     as medicaid
        ,sum(case when has_mydenver = true then 1 else 0 end)                     as mydenver
        ,sum(case when has_nc_lieap = true then 1 else 0 end)                     as nc_lieap
        ,sum(case when has_nccip = true then 1 else 0 end)                     as nccip
        ,sum(case when has_ncscca = true then 1 else 0 end)                     as ncscca
        ,sum(case when has_ncwap = true then 1 else 0 end)                     as ncwap
        ,sum(case when has_nfp = true then 1 else 0 end)                     as nfp
        ,sum(case when has_nslp = true then 1 else 0 end)                     as nslp
        ,sum(case when has_oap = true then 1 else 0 end)                     as oap
        ,sum(case when has_pell_grant = true then 1 else 0 end)                     as pell_grant
        ,sum(case when has_rag = true then 1 else 0 end)                     as rag
        ,sum(case when has_rtdlive = true then 1 else 0 end)                     as rtdlive
        ,sum(case when has_section_8 = true then 1 else 0 end)                     as section_8
        ,sum(case when has_snap = true then 1 else 0 end)                     as snap
        ,sum(case when has_ssi = true then 1 else 0 end)                     as ssi
        ,sum(case when has_sunbucks = true then 1 else 0 end)                     as sunbucks
        ,sum(case when has_tanf = true then 1 else 0 end)                     as tanf
        ,sum(case when has_ubp = true then 1 else 0 end)                     as ubp
        ,sum(case when has_upk = true then 1 else 0 end)                     as upk
        ,sum(case when has_va = true then 1 else 0 end)                     as va
        ,sum(case when has_wic = true then 1 else 0 end)                     as wic
    from data
    group by white_label_id, partner
    )

select
    unnest(array[
        'ACP'
        ,'ANDCS'
        ,'CCB'
        ,'CCCAP'
        ,'CCDF'
        ,'CDHCS'
        ,'CHP'
        ,'CHS'
        ,'CO ANDSO'
        ,'COCTC'
        ,'COEITC'
        ,'COWAP'
        ,'CPCR'
        ,'CSFP'
        ,'CTC'
        ,'DPP'
        ,'EDE'
        ,'EITC'
        ,'ERC'
        ,'FATC'
        ,'LEAP'
        ,'Lifeline'
        ,'MA EAEDC'
        ,'MA CFC'
        ,'MA EITC'
        ,'MA MBTA'
        ,'MA SSP'
        ,'Medicaid'
        ,'My Denver'
        ,'NC LIEAP'
        ,'NCCIP'
        ,'NC SCCA'
        ,'NC WAP'
        ,'NFP'
        ,'NSLP'
        ,'OAP'
        ,'Pell Grant'
        ,'RAG'
        ,'RTD Live'
        ,'Section 8'
        ,'SNAP'
        ,'SSI'
        ,'Sunbucks'
        ,'TANF'
        ,'UBP'
        ,'UPK'
        ,'VA'
        ,'WIC'
        ]) as Benefit
    ,unnest(array[
        acp
        ,andcs
        ,ccb
        ,cccap
        ,ccdf
        ,cdhcs
        ,chp
        ,chs
        ,co_andso
        ,coctc
        ,coeitc
        ,cowap
        ,cpcr
        ,csfp
        ,ctc
        ,dpp
        ,ede
        ,eitc
        ,erc
        ,fatc
        ,leap
        ,lifeline
        ,ma_eaedc
        ,ma_macfc
        ,ma_maeitc
        ,ma_mbta
        ,ma_ssp
        ,medicaid
        ,mydenver
        ,nc_lieap
        ,nccip
        ,ncscca
        ,ncwap
        ,nfp
        ,nslp
        ,oap
        ,pell_grant
        ,rag
        ,rtdlive
        ,section_8
        ,snap
        ,ssi
        ,sunbucks
        ,tanf
        ,ubp
        ,upk
        ,va
        ,wic
        ]) as Count
    ,white_label_id
    ,partner
from base;
