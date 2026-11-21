-- Singular test: Đối soát (Reconciliation) tổng doanh thu giữa Silver và Gold
-- Nếu độ lệch vượt quá 1.0 (sai số làm tròn), test sẽ trả về dòng lỗi và FAIL.

with silver_revenue as (

    select
        sum(net_amount) as total_silver_revenue
    from {{ ref('slvr_sales_order_lines') }}

),

gold_revenue as (

    select
        sum(net_revenue) as total_gold_revenue
    from {{ ref('gld_monthly_sales_summary') }}

)

select
    s.total_silver_revenue,
    g.total_gold_revenue,
    abs(s.total_silver_revenue - g.total_gold_revenue) as diff
from silver_revenue s
cross join gold_revenue g
where abs(s.total_silver_revenue - g.total_gold_revenue) > 1.0
