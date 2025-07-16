-- # This creates data_householdmembers

drop materialized view if exists
    data_householdmembers

create materialized view
    data_householdmembers as

select
    d.id as screener_id
    ,d.white_label_id
    ,d.partner
    ,d.submission_date
    ,sh.*
from screener_householdmember sh
left join data d on sh.screen_id=d.id
where sh.screen_id in(d.id)

