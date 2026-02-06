{{ config(
    materialized='view',
    description='Intermediate model that unpivots current benefits counts into benefit-level rows'
) }}

select
    t.benefit as benefit,
    t.count as count,
    cb.white_label_id,
    cb.partner
from {{ ref('int_current_benefits') }} cb
cross join lateral unnest(
    array[
        'ACP'
        ,'ANDCS'
        ,'AWD Medicaid'
        ,'BCA'
        ,'CCAP'
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
        ,'NFP'
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
    ],
    array[
        cb.acp
        ,cb.andcs
        ,cb.awd_medicaid
        ,cb.bca
        ,cb.ccap
        ,cb.cdhcs
        ,cb.cfhc
        ,cb.chp
        ,cb.chs
        ,cb.cocb
        ,cb.coctc
        ,cb.coeitc
        ,cb.co_energy_calculator_bheap
        ,cb.co_energy_calculator_bhgap
        ,cb.co_energy_calculator_care
        ,cb.co_energy_calculator_cngba
        ,cb.co_energy_calculator_cpcr
        ,cb.co_energy_calculator_ea
        ,cb.co_energy_calculator_ebt
        ,cb.co_energy_calculator_eoc
        ,cb.co_energy_calculator_eoccip
        ,cb.co_energy_calculator_eocs
        ,cb.co_energy_calculator_leap
        ,cb.co_energy_calculator_poipp
        ,cb.co_energy_calculator_ubp
        ,cb.co_energy_calculator_xceleap
        ,cb.co_energy_calculator_xcelgap
        ,cb.co_medicaid
        ,cb.co_snap
        ,cb.co_tanf
        ,cb.co_wic
        ,cb.cowap
        ,cb.cpcr
        ,cb.ctc
        ,cb.cwd_medicaid
        ,cb.dpp
        ,cb.dptr
        ,cb.dsr
        ,cb.dtr
        ,cb.ede
        ,cb.eitc
        ,cb.emergency_medicaid
        ,cb.erap
        ,cb.erc
        ,cb.fatc
        ,cb.fps
        ,cb.leap
        ,cb.lifeline
        ,cb.lwcr
        ,cb.ma_aca
        ,cb.ma_ccdf
        ,cb.ma_cfc
        ,cb.ma_eaedc
        ,cb.ma_maeitc
        ,cb.ma_mass_health
        ,cb.ma_mass_health_limited
        ,cb.ma_mbta
        ,cb.ma_snap
        ,cb.ma_ssp
        ,cb.ma_tafdc
        ,cb.ma_wic
        ,cb.medicaid
        ,cb.medicare_savings
        ,cb.mydenver
        ,cb.myspark
        ,cb.nc_aca
        ,cb.nccip
        ,cb.nc_emergency_medicaid
        ,cb.nc_lieap
        ,cb.nc_medicaid
        ,cb.nc_scca
        ,cb.nc_snap
        ,cb.nc_tanf
        ,cb.nc_wap
        ,cb.nc_wic
        ,cb.il_aabd
        ,cb.il_aca
        ,cb.il_aca_adults
        ,cb.il_all_kids
        ,cb.il_bap
        ,cb.il_ctc
        ,cb.il_eitc
        ,cb.il_family_care
        ,cb.il_liheap
        ,cb.il_medicaid
        ,cb.il_moms_and_babies
        ,cb.il_nslp
        ,cb.il_snap
        ,cb.il_tanf
        ,cb.il_transit_reduced_fare
        ,cb.il_wic
        ,cb.nf
        ,cb.nfp
        ,cb.nslp
        ,cb.oap
        ,cb.omnisalud
        ,cb.pell_grant
        ,cb.rag
        ,cb.rhc
        ,cb.rtdlive
        ,cb.shitc
        ,cb.sunbucks
        ,cb.snap
        ,cb.ssdi
        ,cb.ssi
        ,cb.tabor
        ,cb.tanf
        ,cb.trua
        ,cb.ubp
        ,cb.wic
    ]
) as t(benefit, count)