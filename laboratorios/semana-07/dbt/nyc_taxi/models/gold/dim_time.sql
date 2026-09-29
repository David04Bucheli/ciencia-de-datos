{#
  GOLD - Dimensión hora del día. Una fila por hora (0-23).
  PK: time_key (0-23). Permite analizar la demanda por franja horaria.
#}
{{ config(materialized='table') }}

with hours as (

    select cast(generated_number - 1 as integer) as hour_of_day
    from ({{ dbt_utils.generate_series(upper_bound=24) }}) as series

)

select
    hour_of_day                                                          as time_key,
    hour_of_day,
    lpad(cast(hour_of_day as varchar), 2, '0') || ':00 - '
        || lpad(cast(hour_of_day as varchar), 2, '0') || ':59'           as hour_label,
    case
        when hour_of_day between 0 and 5   then 'Madrugada'
        when hour_of_day between 6 and 11  then 'Mañana'
        when hour_of_day between 12 and 17 then 'Tarde'
        else 'Noche'
    end                                                                  as day_part,
    hour_of_day between 7 and 9 or hour_of_day between 16 and 19         as is_peak_hour
from hours