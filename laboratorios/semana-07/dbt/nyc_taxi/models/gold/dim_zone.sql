{#
  GOLD - Dimensión zona (se usa dos veces: zona de recogida y zona de destino).
  PK: zone_key (llave sustituta). Llave natural: location_id.
#}
{{ config(materialized='table') }}

select
    {{ dbt_utils.generate_surrogate_key(['location_id']) }} as zone_key,
    location_id,
    borough,
    zone_name,
    service_zone,
    is_airport,
    is_unknown_location
from {{ ref('slv_taxi_zones') }}