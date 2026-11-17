-- Gold: daily sales KPIs by channel (grain: order_date x order_channel).
-- Line-level measures come from slvr_sales_order_lines; order-level amounts
-- (tax, freight) come from slvr_sales_orders to avoid double counting.

with lines as (

    select
        order_date,
        order_channel,
        count(distinct customer_id)                             as unique_customers,
        sum(order_qty)                                          as total_units,
        sum(gross_amount)                                       as gross_revenue,
        sum(discount_amount)                                    as discount_amount,
        sum(net_amount)                                         as net_revenue,
        sum(cost_amount)                                        as cost_amount,
        sum(gross_profit)                                       as gross_profit
    from {{ ref('slvr_sales_order_lines') }}
    group by order_date, order_channel

),

orders as (

    select
        order_date,
        order_channel,
        count(*)                                                as total_orders,
        sum(tax_amount)                                         as tax_amount,
        sum(freight_amount)                                     as freight_amount,
        sum(is_late_shipment)                                   as late_shipments
    from {{ ref('slvr_sales_orders') }}
    group by order_date, order_channel

)

select
    o.order_date,
    o.order_channel,
    o.total_orders,
    coalesce(l.unique_customers, 0)                             as unique_customers,
    coalesce(l.total_units, 0)                                  as total_units,
    coalesce(l.gross_revenue, 0)                                as gross_revenue,
    coalesce(l.discount_amount, 0)                              as discount_amount,
    coalesce(l.net_revenue, 0)                                  as net_revenue,
    coalesce(l.cost_amount, 0)                                  as cost_amount,
    coalesce(l.gross_profit, 0)                                 as gross_profit,
    cast(l.gross_profit / nullif(l.net_revenue, 0) as decimal(9, 4))
                                                                as gross_margin_pct,
    cast(l.net_revenue / nullif(o.total_orders, 0) as decimal(19, 4))
                                                                as avg_order_value,
    o.tax_amount,
    o.freight_amount,
    o.late_shipments
from orders o
left join lines l
    on o.order_date = l.order_date
   and o.order_channel = l.order_channel
