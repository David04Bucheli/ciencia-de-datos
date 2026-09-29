{# Llave entera AAAAMMDD a partir de una fecha u hora (estándar Kimball para dim_date) #}
{% macro date_key(column) -%}
    cast(extract(year from {{ column }}) * 10000
         + extract(month from {{ column }}) * 100
         + extract(day from {{ column }}) as integer)
{%- endmacro %}


{# Nombre del mes en español a partir de su número (1-12) #}
{% macro month_name_es(month_number) -%}
    case {{ month_number }}
        when 1 then 'Enero' when 2 then 'Febrero' when 3 then 'Marzo' when 4 then 'Abril'
        when 5 then 'Mayo' when 6 then 'Junio' when 7 then 'Julio' when 8 then 'Agosto'
        when 9 then 'Septiembre' when 10 then 'Octubre' when 11 then 'Noviembre' when 12 then 'Diciembre'
    end
{%- endmacro %}


{# Nombre del día en español a partir del día ISO (1 = lunes ... 7 = domingo) #}
{% macro day_name_es(iso_day_number) -%}
    case {{ iso_day_number }}
        when 1 then 'Lunes' when 2 then 'Martes' when 3 then 'Miércoles' when 4 then 'Jueves'
        when 5 then 'Viernes' when 6 then 'Sábado' when 7 then 'Domingo'
    end
{%- endmacro %}