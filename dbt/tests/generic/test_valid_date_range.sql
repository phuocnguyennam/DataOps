{% test valid_date_range(model, column_name, min_date='2000-01-01', max_date='2030-12-31') %}

select
    {{ column_name }}
from {{ model }}
where {{ column_name }} is not null
  and (
    cast({{ column_name }} as date) < cast('{{ min_date }}' as date)
    or cast({{ column_name }} as date) > cast('{{ max_date }}' as date)
  )

{% endtest %}
