-- # Create the Income Stream table
create materialized view
    data_income as

select
    d.id as screener_id
    ,d.submission_date
    ,d.white_label_id
    ,si.*
from screener_incomestream si
left join data d on si.screen_id=d.id
where si.screen_id in(d.id)
