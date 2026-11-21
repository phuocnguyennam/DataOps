-- Bronze: 1:1 with Sales.SalesOrderDetail
-- Rename to snake_case, cast types, trim strings. Dropped: rowguid.

with source as (

    select * from {{ source('sales', 'SalesOrderDetail') }}

),

renamed as (

    select
        cast(SalesOrderDetailID as int)                         as sales_order_detail_id,
        cast(SalesOrderID as int)                               as sales_order_id,
        cast(ProductID as int)                                  as product_id,
        cast(SpecialOfferID as int)                             as special_offer_id,
        nullif(ltrim(rtrim(CarrierTrackingNumber)), '')         as carrier_tracking_number,
        cast(OrderQty as int)                                   as order_qty,
        cast(UnitPrice as decimal(19, 4))                       as unit_price,
        cast(UnitPriceDiscount as decimal(19, 4))               as unit_price_discount_pct,
        cast(LineTotal as decimal(19, 4))                       as line_total,
        cast(ModifiedDate as datetime)                          as modified_at
    from source

)

select * from renamed
