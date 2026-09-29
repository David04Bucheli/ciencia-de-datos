{#
  Por defecto dbt nombraría los esquemas "PUBLIC_BRONZE", "PUBLIC_SILVER"...
  Con esta macro se usan exactamente BRONZE, SILVER y GOLD (las capas).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}