{#
    Incremental via hash-diff, not a time watermark.

    Upstream has no reliable change signal: no updated_at columns, change
    tracking is off, and raw.tpch_now.orders/lineitem re-shift every date by
    current_date() - max(o_orderdate). Old orders and supplier costs can change
    at any time, so every run recomputes the full join and then:
      1. merges only rows that are new or whose content hash changed
      2. deletes rows whose key no longer exists upstream (post_hook)
    The result is row-for-row identical to a full refresh, while only writing
    the rows that actually changed. Schema changes sync in place; rows with a
    null row_hash (e.g. right after it is added) are rewritten once.
#}

{%- set tracked_columns = [
    'order_key', 'order_date', 'customer_key', 'part_key', 'supplier_key',
    'order_item_status_code', 'is_return', 'line_number', 'ship_date',
    'commit_date', 'receipt_date', 'ship_mode', 'supplier_cost', 'base_price',
    'discount_percentage', 'discounted_price', 'tax_rate', 'nation_key',
    'order_item_count', 'quantity', 'gross_item_sales_amount',
    'discounted_item_sales_amount', 'item_discount_amount', 'item_tax_amount',
    'net_item_sales_amount'
] -%}

{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'merge',
        unique_key = 'order_item_key',
        on_schema_change = 'sync_all_columns',
        tags = ['finance'],
        static_analysis = 'strict',
        post_hook = [
            "{% if is_incremental() %}
            delete from {{ this }} as existing
            where not exists (
                select 1
                from {{ ref('order_items') }} as order_item
                inner join {{ ref('part_suppliers') }} as part_supplier
                    on order_item.part_key = part_supplier.part_key and
                        order_item.supplier_key = part_supplier.supplier_key
                where order_item.order_item_key = existing.order_item_key
            )
            {% endif %}"
        ]
    )
}}

with order_item as (
    
    select * from {{ ref('order_items') }}

),
part_supplier as (
    
    select * from {{ ref('part_suppliers') }}

),
joined as (
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
        {# ps.retail_price, #}
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

    from
        order_item
        inner join part_supplier
            on order_item.part_key = part_supplier.part_key and
                order_item.supplier_key = part_supplier.supplier_key

),
final as (
    select
        joined.*,
        {{ dbt_utils.generate_surrogate_key(tracked_columns) }} as row_hash
    from joined
)
select 
    final.*
from
    final
{% if is_incremental() %}
    {#- Before row_hash exists in the target (first run after this change),
        rewrite every row once; sync_all_columns adds the column. -#}
    {%- set existing_columns = adapter.get_columns_in_relation(this) | map(attribute='name') | map('lower') | list -%}
    {%- if 'row_hash' in existing_columns %}
    left join {{ this }} as existing
        on final.order_item_key = existing.order_item_key
    where existing.order_item_key is null
        or existing.row_hash is distinct from final.row_hash
    {%- endif %}
{% endif %}
order by
    final.order_date
