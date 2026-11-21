-- Silver: customer dimension (grain: 1 row per customer).
-- Joins bronze customer and bronze person records to provide complete customer
-- profiles, full name formatting, and retail vs wholesale classification.

with customers as (

    select * from {{ ref('brnz_customer') }}

),

persons as (

    select * from {{ ref('brnz_person') }}

),

final as (

    select
        c.customer_id,
        c.account_number,
        c.person_id,
        c.store_id,
        c.territory_id,
        p.first_name,
        p.last_name,

        case
            when p.person_id is not null then
                ltrim(rtrim(
                    concat(
                        p.first_name, ' ',
                        case when p.middle_name is not null then concat(p.middle_name, ' ') else '' end,
                        p.last_name
                    )
                ))
            else
                concat('Store Account ', c.account_number)
        end                                                     as full_name,

        case
            when c.is_individual = 1 then 'Retail Individual'
            when c.is_store_customer = 1 then 'Wholesale Store'
            else 'Other'
        end                                                     as customer_type,

        case p.email_promotion_code
            when 0 then 'No'
            when 1 then 'Direct Channel'
            when 2 then 'Partner Channel'
            else 'Unknown'
        end                                                     as email_promotion,

        c.is_individual,
        c.is_store_customer,
        c.modified_at
    from customers c
    left join persons p
        on c.person_id = p.person_id

)

select * from final
