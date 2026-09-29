{#
  SILVER - Viajes estandarizados y evaluados
  Contiene TODOS los registros de Bronze (no se pierde ninguno) después de:
    1. Tipos y nombres: snake_case, enteros, timestamps y montos NUMERIC(18,2).
    2. Formatos inconsistentes: 'Y'/'N' -> booleano; códigos fuera del diccionario
       -> miembro "desconocido" (vendor -1, tarifa 99, pago 5, zona 264).
    3. Nulos: recargos/propinas nulos -> 0; pasajeros 0 o fuera de 1..6 -> NULL.
    4. Reglas de calidad: una bandera dq_* por regla, el motivo principal de rechazo
       y is_valid. Los duplicados se marcan (se conserva la primera fila del archivo).
  Las decisiones se justifican en docs/decisiones_calidad_datos.md.
#}
{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='_source_file',
        on_schema_change='append_new_columns'
    )
}}

{%- set money_columns = [
    ('fare_amount', 'fare_amount'),
    ('extra', 'extra_amount'),
    ('mta_tax', 'mta_tax_amount'),
    ('tip_amount', 'tip_amount'),
    ('tolls_amount', 'tolls_amount'),
    ('improvement_surcharge', 'improvement_surcharge_amount'),
    ('congestion_surcharge', 'congestion_surcharge_amount'),
    ('airport_fee', 'airport_fee_amount'),
    ('cbd_congestion_fee', 'cbd_congestion_fee_amount'),
    ('total_amount', 'total_amount'),
] -%}
{#- Componentes que, si vienen nulos, significan "no se cobró" -> 0 -#}
{%- set zero_if_null = [
    'extra_amount', 'mta_tax_amount', 'tip_amount', 'tolls_amount', 'improvement_surcharge_amount',
    'congestion_surcharge_amount', 'airport_fee_amount', 'cbd_congestion_fee_amount'
] -%}

with bronze as (

    select *
    from {{ ref('brz_yellow_tripdata') }}
    where {{ changed_files_filter(ref('brz_yellow_tripdata')) }}

),

vendors as (
    select vendor_id from {{ ref('ref_vendor') }} where vendor_id <> -1
),

rate_codes as (
    select rate_code_id from {{ ref('ref_rate_code') }}
),

payment_types as (
    select payment_type_id from {{ ref('ref_payment_type') }}
),

zones as (
    select location_id from {{ ref('slv_taxi_zones') }}
),

-- 1) Nombres y tipos -----------------------------------------------------------
typed as (

    select
        _record_id                                           as trip_id,
        cast(vendorid as integer)                            as vendor_id_reported,
        cast(tpep_pickup_datetime as timestamp_ntz)          as pickup_datetime,
        cast(tpep_dropoff_datetime as timestamp_ntz)         as dropoff_datetime,
        cast(passenger_count as integer)                     as passenger_count_reported,
        cast(round(trip_distance, 2) as numeric(18, 2))      as trip_distance_miles,
        cast(ratecodeid as integer)                          as rate_code_id_reported,
        upper(trim(store_and_fwd_flag))                      as store_and_fwd_flag_reported,
        cast(pulocationid as integer)                        as pickup_location_id_reported,
        cast(dolocationid as integer)                        as dropoff_location_id_reported,
        cast(payment_type as integer)                        as payment_type_id_reported,
        {%- for source_col, target_col in money_columns %}
        cast(round({{ source_col }}, 2) as numeric(18, 2))   as {{ target_col }}_reported,
        {%- endfor %}
        _source_file,
        _source_period,
        _file_row_number,
        _loaded_at
    from bronze

),

-- 2) Estandarización de códigos y tratamiento de nulos --------------------------
standardized as (

    select
        t.*,
        coalesce(v.vendor_id, -1)                            as vendor_id,
        case
            when t.passenger_count_reported between 1 and {{ var('max_passengers') }}
                then t.passenger_count_reported
        end                                                  as passenger_count,
        coalesce(rc.rate_code_id, 99)                        as rate_code_id,
        case t.store_and_fwd_flag_reported
            when 'Y' then true
            when 'N' then false
        end                                                  as is_store_and_forward,
        coalesce(pz.location_id, 264)                        as pickup_location_id,
        coalesce(dz.location_id, 264)                        as dropoff_location_id,
        coalesce(pt.payment_type_id, 5)                      as payment_type_id,
        {%- for source_col, target_col in money_columns %}
        {%- if target_col in zero_if_null %}
        coalesce(t.{{ target_col }}_reported, 0)             as {{ target_col }},
        {%- else %}
        t.{{ target_col }}_reported                          as {{ target_col }},
        {%- endif %}
        {%- endfor %}
        cast({{ dbt.datediff('t.pickup_datetime', 't.dropoff_datetime', 'second') }} / 60.0
             as numeric(18, 2))                              as trip_duration_minutes,
        -- qué campos se imputaron (para medir cuánto se corrigió)
        rtrim(
            case when v.vendor_id is null then 'VENDOR,' else '' end
            || case when t.passenger_count_reported is null
                      or t.passenger_count_reported not between 1 and {{ var('max_passengers') }}
                    then 'PASSENGER_COUNT,' else '' end
            || case when rc.rate_code_id is null then 'RATE_CODE,' else '' end
            || case when pz.location_id is null then 'PICKUP_LOCATION,' else '' end
            || case when dz.location_id is null then 'DROPOFF_LOCATION,' else '' end
            || case when pt.payment_type_id is null then 'PAYMENT_TYPE,' else '' end
            || case when t.store_and_fwd_flag_reported is null
                      or t.store_and_fwd_flag_reported not in ('Y', 'N')
                    then 'STORE_AND_FWD_FLAG,' else '' end
            , ','
        )                                                    as dq_imputations
    from typed as t
    left join vendors       as v  on t.vendor_id_reported = v.vendor_id
    left join rate_codes    as rc on t.rate_code_id_reported = rc.rate_code_id
    left join payment_types as pt on t.payment_type_id_reported = pt.payment_type_id
    left join zones         as pz on t.pickup_location_id_reported = pz.location_id
    left join zones         as dz on t.dropoff_location_id_reported = dz.location_id

),

