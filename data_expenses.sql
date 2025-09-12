-- # Create the Expenses table
create materialized view
    data_expenses as

select
    d.id as screener_id
    ,d.submission_date
    ,d.white_label_id
    ,se.*
from screener_expense se
left join data d on se.screen_id=d.id
where se.screen_id in(d.id)
