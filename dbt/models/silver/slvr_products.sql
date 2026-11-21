-- Silver: cleaned product dimension (grain: 1 row per product).
-- Decodes raw code columns and adds business attributes. No rows filtered so
-- that unsold products remain available to the gold layer.

with products as (

    select * from {{ ref('brnz_product') }}

),

final as (

    select
        product_id,
        product_name,
        product_number,
        product_subcategory_id,
        coalesce(color, 'N/A')                                  as color,
        standard_cost,
        list_price,
        list_price - standard_cost                              as unit_margin,

        case product_line_code
            when 'R' then 'Road'
            when 'M' then 'Mountain'
            when 'T' then 'Touring'
            when 'S' then 'Standard'
            else 'Unknown'
        end                                                     as product_line,

        case class_code
            when 'H' then 'High'
            when 'M' then 'Medium'
            when 'L' then 'Low'
            else 'Unknown'
        end                                                     as product_class,

        case style_code
            when 'W' then 'Women'
            when 'M' then 'Men'
            when 'U' then 'Universal'
            else 'Unknown'
        end                                                     as product_style,

        case when is_finished_good = 1
            then 'Finished Good' else 'Component'
        end                                                     as product_type,

        case
            when list_price = 0     then 'Not For Sale'
            when list_price < 100   then 'Low'
            when list_price < 1000  then 'Mid'
            else 'Premium'
        end                                                     as price_tier,

        case when sell_end_date is null and discontinued_date is null
            then 1 else 0
        end                                                     as is_active,

        sell_start_date,
        sell_end_date,
        modified_at
    from products

)

select * from final