-- 3) Reglas de calidad (una bandera por regla) ----------------------------------
flagged as (

    select
        s.*,
        (s.pickup_datetime is null or s.dropoff_datetime is null)             as dq_missing_datetime,
        (s.fare_amount is null or s.total_amount is null)                     as dq_missing_amount,
        coalesce(s.dropoff_datetime <= s.pickup_datetime, false)              as dq_non_positive_duration,
        coalesce(s.trip_duration_minutes > {{ var('max_trip_hours') }} * 60, false) as dq_excessive_duration,
        coalesce(s.trip_distance_miles < 0
                 or s.trip_distance_miles > {{ var('max_trip_miles') }}, false)  as dq_invalid_distance,
        coalesce(
            {%- for source_col, target_col in money_columns %}
            s.{{ target_col }} < 0{{ ' or' if not loop.last }}
            {%- endfor %}
        , false)                                                              as dq_negative_amount,
        coalesce(s.total_amount > {{ var('max_total_amount') }}, false)       as dq_excessive_amount,
        coalesce(s.trip_distance_miles = 0 and s.total_amount = 0, false)     as dq_empty_trip,
        coalesce(cast({{ dbt.date_trunc('month', 's.pickup_datetime') }} as date) <> s._source_period, false)
                                                                              as dq_out_of_period,
        -- Duplicado = mismo viaje de negocio: mismo proveedor, mismas horas exactas de
        -- inicio y fin, mismas zonas, misma distancia y mismos montos. Se conserva la
        -- primera aparición en el archivo.
        row_number() over (
            partition by
                s._source_file,
                s.vendor_id,
                s.pickup_datetime,
                s.dropoff_datetime,
                s.pickup_location_id,
                s.dropoff_location_id,
                s.trip_distance_miles,
                s.fare_amount,
                s.total_amount
            order by s._file_row_number
        ) > 1                                                                 as dq_duplicate
    from standardized as s

),

-- 4) Motivo de rechazo (el primero según prioridad) y todos los problemas -------
evaluated as (

    select
        f.*,
        case
            when f.dq_missing_datetime      then 'MISSING_DATETIME'
            when f.dq_duplicate             then 'DUPLICATE'
            when f.dq_out_of_period         then 'OUT_OF_PERIOD'
            when f.dq_non_positive_duration then 'NON_POSITIVE_DURATION'
            when f.dq_excessive_duration    then 'EXCESSIVE_DURATION'
            when f.dq_missing_amount        then 'MISSING_AMOUNT'
            when f.dq_negative_amount       then 'NEGATIVE_AMOUNT'
            when f.dq_excessive_amount      then 'EXCESSIVE_AMOUNT'
            when f.dq_invalid_distance      then 'INVALID_DISTANCE'
            when f.dq_empty_trip            then 'EMPTY_TRIP'
        end                                                                   as rejection_reason,
        rtrim(
            case when f.dq_missing_datetime      then 'MISSING_DATETIME,' else '' end
            || case when f.dq_duplicate          then 'DUPLICATE,' else '' end
            || case when f.dq_out_of_period      then 'OUT_OF_PERIOD,' else '' end
            || case when f.dq_non_positive_duration then 'NON_POSITIVE_DURATION,' else '' end
            || case when f.dq_excessive_duration then 'EXCESSIVE_DURATION,' else '' end
            || case when f.dq_missing_amount     then 'MISSING_AMOUNT,' else '' end
            || case when f.dq_negative_amount    then 'NEGATIVE_AMOUNT,' else '' end
            || case when f.dq_excessive_amount   then 'EXCESSIVE_AMOUNT,' else '' end
            || case when f.dq_invalid_distance   then 'INVALID_DISTANCE,' else '' end
            || case when f.dq_empty_trip         then 'EMPTY_TRIP,' else '' end
            , ','
        )                                                                     as dq_issues
    from flagged as f

)

select
    trip_id,
    -- valores estandarizados
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    passenger_count,
    trip_distance_miles,
    trip_duration_minutes,
    rate_code_id,
    is_store_and_forward,
    pickup_location_id,
    dropoff_location_id,
    payment_type_id,
    {%- for source_col, target_col in money_columns %}
    {{ target_col }},
    {%- endfor %}
    -- valores tal como se reportaron (auditoría)
    vendor_id_reported,
    passenger_count_reported,
    rate_code_id_reported,
    store_and_fwd_flag_reported,
    pickup_location_id_reported,
    dropoff_location_id_reported,
    payment_type_id_reported,
    -- calidad de datos
    dq_missing_datetime,
    dq_missing_amount,
    dq_non_positive_duration,
    dq_excessive_duration,
    dq_invalid_distance,
    dq_negative_amount,
    dq_excessive_amount,
    dq_empty_trip,
    dq_out_of_period,
    dq_duplicate,
    rejection_reason,
    nullif(dq_issues, '')                                                     as dq_issues,
    nullif(dq_imputations, '')                                                as dq_imputations,
    rejection_reason is null                                                  as is_valid,
    -- linaje
    _source_file,
    _source_period,
    _file_row_number,
    _loaded_at
from evaluated