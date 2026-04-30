{{
    config(
        materialized = 'table',
        tags = ['finance', 'aggregates']
    )
}}

with supplier_sales as (
    select 
        s.supplier_name,
        extract(year from oi.ship_date) as shipping_year,
        sum(oi.net_item_sales_amount) as net_sales_amount
    from {{ ref('dim_suppliers') }} s
    inner join {{ ref('fct_order_items') }} oi
        on s.supplier_key = oi.supplier_key
    group by 
        s.supplier_name,
        extract(year from oi.ship_date)
)

select 
    supplier_name,
    shipping_year,
    net_sales_amount
from supplier_sales
order by 
    supplier_name,
    shipping_year 