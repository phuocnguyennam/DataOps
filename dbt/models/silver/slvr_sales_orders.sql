-- Silver: order-level fact (grain: 1 row per sales order).
-- Joins header with detail aggregated once per order; adds shipping
-- performance and a subtotal reconciliation data-quality flag.

with headers as (

    select * from {{ ref('brnz_sales_order_header') }}

),

line_agg as (

    select
        sales_order_id,
        count(*)                                                as line_count,
        sum(order_qty)                                          as total_units,
        sum(line_total)                                         as lines_subtotal
    from {{ ref('brnz_sales_order_detail') }}
    group by sales_order_id

),

final as (

    select
        h.sales_order_id,
        h.sales_order_number,
        h.customer_id,
        h.sales_person_id,
        h.territory_id,

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

        cast(h.order_date as date)                              as order_date,
        cast(h.due_date as date)                                as due_date,
        cast(h.ship_date as date)                               as ship_date,
        datediff(day, h.order_date, h.ship_date)                as days_to_ship,
        case when h.ship_date > h.due_date
            then 1 else 0
        end                                                     as is_late_shipment,

        coalesce(l.line_count, 0)                               as line_count,
        coalesce(l.total_units, 0)                              as total_units,
        h.subtotal_amount,
        h.tax_amount,
        h.freight_amount,
        h.total_due_amount,
        coalesce(l.lines_subtotal, 0)                           as lines_subtotal,
        case when abs(h.subtotal_amount - coalesce(l.lines_subtotal, 0)) < 0.01
            then 1 else 0
        end                                                     as is_subtotal_reconciled
    from headers h
    left join line_agg l
        on h.sales_order_id = l.sales_order_id
    where h.order_status_code not in (4, 6)   -- exclude Rejected / Cancelled

)

select * from final
