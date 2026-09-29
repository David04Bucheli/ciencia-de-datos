-- Consultas de ejemplo sobre el esquema estrella (capa GOLD).

-- 1) Viajes, ingreso y ticket promedio por mes
select d.year_month,
       sum(f.trip_count)                 as viajes,
       round(sum(f.total_amount), 2)     as ingreso_total_usd,
       round(avg(f.total_amount), 2)     as ticket_promedio_usd
from {{ ref('fct_trips') }} as f
join {{ ref('dim_date') }} as d on f.pickup_date_key = d.date_key
group by d.year_month
order by d.year_month;

-- 2) Demanda por día de la semana y franja horaria
select d.day_name, t.day_part, sum(f.trip_count) as viajes
from {{ ref('fct_trips') }} as f
join {{ ref('dim_date') }} as d on f.pickup_date_key = d.date_key
join {{ ref('dim_time') }} as t on f.pickup_time_key = t.time_key
group by d.day_of_week, d.day_name, t.day_part
order by d.day_of_week, t.day_part;

-- 3) Top 10 rutas (zona de recogida -> zona de destino)
select pz.zone_name as zona_recogida, dz.zone_name as zona_destino,
       sum(f.trip_count) as viajes,
       round(avg(f.trip_distance_miles), 2) as distancia_promedio_millas
from {{ ref('fct_trips') }} as f
join {{ ref('dim_zone') }} as pz on f.pickup_zone_key = pz.zone_key
join {{ ref('dim_zone') }} as dz on f.dropoff_zone_key = dz.zone_key
group by pz.zone_name, dz.zone_name
order by viajes desc
limit 10;

-- 4) Propina como % de la tarifa, por forma de pago
select p.payment_type_description, sum(f.trip_count) as viajes,
       round(100 * sum(f.tip_amount) / nullif(sum(f.fare_amount), 0), 2) as propina_pct
from {{ ref('fct_trips') }} as f
join {{ ref('dim_payment_type') }} as p on f.payment_type_key = p.payment_type_key
group by p.payment_type_description
order by viajes desc;

-- 5) Cargo de congestión de Manhattan (CBD) por mes
select d.year_month,
       round(sum(f.cbd_congestion_fee_amount), 2) as cargo_cbd_usd,
       sum(case when f.cbd_congestion_fee_amount > 0 then 1 else 0 end) as viajes_con_cargo
from {{ ref('fct_trips') }} as f
join {{ ref('dim_date') }} as d on f.pickup_date_key = d.date_key
group by d.year_month
order by d.year_month;