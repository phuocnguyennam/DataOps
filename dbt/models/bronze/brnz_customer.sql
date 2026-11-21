-- Bronze: 1:1 with Sales.Customer
-- Rename to snake_case, cast types, trim strings.
-- Adds derived flags for individual retail consumer vs wholesale store account.
-- Dropped: rowguid.

with source as (

    select * from {{ source('sales', 'Customer') }}

),

renamed as (

    select
        cast(CustomerID as int)                                 as customer_id,
        cast(PersonID as int)                                   as person_id,
        cast(StoreID as int)                                    as store_id,
        cast(TerritoryID as int)                                as territory_id,
        nullif(ltrim(rtrim(AccountNumber)), '')                 as account_number,
        case when PersonID is not null
            then 1 else 0
        end                                                     as is_individual,
        case when StoreID is not null
            then 1 else 0
        end                                                     as is_store_customer,
        cast(ModifiedDate as datetime)                          as modified_at
    from source

)

select * from renamed
