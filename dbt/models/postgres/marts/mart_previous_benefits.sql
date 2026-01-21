{{
  config(
    materialized='table',
    description='Materialized mart for previous benefits'
  )
}}

select
    t.benefit as benefit,
    t.count as count,
    pb.white_label_id,
    pb.partner
from {{ ref('int_previous_benefits') }} pb
cross join lateral unnest(
    array[
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
        ],
    array[
        pb.acp
        ,pb.andcs
        ,pb.ccb
        ,pb.ccap
        ,pb.ccdf
        ,pb.cdhcs
        ,pb.chp
        ,pb.chs
        ,pb.co_andso
        ,pb.coctc
        ,pb.coeitc
        ,pb.cowap
        ,pb.cpcr
        ,pb.csfp
        ,pb.ctc
        ,pb.dpp
        ,pb.ede
        ,pb.eitc
        ,pb.erc
        ,pb.fatc
        ,pb.leap
        ,pb.lifeline
        ,pb.ma_eaedc
        ,pb.ma_macfc
        ,pb.ma_maeitc
        ,pb.ma_mbta
        ,pb.ma_ssp
        ,pb.medicaid
        ,pb.mydenver
        ,pb.nc_lieap
        ,pb.nccip
        ,pb.ncscca
        ,pb.ncwap
        ,pb.nfp
        ,pb.nslp
        ,pb.oap
        ,pb.pell_grant
        ,pb.rag
        ,pb.rtdlive
        ,pb.section_8
        ,pb.snap
        ,pb.ssi
        ,pb.sunbucks
        ,pb.tanf
        ,pb.ubp
        ,pb.upk
        ,pb.va
        ,pb.wic
    ]
) as t(benefit, count)
