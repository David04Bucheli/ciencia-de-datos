{#
  SILVER - Zonas de taxi limpias
  - Tipos: locationid -> entero.
  - Nulos inconsistentes: la fuente usa 'N/A', 'Unknown' y vacío para "sin dato";
    se unifican en 'Unknown' (o 'Outside of NYC' para la zona 265).
#}
{{ config(materialized='table') }}

with source as (

    select * from {{ ref('brz_taxi_zone_lookup') }}

),

cleaned as (

    select
        cast(locationid as integer)                                   as location_id,
        nullif(nullif(nullif(trim(borough), ''), 'N/A'), 'Unknown')   as borough_clean,
        nullif(nullif(trim(zone), ''), 'N/A')                         as zone_clean,
        nullif(nullif(trim(service_zone), ''), 'N/A')                 as service_zone_clean,
        _source_file,
        _loaded_at
    from source

)

select
    location_id,
    coalesce(borough_clean,
             case when zone_clean = 'Outside of NYC' then 'Outside of NYC' else 'Unknown' end) as borough,
    coalesce(zone_clean, 'Unknown')                                                         as zone_name,
    coalesce(service_zone_clean,
             case when zone_clean = 'Outside of NYC' then 'Outside of NYC' else 'Unknown' end) as service_zone,
    location_id in (1, 132, 138)                                    as is_airport,
    borough_clean is null                                           as is_unknown_location,
    _source_file,
    _loaded_at
from cleaned