-- Silver evalúa TODOS los registros de Bronze: ninguno se pierde en la limpieza
-- (los inválidos quedan marcados, no desaparecen).
with bronze_counts as (
    select _source_file, count(*) as n from {{ ref('brz_yellow_tripdata') }} group by _source_file
),

silver_counts as (
    select _source_file, count(*) as n from {{ ref('slv_yellow_trips_standardized') }} group by _source_file
)

select
    coalesce(b._source_file, s._source_file) as source_file,
    b.n as bronze_rows,
    s.n as silver_rows
from bronze_counts as b
full outer join silver_counts as s
    on b._source_file = s._source_file
where coalesce(b.n, -1) <> coalesce(s.n, -1)