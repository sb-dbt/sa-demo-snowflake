-- fct_order_items is a hash-diff incremental. Fails if the incremental table
-- differs in any row from what a full refresh would produce right now.

with expected as (

    select
        order_item.order_item_key,
        order_item.order_key,
        order_item.order_date,
        order_item.customer_key,
        order_item.part_key,
        order_item.supplier_key,
        order_item.order_item_status_code,
        order_item.is_return,
        order_item.line_number,
        order_item.ship_date,
        order_item.commit_date,
        order_item.receipt_date,
        order_item.ship_mode,
        part_supplier.cost as supplier_cost,
        order_item.base_price,
        order_item.discount_percentage,
        order_item.discounted_price,
        order_item.tax_rate,
        part_supplier.nation_key,
        1 as order_item_count,
        order_item.quantity,
        order_item.gross_item_sales_amount,
        order_item.discounted_item_sales_amount,
        order_item.item_discount_amount,
        order_item.item_tax_amount,
        order_item.net_item_sales_amount
    from {{ ref('order_items') }} as order_item
    inner join {{ ref('part_suppliers') }} as part_supplier
        on order_item.part_key = part_supplier.part_key and
            order_item.supplier_key = part_supplier.supplier_key

),

actual as (

    select * exclude (row_hash) from {{ ref('fct_order_items') }}

),

missing_from_actual as (
    select 'missing_from_table' as diff, * from (select * from expected except select * from actual)
),

extra_in_actual as (
    select 'extra_in_table' as diff, * from (select * from actual except select * from expected)
)

select * from missing_from_actual
union all
select * from extra_in_actual
