-- Gold: product sales performance (grain: 1 row per product).
-- LEFT JOIN keeps products with no sales (metrics = 0) for complete analysis.

with products as (

    select * from {{ ref('slvr_products') }}

),

sales as (

    select
        product_id,
        count(distinct sales_order_id)                          as total_orders,
        sum(order_qty)                                          as total_units,
        sum(net_amount)                                         as net_revenue,
        sum(discount_amount)                                    as discount_amount,
        sum(cost_amount)                                        as cost_amount,
        sum(gross_profit)                                       as gross_profit,
        min(order_date)                                         as first_sale_date,
        max(order_date)                                         as last_sale_date
    from {{ ref('slvr_sales_order_lines') }}
    group by product_id

),

final as (

    select
        p.product_id,
        p.product_name,
        p.product_number,
        p.product_line,
        p.product_type,
        p.price_tier,
        p.is_active,
        p.list_price,
        p.standard_cost,
        coalesce(s.total_orders, 0)                             as total_orders,
        coalesce(s.total_units, 0)                              as total_units,
        coalesce(s.net_revenue, 0)                              as net_revenue,
        coalesce(s.discount_amount, 0)                          as discount_amount,
        coalesce(s.cost_amount, 0)                              as cost_amount,
        coalesce(s.gross_profit, 0)                             as gross_profit,
        cast(s.gross_profit / nullif(s.net_revenue, 0) as decimal(9, 4))
                                                                as gross_margin_pct,
        cast(s.net_revenue / nullif(s.total_units, 0) as decimal(19, 4))
                                                                as avg_selling_price,
        s.first_sale_date,
        s.last_sale_date,
        case when s.product_id is null then 0 else 1 end        as has_sales,
        rank() over (order by coalesce(s.net_revenue, 0) desc)  as revenue_rank
    from products p
    left join sales s
        on p.product_id = s.product_id

)

select * from final
