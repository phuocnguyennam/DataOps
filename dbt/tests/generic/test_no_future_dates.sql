{% test no_future_dates(model, column_name) %}

select
    {{ column_name }}
from {{ model }}
where {{ column_name }} is not null
  and cast({{ column_name }} as date) > cast(getdate() as date)

{% endtest %}
