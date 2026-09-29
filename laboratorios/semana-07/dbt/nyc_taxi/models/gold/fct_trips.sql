{#
  GOLD - Tabla de hechos de viajes
  GRANO: una fila por viaje válido de Yellow Taxi (un encendido y apagado del taxímetro).
  PK: trip_key.  FKs: fecha y hora de recogida/llegada, zona de recogida/destino,
  proveedor, tarifa y forma de pago.  Métricas: pasajeros, distancia, duración y montos.
  Incremental: reemplaza por archivo de origen, igual que las capas anteriores.

  Las llaves de las dimensiones se calculan con la MISMA función que usan las
  dimensiones (hash de la llave natural): no hace falta unir decenas de millones de
  filas con cada dimensión, y las pruebas "relationships" garantizan la integridad.
#}
{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='_source_file',
        on_schema_change='append_new_columns'
    )
}}

with trips as (

    select *
    from {{ ref('slv_yellow_trips') }}
    where {{ changed_files_filter(ref('slv_yellow_trips')) }}

)

select
    -- llave primaria
    trip_id                                                              as trip_key,

    -- llaves foráneas (dimensiones)
    {{ date_key('pickup_datetime') }}                                    as pickup_date_key,
    cast(extract(hour from pickup_datetime) as integer)                  as pickup_time_key,
    {{ date_key('dropoff_datetime') }}                                   as dropoff_date_key,
    cast(extract(hour from dropoff_datetime) as integer)                 as dropoff_time_key,
    {{ dbt_utils.generate_surrogate_key(['pickup_location_id']) }}       as pickup_zone_key,
    {{ dbt_utils.generate_surrogate_key(['dropoff_location_id']) }}      as dropoff_zone_key,
    {{ dbt_utils.generate_surrogate_key(['vendor_id']) }}                as vendor_key,
    {{ dbt_utils.generate_surrogate_key(['rate_code_id']) }}             as rate_code_key,
    {{ dbt_utils.generate_surrogate_key(['payment_type_id']) }}          as payment_type_key,

    -- atributos del viaje (dimensiones degeneradas)
    pickup_datetime,
    dropoff_datetime,
    is_store_and_forward,

    -- métricas
    1                                                                    as trip_count,
    passenger_count,
    trip_distance_miles,
    trip_duration_minutes,
    fare_amount,
    extra_amount,
    mta_tax_amount,
    tip_amount,
    tolls_amount,
    improvement_surcharge_amount,
    congestion_surcharge_amount,
    airport_fee_amount,
    cbd_congestion_fee_amount,
    total_amount,

    -- linaje
    _source_file,
    _source_period,
    _loaded_at

from trips