# Decisiones de limpieza y calidad de datos (capa Silver)

**Principio general:** Silver **no borra evidencia**. Cada registro de Bronze se evalúa en
`SILVER.SLV_YELLOW_TRIPS_STANDARDIZED`, con una bandera por regla. Los válidos pasan a
`SILVER.SLV_YELLOW_TRIPS` (la tabla que consume Gold). Los inválidos quedan en
`SILVER.SLV_YELLOW_TRIPS_REJECTED` con su motivo. El resumen por mes está en
`SILVER.SLV_DATA_QUALITY_SUMMARY`. Los umbrales están en `dbt_project.yml` (`vars`).

## 1. Tipos de datos

| Campo | Tipo en Silver | Justificación |
|---|---|---|
| Códigos (vendor, tarifa, pago, zonas, pasajeros) | `INTEGER` | Son identificadores o conteos. La fuente a veces los trae como decimales (`1.0`). |
| `pickup_datetime`, `dropoff_datetime` | `TIMESTAMP_NTZ` | Hora local de Nueva York, sin zona horaria, tal como la reporta el taxímetro. |
| Montos (`*_amount`) | `NUMERIC(18,2)` | Dinero con 2 decimales exactos; `FLOAT` acumula errores de redondeo al sumar millones de filas. |
| `trip_distance_miles` | `NUMERIC(18,2)` | Precisión suficiente (centésimas de milla). |
| `trip_duration_minutes` | `NUMERIC(18,2)` | Métrica derivada: (fin - inicio) en minutos. |

## 2. Nombres y formatos inconsistentes

| Problema en la fuente | Decisión |
|---|---|
| Nombres mezclados (`VendorID`, `PULocationID`, `Airport_fee`, `RatecodeID`) | Todo en `snake_case` descriptivo: `vendor_id`, `pickup_location_id`, `airport_fee_amount`, `rate_code_id`. |
| `store_and_fwd_flag` con `Y`/`N` (a veces con espacios o minúsculas) | `UPPER(TRIM())` y conversión al booleano `is_store_and_forward`. |
| Zonas: "sin dato" escrito de tres formas (`N/A`, `Unknown`, vacío) | Se unifica como `Unknown`; la zona 265 queda como `Outside of NYC`. |
| Códigos fuera del diccionario TLC | Se mapean al miembro "desconocido" que define el propio diccionario (sección 3). |

## 3. Valores nulos: imputar sin inventar

| Campo | Regla | Justificación |
|---|---|---|
| `vendor_id` nulo o no documentado | → `-1` (Unknown) | Conserva el viaje y la integridad referencial con `dim_vendor`. |
| `rate_code_id` nulo o inválido | → `99` | El diccionario TLC define 99 = "Null/unknown". |
| `payment_type_id` nulo o inválido | → `5` | El diccionario TLC define 5 = "Unknown". |
| Zona nula o inexistente | → `264` | Zona "Unknown" del catálogo TLC; ningún viaje queda sin zona. |
| `passenger_count` nulo, 0 o > 6 | → `NULL` | No se inventa un número: 0 no tiene sentido en un viaje cobrado y más de 6 supera el límite legal TLC (5 + 1 menor de 7 años). `NULL` evita sesgar promedios. |
| Recargos, propinas y peajes nulos | → `0` | La ausencia del componente significa que no se cobró; así los componentes suman. |
| `fare_amount` o `total_amount` nulos | Rechazo `MISSING_AMOUNT` | Sin monto no hay métrica económica confiable. |
| Hora de inicio o fin nula | Rechazo `MISSING_DATETIME` | No se puede ubicar el viaje en el tiempo. |

La columna `dq_imputations` registra qué se imputó en cada viaje.

## 4. Duplicados

Dos registros son el mismo viaje si coinciden en proveedor, hora exacta de inicio y fin, zonas
de origen y destino, distancia, tarifa y total. Se conserva la **primera aparición** en el
archivo (menor `_file_row_number`) y las demás copias se marcan `DUPLICATE`. Comparar dentro de
cada archivo basta, porque la regla `OUT_OF_PERIOD` garantiza que cada viaje válido pertenece a
un solo mes. La prueba `assert_no_duplicate_trips_in_silver` lo verifica en todo el histórico.

## 5. Registros inválidos (rechazo a cuarentena)

| Prioridad | Motivo | Regla | Justificación |
|---|---|---|---|
| 1 | `MISSING_DATETIME` | Falta hora de inicio o fin | No se ubica el viaje en el tiempo. |
| 2 | `DUPLICATE` | Misma llave de negocio que otro registro | Contarlo dos veces infla viajes e ingresos. |
| 3 | `OUT_OF_PERIOD` | El inicio no cae en el mes del archivo | Errores del reloj del taxímetro (fechas de otros años); además asegura un solo archivo por viaje. |
| 4 | `NON_POSITIVE_DURATION` | Fin igual o anterior al inicio | Es físicamente imposible. |
| 5 | `EXCESSIVE_DURATION` | Más de 24 horas | Taxímetro olvidado encendido; no es un viaje real. |
| 6 | `MISSING_AMOUNT` | Falta tarifa o total | Sin monto no hay métrica. |
| 7 | `NEGATIVE_AMOUNT` | Algún monto negativo | Son reversos o anulaciones contables, no viajes. |
| 8 | `EXCESSIVE_AMOUNT` | Total > USD 1.000 | Error de digitación: incluso la tarifa fija a JFK ronda los USD 70. |
| 9 | `INVALID_DISTANCE` | Distancia < 0 o > 200 millas | Error del odómetro: NYC mide ~35 millas de extremo a extremo. |
| 10 | `EMPTY_TRIP` | Distancia 0 y total 0 | No hubo desplazamiento ni cobro. |
