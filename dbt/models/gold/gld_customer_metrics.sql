-- Gold: customer-level analytical mart (grain: 1 row per customer).
-- Provides customer lifetime value (LTV), purchasing behavior, recency, and segmentation.
-- LEFT JOIN ensures all customers (including those who haven't ordered yet) are included.

with customers as (

    select * from {{ ref('slvr_customers') }}

),

order_lines as (

    select * from {{ ref('slvr_sales_order_lines') }}

),

reference_date as (

    select max(order_date) as max_system_date
    from {{ ref('slvr_sales_orders') }}

),

customer_sales as (

    select
        customer_id,
        count(distinct sales_order_id)                          as total_orders,
        sum(order_qty)                                          as total_units_purchased,
        sum(net_amount)                                         as lifetime_revenue,
        sum(discount_amount)                                    as lifetime_discount_amount,
        sum(gross_profit)                                       as lifetime_gross_profit,
        min(order_date)                                         as first_order_date,
        max(order_date)                                         as last_order_date
    from order_lines
    group by customer_id

),

final as (

    select
        c.customer_id,
        c.account_number,
        c.full_name,
        c.customer_type,
        c.territory_id,
        c.email_promotion,
        coalesce(s.total_orders, 0)                             as total_orders,
        coalesce(s.total_units_purchased, 0)                    as total_units_purchased,
        coalesce(s.lifetime_revenue, 0)                         as lifetime_revenue,
        coalesce(s.lifetime_discount_amount, 0)                 as lifetime_discount_amount,
        coalesce(s.lifetime_gross_profit, 0)                    as lifetime_gross_profit,
        cast(s.lifetime_gross_profit / nullif(s.lifetime_revenue, 0) as decimal(9, 4))
                                                                as lifetime_margin_pct,
        cast(s.lifetime_revenue / nullif(s.total_orders, 0) as decimal(19, 4))
                                                                as avg_order_value,
        s.first_order_date,
        s.last_order_date,
        datediff(day, s.last_order_date, r.max_system_date)     as days_since_last_order,
        case
            when coalesce(s.total_orders, 0) = 0
                then 'Prospect / No Purchase'
            when s.lifetime_revenue >= 10000 or s.total_orders >= 10
                then 'VIP Customer'
            when s.lifetime_revenue >= 3000
                then 'Loyal Customer'
            when s.total_orders = 1
                then 'One-Time Buyer'
            else 'Regular Customer'
        end                                                     as customer_segment,
        case when s.customer_id is not null
            then 1 else 0
        end                                                     as has_orders
    from customers c
    cross join reference_date r
    left join customer_sales s
        on c.customer_id = s.customer_id

)

select * from final
