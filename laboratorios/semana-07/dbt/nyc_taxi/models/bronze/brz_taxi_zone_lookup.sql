{#
  BRONZE - Zonas de taxi: copia fiel del CSV de la TLC + metadata de origen.
  Tabla pequeña (265 filas): se reconstruye completa cada vez.
#}
{{ config(materialized='table') }}

select
    locationid,
    borough,
    zone,
    service_zone,
    _source_file,
    _loaded_at
from {{ source('raw', 'taxi_zone_lookup') }}