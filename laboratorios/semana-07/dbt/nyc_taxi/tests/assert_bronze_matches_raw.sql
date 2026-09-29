-- Bronze no pierde ni duplica registros: mismas filas por archivo que RAW.
with raw_counts as (
    select _source_file, count(*) as n from {{ source('raw', 'yellow_tripdata') }} group by _source_file
),

bronze_counts as (
    select _source_file, count(*) as n from {{ ref('brz_yellow_tripdata') }} group by _source_file
)

select
    coalesce(r._source_file, b._source_file) as source_file,
    r.n as raw_rows,
    b.n as bronze_rows
from raw_counts as r
full outer join bronze_counts as b
    on r._source_file = b._source_file
where coalesce(r.n, -1) <> coalesce(b.n, -1)