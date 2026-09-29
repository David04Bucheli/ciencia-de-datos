{#
  GOLD - Dimensión fecha. Una fila por día del calendario.
  PK: date_key (entero AAAAMMDD). Rango: var('dim_date_start') a var('dim_date_end').
#}
{{ config(materialized='table') }}

with days as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('dim_date_start') ~ "' as date)",
        end_date="cast('" ~ var('dim_date_end') ~ "' as date)"
    ) }}

),

base as (

    select cast(date_day as date) as full_date
    from days

)

select
    {{ date_key('full_date') }}                                     as date_key,
    full_date,
    cast(extract(year from full_date) as integer)                   as calendar_year,
    cast(extract(quarter from full_date) as integer)                as calendar_quarter,
    cast(extract(month from full_date) as integer)                  as calendar_month,
    {{ month_name_es('cast(extract(month from full_date) as integer)') }} as month_name,
    cast(extract(year from full_date) as varchar) || '-'
        || lpad(cast(cast(extract(month from full_date) as integer) as varchar), 2, '0') as year_month,
    cast(extract(day from full_date) as integer)                    as day_of_month,
    dayofweekiso(full_date)                                         as day_of_week,
    {{ day_name_es('dayofweekiso(full_date)') }}                    as day_name,
    weekiso(full_date)                                              as iso_week,
    dayofweekiso(full_date) in (6, 7)                               as is_weekend
from base