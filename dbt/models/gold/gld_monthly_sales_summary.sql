-- Gold: monthly executive sales summary (grain: 1 row per order_year x order_month).
-- Tracks high-level financial metrics, channel splits, and month-over-month (MoM) revenue growth.

with lines as (

    select
        order_year,
        order_month,
        count(distinct customer_id)                             as unique_customers,
        sum(order_qty)                                          as total_units_sold,
        sum(gross_amount)                                       as gross_revenue,
        sum(discount_amount)                                    as discount_amount,
        sum(net_amount)                                         as net_revenue,
        sum(cost_amount)                                        as cost_amount,
        sum(gross_profit)                                       as gross_profit,
        sum(case when order_channel = 'Online' then net_amount else 0 end)
                                                                as online_revenue,
        sum(case when order_channel = 'Reseller' then net_amount else 0 end)
                                                                as reseller_revenue
    from {{ ref('slvr_sales_order_lines') }}
    group by order_year, order_month

),

orders as (

    select
        year(order_date)                                        as order_year,
        month(order_date)                                       as order_month,
        count(*)                                                as total_orders,
        sum(case when order_channel = 'Online' then 1 else 0 end)
                                                                as online_orders,
        sum(case when order_channel = 'Reseller' then 1 else 0 end)
                                                                as reseller_orders,
        sum(tax_amount)                                         as tax_amount,
        sum(freight_amount)                                     as freight_amount,
        sum(is_late_shipment)                                   as late_shipments
    from {{ ref('slvr_sales_orders') }}
    group by year(order_date), month(order_date)

),

joined as (

    select
        o.order_year,
        o.order_month,
        concat(cast(o.order_year as varchar(4)), '-', right(concat('0', cast(o.order_month as varchar(2))), 2))
                                                                as year_month_label,
        o.total_orders,
        o.online_orders,
        o.reseller_orders,
        l.unique_customers,
        l.total_units_sold,
        l.gross_revenue,
        l.discount_amount,
        l.net_revenue,
        l.cost_amount,
        l.gross_profit,
        cast(l.gross_profit / nullif(l.net_revenue, 0) as decimal(9, 4))
                                                                as gross_margin_pct,
        cast(l.net_revenue / nullif(o.total_orders, 0) as decimal(19, 4))
                                                                as avg_order_value,
        l.online_revenue,
        l.reseller_revenue,
        cast(l.online_revenue / nullif(l.net_revenue, 0) as decimal(9, 4))
                                                                as online_revenue_share_pct,
        o.tax_amount,
        o.freight_amount,
        o.late_shipments
    from orders o
    inner join lines l
        on o.order_year = l.order_year
       and o.order_month = l.order_month

),

with_growth as (

    select
        *,
        lag(net_revenue) over (order by order_year, order_month)
                                                                as prior_month_net_revenue,
        cast(
            (net_revenue - lag(net_revenue) over (order by order_year, order_month))
            / nullif(lag(net_revenue) over (order by order_year, order_month), 0)
            as decimal(9, 4)
        )                                                       as mom_revenue_growth_pct
    from joined

)

select * from with_growth
