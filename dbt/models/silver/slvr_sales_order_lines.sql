-- Silver: order-line fact (grain: 1 row per sales order line).
-- Joins header + detail + product bronze models and derives revenue,
-- discount, cost and profit measures. Invalid / non-revenue rows filtered.

with headers as (

    select * from {{ ref('brnz_sales_order_header') }}

),

details as (

    select * from {{ ref('brnz_sales_order_detail') }}

),

products as (

    select product_id, standard_cost from {{ ref('brnz_product') }}

),

joined as (

    select
        d.sales_order_detail_id,
        d.sales_order_id,
        h.sales_order_number,
        d.product_id,
        h.customer_id,
        h.territory_id,
        cast(h.order_date as date)                              as order_date,
        year(h.order_date)                                      as order_year,
        month(h.order_date)                                     as order_month,

        case when h.is_online_order = 1
            then 'Online' else 'Reseller'
        end                                                     as order_channel,

        case h.order_status_code
            when 1 then 'In Process'
            when 2 then 'Approved'
            when 3 then 'Backordered'
            when 4 then 'Rejected'
            when 5 then 'Shipped'
            when 6 then 'Cancelled'
            else 'Unknown'
        end                                                     as order_status,

        d.order_qty,
        d.unit_price,
        d.unit_price_discount_pct,
        d.unit_price * d.order_qty                              as gross_amount,
        d.unit_price * d.order_qty - d.line_total               as discount_amount,
        d.line_total                                            as net_amount,
        p.standard_cost,
        p.standard_cost * d.order_qty                           as cost_amount,
        d.line_total - p.standard_cost * d.order_qty            as gross_profit,
        case when d.unit_price_discount_pct > 0
            then 1 else 0
        end                                                     as has_discount,
        h.order_status_code
    from details d
    inner join headers h
        on d.sales_order_id = h.sales_order_id
    left join products p
        on d.product_id = p.product_id

)

select
    sales_order_detail_id,
    sales_order_id,
    sales_order_number,
    product_id,
    customer_id,
    territory_id,
    order_date,
    order_year,
    order_month,
    order_channel,
    order_status,
    order_qty,
    unit_price,
    unit_price_discount_pct,
    gross_amount,
    discount_amount,
    net_amount,
    standard_cost,
    cost_amount,
    gross_profit,
    has_discount
from joined
where order_qty > 0
  and unit_price >= 0
  and order_status_code not in (4, 6)   -- exclude Rejected / Cancelled
