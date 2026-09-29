{#
  SILVER - Cuarentena: registros que NO pasaron las reglas de calidad, con el motivo.
  No se borran: quedan para auditoría y para explicar las decisiones de limpieza.
#}
{{ config(materialized='view') }}

select
    trip_id,
    rejection_reason,
    dq_issues,
    pickup_datetime,
    dropoff_datetime,
    trip_duration_minutes,
    trip_distance_miles,
    passenger_count_reported,
    pickup_location_id_reported,
    dropoff_location_id_reported,
    payment_type_id_reported,
    fare_amount,
    total_amount,
    _source_file,
    _source_period,
    _file_row_number
from {{ ref('slv_yellow_trips_standardized') }}
where not is_valid