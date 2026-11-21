{% test is_positive(model, column_name, allow_zero=false) %}

select
    {{ column_name }}
from {{ model }}
where {{ column_name }} is not null
  {% if allow_zero %}
  and {{ column_name }} < 0
  {% else %}
  and {{ column_name }} <= 0
  {% endif %}

{% endtest %}