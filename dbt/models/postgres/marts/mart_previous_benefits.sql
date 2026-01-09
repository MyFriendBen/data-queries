{{
  config(
    materialized='table',
    description='Materialized mart for previous beneftis'
  )
}}

select
    unnest(array[
        'ACP'
        ,'ANDCS'
        ,'CCB'
        ,'CCAP'
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
        ,ccap
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
from {{ ref('int_previous_benefits') }}
