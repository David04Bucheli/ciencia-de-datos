{#
  changed_files_filter(upstream)
  - Primera ejecución (o --full-refresh): procesa todo  ->  1 = 1
  - Siguientes: procesa COMPLETOS solo los archivos que tienen filas cargadas
    después de la última carga que ya está en este modelo.
  Con incremental_strategy='delete+insert' y unique_key='_source_file', dbt borra
  las filas viejas de esos archivos y las vuelve a insertar: nunca duplica.
#}
{% macro changed_files_filter(upstream, file_column='_source_file', loaded_at_column='_loaded_at') -%}
    {%- if is_incremental() -%}
        {{ file_column }} in (
            select distinct {{ file_column }}
            from {{ upstream }}
            where {{ loaded_at_column }} > (select max({{ loaded_at_column }}) from {{ this }})
               or not exists (select 1 from {{ this }})
        )
    {%- else -%}
        1 = 1
    {%- endif -%}
{%- endmacro %}