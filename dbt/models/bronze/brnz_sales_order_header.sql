-- Bronze: 1:1 with Sales.SalesOrderHeader
-- Rename to snake_case, cast types, trim strings.
-- Dropped: RevisionNumber, BillTo/ShipToAddressID, CreditCardID,
--          CreditCardApprovalCode (sensitive), CurrencyRateID, Comment, rowguid.

with source as (

    select * from {{ source('sales', 'SalesOrderHeader') }}

),

renamed as (

    select
        cast(SalesOrderID as int)                               as sales_order_id,
        cast(OrderDate as datetime)                             as order_date,
        cast(DueDate as datetime)                               as due_date,
        cast(ShipDate as datetime)                              as ship_date,
        cast(Status as int)                                     as order_status_code,
        cast(OnlineOrderFlag as int)                            as is_online_order,
        nullif(ltrim(rtrim(SalesOrderNumber)), '')              as sales_order_number,
        nullif(ltrim(rtrim(PurchaseOrderNumber)), '')           as purchase_order_number,
        nullif(ltrim(rtrim(AccountNumber)), '')                 as account_number,
        cast(CustomerID as int)                                 as customer_id,
        cast(SalesPersonID as int)                              as sales_person_id,
        cast(TerritoryID as int)                                as territory_id,
        cast(ShipMethodID as int)                               as ship_method_id,
        cast(SubTotal as decimal(19, 4))                        as subtotal_amount,
        cast(TaxAmt as decimal(19, 4))                          as tax_amount,
        cast(Freight as decimal(19, 4))                         as freight_amount,
        cast(TotalDue as decimal(19, 4))                        as total_due_amount,
        cast(ModifiedDate as datetime)                          as modified_at
    from source

)

select * from renamed
