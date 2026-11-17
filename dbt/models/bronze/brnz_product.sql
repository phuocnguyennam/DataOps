-- Bronze: 1:1 with Production.Product
-- Rename to snake_case, cast types, trim strings (nchar(2) codes carry
-- trailing spaces, e.g. 'R '). Dropped: rowguid.

with source as (

    select * from {{ source('production', 'Product') }}

),

renamed as (

    select
        cast(ProductID as int)                                  as product_id,
        nullif(ltrim(rtrim(Name)), '')                          as product_name,
        nullif(ltrim(rtrim(ProductNumber)), '')                 as product_number,
        cast(MakeFlag as int)                                   as is_manufactured_in_house,
        cast(FinishedGoodsFlag as int)                          as is_finished_good,
        nullif(ltrim(rtrim(Color)), '')                         as color,
        cast(SafetyStockLevel as int)                           as safety_stock_level,
        cast(ReorderPoint as int)                               as reorder_point,
        cast(StandardCost as decimal(19, 4))                    as standard_cost,
        cast(ListPrice as decimal(19, 4))                       as list_price,
        nullif(ltrim(rtrim(Size)), '')                          as size,
        nullif(ltrim(rtrim(SizeUnitMeasureCode)), '')           as size_unit,
        nullif(ltrim(rtrim(WeightUnitMeasureCode)), '')         as weight_unit,
        cast(Weight as decimal(10, 2))                          as weight,
        cast(DaysToManufacture as int)                          as days_to_manufacture,
        nullif(ltrim(rtrim(ProductLine)), '')                   as product_line_code,
        nullif(ltrim(rtrim(Class)), '')                         as class_code,
        nullif(ltrim(rtrim(Style)), '')                         as style_code,
        cast(ProductSubcategoryID as int)                       as product_subcategory_id,
        cast(ProductModelID as int)                             as product_model_id,
        cast(SellStartDate as datetime)                         as sell_start_date,
        cast(SellEndDate as datetime)                           as sell_end_date,
        cast(DiscontinuedDate as datetime)                      as discontinued_date,
        cast(ModifiedDate as datetime)                          as modified_at
    from source

)

select * from renamed
