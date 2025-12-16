{{
  config(
    materialized='view',
    description='Household age demographics and percentages'
  )
}}

select
    screen_id
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
from {{ source('django_apps', 'screener_householdmember') }}
group by screen_id