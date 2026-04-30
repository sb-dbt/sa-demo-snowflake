{{
    config(
        materialized='table'
    )
}}

select * 
from {{ ref('dim_customers',v=2) }}
order by lifetime_value desc