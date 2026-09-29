-- No quedan viajes duplicados en Silver limpio (misma llave de negocio que usa la regla).
select
    vendor_id, pickup_datetime, dropoff_datetime, pickup_location_id,
    dropoff_location_id, trip_distance_miles, fare_amount, total_amount,
    count(*) as copias
from {{ ref('slv_yellow_trips') }}
group by
    vendor_id, pickup_datetime, dropoff_datetime, pickup_location_id,
    dropoff_location_id, trip_distance_miles, fare_amount, total_amount
having count(*) > 1