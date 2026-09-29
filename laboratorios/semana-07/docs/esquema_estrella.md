# Esquema estrella (capa GOLD)

```mermaid
erDiagram
    FCT_TRIPS }o--|| DIM_DATE : "pickup_date_key / dropoff_date_key"
    FCT_TRIPS }o--|| DIM_TIME : "pickup_time_key / dropoff_time_key"
    FCT_TRIPS }o--|| DIM_ZONE : "pickup_zone_key / dropoff_zone_key"
    FCT_TRIPS }o--|| DIM_VENDOR : "vendor_key"
    FCT_TRIPS }o--|| DIM_RATE_CODE : "rate_code_key"
    FCT_TRIPS }o--|| DIM_PAYMENT_TYPE : "payment_type_key"

    FCT_TRIPS {
        varchar trip_key PK "1 fila = 1 viaje valido"
        int pickup_date_key FK
        int dropoff_date_key FK
        int pickup_time_key FK
        int dropoff_time_key FK
        varchar pickup_zone_key FK
        varchar dropoff_zone_key FK
        varchar vendor_key FK
        varchar rate_code_key FK
        varchar payment_type_key FK
        timestamp pickup_datetime "atributo"
        timestamp dropoff_datetime "atributo"
        boolean is_store_and_forward "atributo"
        int trip_count "metrica"
        int passenger_count "metrica"
        decimal trip_distance_miles "metrica"
        decimal trip_duration_minutes "metrica"
        decimal fare_amount "metrica"
        decimal tip_amount "metrica"
        decimal tolls_amount "metrica"
        decimal congestion_surcharge_amount "metrica"
        decimal airport_fee_amount "metrica"
        decimal cbd_congestion_fee_amount "metrica"
        decimal total_amount "metrica"
        varchar _source_file "linaje"
    }
    DIM_DATE {
        int date_key PK "AAAAMMDD"
        date full_date
        int calendar_year
        int calendar_quarter
        int calendar_month
        varchar month_name
        varchar year_month
        int day_of_week
        varchar day_name
        boolean is_weekend
    }
    DIM_TIME {
        int time_key PK "hora 0-23"
        varchar hour_label
        varchar day_part
        boolean is_peak_hour
    }
    DIM_ZONE {
        varchar zone_key PK "hash de location_id"
        int location_id "llave natural"
        varchar borough
        varchar zone_name
        varchar service_zone
        boolean is_airport
    }
    DIM_VENDOR {
        varchar vendor_key PK "hash de vendor_id"
        int vendor_id "llave natural"
        varchar vendor_name
    }
    DIM_RATE_CODE {
        varchar rate_code_key PK "hash de rate_code_id"
        int rate_code_id "llave natural"
        varchar rate_code_name
        varchar rate_code_description
    }
    DIM_PAYMENT_TYPE {
        varchar payment_type_key PK "hash de payment_type_id"
        int payment_type_id "llave natural"
        varchar payment_type_name
        varchar payment_type_description
    }
```

## Grano

**Una fila de `fct_trips` = un viaje válido de Yellow Taxi**, es decir, un encendido y apagado del
taxímetro que pasó todas las reglas de calidad de Silver.

## Llaves

| Tabla | Llave primaria | Tipo de llave |
|---|---|---|
| `fct_trips` | `trip_key` | Hash de archivo de origen + número de fila: estable entre ejecuciones. |
| `dim_date` | `date_key` | Entero `AAAAMMDD` (estándar para fechas). |
| `dim_time` | `time_key` | Hora del día `0-23`. |
| `dim_zone` | `zone_key` | Sustituta: hash de `location_id`. |
| `dim_vendor` | `vendor_key` | Sustituta: hash de `vendor_id`. |
| `dim_rate_code` | `rate_code_key` | Sustituta: hash de `rate_code_id`. |
| `dim_payment_type` | `payment_type_key` | Sustituta: hash de `payment_type_id`. |

**Llaves foráneas:** `fct_trips` tiene 9. `dim_date`, `dim_time` y `dim_zone` son *role-playing
dimensions*: se usan dos veces, una para la recogida y otra para la llegada o el destino. Cada FK
tiene pruebas `not_null` y `relationships` en dbt.

## Métricas y atributos

- **Métricas aditivas:** `trip_count`, `trip_distance_miles`, `trip_duration_minutes` y todos los
  montos (`fare`, `extra`, `mta_tax`, `tip`, `tolls`, `improvement_surcharge`, `congestion_surcharge`,
  `airport_fee`, `cbd_congestion_fee`, `total`). `passenger_count` es aditiva, pero admite nulos.
- **Atributos del hecho (dimensiones degeneradas):** `pickup_datetime`, `dropoff_datetime` y
  `is_store_and_forward`.
- **Atributos de análisis en las dimensiones:** año, mes, día de la semana, fin de semana; franja
  horaria y hora pico; distrito, zona, zona de servicio y aeropuerto; proveedor; tarifa; forma de pago.

## Preguntas que responde

Viajes e ingresos por mes, día o franja horaria; rutas más frecuentes entre zonas; propina según la
forma de pago; efecto del cargo de congestión de Manhattan (desde enero de 2025); viajes a
aeropuertos. Hay consultas de ejemplo en `dbt/nyc_taxi/analyses/consultas_ejemplo.sql`.