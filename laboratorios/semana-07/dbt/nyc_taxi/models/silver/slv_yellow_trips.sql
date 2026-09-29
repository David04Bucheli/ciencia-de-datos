{#
  SILVER - Viajes limpios (la tabla que consume Gold).
  Solo registros que pasaron todas las reglas (is_valid). Grano: un viaje válido.
#}
{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='_source_file',
        on_schema_change='append_new_columns'
    )
}}

select
    trip_id,
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    passenger_count,
    trip_distance_miles,
    trip_duration_minutes,
    rate_code_id,
    is_store_and_forward,
    pickup_location_id,
    dropoff_location_id,
    payment_type_id,
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
    dq_imputations,
    _source_file,
    _source_period,
    _loaded_at
from {{ ref('slv_yellow_trips_standardized') }}
where is_valid
  and {{ changed_files_filter(ref('slv_yellow_trips_standardized')) }}