{#
  BRONZE - Viajes Yellow Taxi
  Datos exactamente como vienen de la fuente (mismas columnas y valores, sin limpiar)
  + metadata para saber de dónde y cuándo vino cada fila.
  Incremental: solo procesa archivos nuevos o recargados y los reemplaza completos.
#}
{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='_source_file',
        on_schema_change='append_new_columns'
    )
}}

with source as (

    select *
    from {{ source('raw', 'yellow_tripdata') }}
    where {{ changed_files_filter(source('raw', 'yellow_tripdata')) }}

)

select
    -- columnas originales (sin cambios)
    vendorid,
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    passenger_count,
    trip_distance,
    ratecodeid,
    store_and_fwd_flag,
    pulocationid,
    dolocationid,
    payment_type,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    total_amount,
    congestion_surcharge,
    airport_fee,
    cbd_congestion_fee,

    -- metadata de linaje
    {{ dbt_utils.generate_surrogate_key(['_source_file', '_file_row_number']) }} as _record_id,
    _source_file,
    cast(right(replace(_source_file, '.parquet', ''), 7) || '-01' as date)  as _source_period,
    _file_row_number,
    _file_last_modified,
    _loaded_at

from source