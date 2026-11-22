# MODELS.md — Catalog mô hình dữ liệu

Tài liệu mô tả toàn bộ mô hình DBT của dự án theo kiến trúc **Medallion**
(bronze → silver → gold), bao gồm nguồn dữ liệu, mục đích, grain và các test áp dụng.

> Tài liệu trực quan (lineage) được sinh tự động bằng `dbt docs generate` và sơ đồ
> PlantUML tại [`docs/diagrams/lineage.puml`](docs/diagrams/lineage.puml).

---

## 1. Nguồn dữ liệu (Sources)

Khai báo trong `dbt/models/bronze/_sources.yml`.

| Source | Schema | Bảng | Freshness |
|---|---|---|---|
| `sales` | Sales | `SalesOrderHeader`, `SalesOrderDetail`, `Customer` | `warn_after: 24h` |
| `production` | Production | `Product` | `warn_after: 7 ngày` |
| `person` | Person | `Person` | `warn_after: 7 ngày` |

> AdventureWorks2014 là dataset tĩnh (ModifiedDate ~2014-07) nên freshness chỉ dùng
> `warn_after` (cảnh báo) thay vì `error_after` để không làm gãy pipeline.

---

## 2. Bronze layer (5 model, materialized = view)

Nạp thô 1:1 với bảng nguồn, đổi tên cột sang snake_case, ép kiểu, `trim`, loại bỏ cột
kỹ thuật/nhạy cảm (`rowguid`, XML, `CreditCardID`, ...).

| Model | Nguồn | Grain | Ghi chú |
|---|---|---|---|
| `brnz_sales_order_header` | `sales.SalesOrderHeader` | 1 dòng / đơn hàng | `order_status_code` (1–6), `is_online_order` |
| `brnz_sales_order_detail` | `sales.SalesOrderDetail` | 1 dòng / dòng đơn hàng | `unit_price_discount_pct` (0–1) |
| `brnz_product` | `production.Product` | 1 dòng / sản phẩm | giải mã mã code ở Silver |
| `brnz_customer` | `sales.Customer` | 1 dòng / khách hàng | cờ `is_individual`, `is_store_customer` |
| `brnz_person` | `person.Person` | 1 dòng / người | `person_type_code`, `email_promotion_code` |

**Test chính:** `unique` + `not_null` trên khóa chính; `relationships` giữa các khóa
ngoại (detail→header, detail→product, customer→person); `accepted_values` cho các mã code.

---

## 3. Silver layer (4 model, materialized = table)

Làm sạch và làm giàu nghiệp vụ, kết hợp nhiều model Bronze.

| Model | Nguồn (`ref`) | Grain | Logic nghiệp vụ chính |
|---|---|---|---|
| `slvr_products` | `brnz_product` | 1 dòng / sản phẩm | Giải mã `product_line`/`class`/`style`/`type`, `price_tier`, `unit_margin`, cờ `is_active` |
| `slvr_customers` | `brnz_customer` + `brnz_person` | 1 dòng / khách hàng | `full_name`, phân loại `customer_type` (Retail/Wholesale), `email_promotion` |
| `slvr_sales_order_lines` | `brnz_sales_order_detail` + `brnz_sales_order_header` + `brnz_product` | 1 dòng / dòng đơn hàng | Kênh `order_channel`, trạng thái, `gross/discount/net/cost/profit`, `has_discount`; loại đơn Rejected/Cancelled và qty ≤ 0 |
| `slvr_sales_orders` | `brnz_sales_order_header` + `brnz_sales_order_detail` | 1 dòng / đơn hàng | `days_to_ship`, `is_late_shipment`, cờ đối soát subtotal `is_subtotal_reconciled` |

**Test chính:** `unique`/`not_null` khóa chính; `relationships` (lines→orders/products/customers);
`accepted_values` (channel, status, price_tier, customer_type...); custom tests
`is_positive` (qty, giá), `no_future_dates`, `valid_date_range` trên `order_date`.

---

## 4. Gold layer (4 model, materialized = table)

Mart phân tích, sẵn sàng cho BI.

| Model | Nguồn (`ref`) | Grain | KPI / kỹ thuật nâng cao |
|---|---|---|---|
| `gld_sales_daily` | `slvr_sales_order_lines` + `slvr_sales_orders` | 1 dòng / ngày × kênh | Doanh thu, margin, AOV, số đơn trễ theo kênh |
| `gld_product_performance` | `slvr_products` + `slvr_sales_order_lines` | 1 dòng / sản phẩm | Doanh thu, lợi nhuận, `revenue_rank` (hàm `RANK`) |
| `gld_customer_metrics` | `slvr_customers` + `slvr_sales_order_lines` + `slvr_sales_orders` | 1 dòng / khách hàng | LTV, recency, `customer_segment` (VIP/Loyal/Regular/One-Time/Prospect) |
| `gld_monthly_sales_summary` | `slvr_sales_order_lines` + `slvr_sales_orders` | 1 dòng / tháng | Tổng hợp tài chính, `prior_month_net_revenue` + `mom_revenue_growth_pct` (hàm `LAG`) |

**Test chính:** `unique`/`not_null` khóa chính + `relationships` về Silver;
`unique_combination_of_columns` cho grain (daily, monthly); `accepted_values` cho segment/tier.

---

## 5. Tests

### 5.1. Schema tests (trong `_*__models.yml`)
`not_null`, `unique`, `relationships`, `accepted_values`, `dbt_utils.unique_combination_of_columns`.

### 5.2. Custom generic tests (`dbt/tests/generic/`)

| Test | Tham số | Mục đích |
|---|---|---|
| `is_positive` | `allow_zero` (mặc định false) | Giá trị phải > 0 (số lượng, đơn giá...) |
| `no_future_dates` | — | Ngày không được ở tương lai |
| `valid_date_range` | `min_date`, `max_date` | Ngày nằm trong khoảng hợp lệ |

### 5.3. Singular test (`dbt/tests/`)
| Test | Mục đích |
|---|---|
| `assert_gold_revenue_matches_silver` | Đối soát tổng `net_revenue` của Silver (`slvr_sales_order_lines`) khớp Gold (`gld_monthly_sales_summary`) trong sai số 1.0 |

---

## 6. Lineage (tóm tắt)

```
Nguồn OLTP                    Bronze                    Silver                      Gold
sales.Customer ──────────► brnz_customer ──────┐
person.Person ───────────► brnz_person ────────┴──► slvr_customers ────────────► gld_customer_metrics
production.Product ──────► brnz_product ────────┬──► slvr_products ─────────────► gld_product_performance
sales.SalesOrderHeader ──► brnz_sales_order_header ─┬ slvr_sales_order_lines ───► gld_sales_daily
sales.SalesOrderDetail ──► brnz_sales_order_detail ─┴► slvr_sales_orders ────────► gld_monthly_sales_summary
```

Sơ đồ chi tiết: [`docs/diagrams/lineage.puml`](docs/diagrams/lineage.puml).
