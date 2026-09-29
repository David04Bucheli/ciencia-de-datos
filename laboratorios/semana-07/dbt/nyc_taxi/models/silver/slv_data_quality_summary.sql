{#
  SILVER - Resumen de calidad por mes: cuántos registros llegaron, cuántos son válidos
  y por qué se rechazó el resto.
#}
{{ config(materialized='view') }}

{%- set reasons = [
    'MISSING_DATETIME', 'DUPLICATE', 'OUT_OF_PERIOD', 'NON_POSITIVE_DURATION',
    'EXCESSIVE_DURATION', 'MISSING_AMOUNT', 'NEGATIVE_AMOUNT', 'EXCESSIVE_AMOUNT',
    'INVALID_DISTANCE', 'EMPTY_TRIP'
] -%}

select
    _source_period                                                        as source_period,
    count(*)                                                              as total_records,
    sum(case when is_valid then 1 else 0 end)                             as valid_records,
    sum(case when is_valid then 0 else 1 end)                             as rejected_records,
    round(100.0 * sum(case when is_valid then 1 else 0 end) / count(*), 2) as pct_valid,
    {%- for reason in reasons %}
    sum(case when rejection_reason = '{{ reason }}' then 1 else 0 end)    as rejected_{{ reason | lower }},
    {%- endfor %}
    sum(case when dq_imputations is not null then 1 else 0 end)           as records_with_imputations,
    sum(case when passenger_count is null then 1 else 0 end)              as passenger_count_unknown
from {{ ref('slv_yellow_trips_standardized') }}
group by _source_period