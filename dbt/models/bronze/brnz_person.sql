-- Bronze: 1:1 with Person.Person
-- Rename to snake_case, cast types, trim strings.
-- Dropped: NameStyle, AdditionalContactInfo (xml), Demographics (xml), rowguid.

with source as (

    select * from {{ source('person', 'Person') }}

),

renamed as (

    select
        cast(BusinessEntityID as int)                           as person_id,
        nullif(ltrim(rtrim(PersonType)), '')                    as person_type_code,
        nullif(ltrim(rtrim(Title)), '')                         as title,
        nullif(ltrim(rtrim(FirstName)), '')                     as first_name,
        nullif(ltrim(rtrim(MiddleName)), '')                    as middle_name,
        nullif(ltrim(rtrim(LastName)), '')                      as last_name,
        nullif(ltrim(rtrim(Suffix)), '')                        as suffix,
        cast(EmailPromotion as int)                             as email_promotion_code,
        cast(ModifiedDate as datetime)                          as modified_at
    from source

)

select * from renamed
