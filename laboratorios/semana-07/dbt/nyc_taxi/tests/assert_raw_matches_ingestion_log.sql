-- Cada archivo LOADED en la bitácora tiene en RAW exactamente las filas que se reportaron al cargarlo.
with raw_counts as (
    select _source_file, count(*) as raw_rows
    from {{ source('raw', 'yellow_tripdata') }}
    group by _source_file
),

loaded_files as (
    select source_file, rows_loaded
    from {{ source('raw', 'ingestion_log') }}
    where dataset = 'yellow_tripdata'
      and status = 'LOADED'
)

select l.source_file, l.rows_loaded, r.raw_rows
from loaded_files as l
left join raw_counts as r
    on right(r._source_file, length(l.source_file)) = l.source_file
where coalesce(r.raw_rows, -1) <> l.rows_loaded