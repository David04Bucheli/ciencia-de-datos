-- Gold cuadra con Silver: mismo número de viajes y mismo monto total por archivo de origen.
with silver as (
    select _source_file, count(*) as trips, sum(total_amount) as total
    from {{ ref('slv_yellow_trips') }}
    group by _source_file
),

gold as (
    select _source_file, sum(trip_count) as trips, sum(total_amount) as total
    from {{ ref('fct_trips') }}
    group by _source_file
)

select
    coalesce(s._source_file, g._source_file) as source_file,
    s.trips as silver_trips,
    g.trips as gold_trips,
    s.total as silver_total,
    g.total as gold_total
from silver as s
full outer join gold as g
    on s._source_file = g._source_file
where coalesce(s.trips, -1) <> coalesce(g.trips, -1)
   or coalesce(s.total, -1) <> coalesce(g.total, -1)