-- Prueba de extremo a extremo: todo mes cargado en RAW tiene viajes en la tabla de hechos.
with loaded_files as (
    select source_file
    from {{ source('raw', 'ingestion_log') }}
    where dataset = 'yellow_tripdata'
      and status = 'LOADED'
),

fact_files as (
    select distinct _source_file from {{ ref('fct_trips') }}
)

select l.source_file
from loaded_files as l
left join fact_files as f
    on right(f._source_file, length(l.source_file)) = l.source_file
where f._source_file is null