# Arquitectura de la solución

```mermaid
flowchart LR
    subgraph FUENTE["Fuente: NYC TLC (sitio público)"]
        TLC["Parquet mensuales<br/>yellow_tripdata_AAAA-MM.parquet<br/>+ taxi_zone_lookup.csv"]
    end

    subgraph LOCAL["PC · Docker Compose"]
        KESTRA["Kestra<br/>flujo elt_pipeline<br/>+ ejecución mensual"]
        PG[("Postgres<br/>memoria de Kestra")]
        subgraph IMG["Contenedores de la imagen nyc-taxi-pipeline"]
            INFRA["1. bootstrap<br/>infra/snowflake/*.sql"]
            ING["2. ingesta Python<br/>descarga, PUT y COPY<br/>idempotente por archivo"]
            DBT["3. dbt build<br/>bronze, silver, gold<br/>+ 116 pruebas"]
        end
        KESTRA --- PG
        KESTRA -->|lanza en orden| INFRA --> ING --> DBT
    end

    subgraph SF["Snowflake · base NYC_TAXI · warehouse NYC_TAXI_WH"]
        STAGE[["RAW.TLC_STAGE<br/>archivos originales"]]
        RAW[("RAW<br/>YELLOW_TRIPDATA<br/>TAXI_ZONE_LOOKUP<br/>INGESTION_LOG")]
        BRZ[("BRONZE<br/>igual a la fuente<br/>+ metadata de linaje")]
        SLV[("SILVER<br/>limpio, tipado, sin duplicados<br/>+ cuarentena de rechazados")]
        GLD[("GOLD<br/>esquema estrella<br/>fct_trips + 6 dimensiones")]
        STAGE -->|COPY INTO| RAW --> BRZ --> SLV --> GLD
    end

    TLC -->|HTTPS| ING
    ING -->|PUT| STAGE
    INFRA -.->|CREATE ... IF NOT EXISTS| RAW
    DBT -.->|SQL| BRZ
    GLD --> BI["Análisis<br/>Snowsight / BI"]
```

## Componentes

| Componente | Tecnología | Responsabilidad |
|---|---|---|
| Infraestructura local | Docker Compose | Levanta Kestra y Postgres, y construye la imagen `nyc-taxi-pipeline` (Python 3.12 + dbt + código). |
| Infraestructura en la nube | SQL (`infra/snowflake/`) | Crea warehouse, base, esquemas por capa, stage, formatos y tablas RAW (`IF NOT EXISTS`). |
| Orquestación | Kestra 1.3 | Ejecuta las 6 tareas en orden, reintenta la ingesta y se programa el día 5 de cada mes. |
| Ingesta (E + L) | Python (`ingestion/`) | Descarga los archivos de la TLC, guarda el original en un stage y lo carga con `COPY INTO`. |
| Transformación (T) | dbt 1.12 (`dbt/nyc_taxi/`) | Modelos Bronze → Silver → Gold y 116 pruebas. |
| Almacenamiento y cómputo | Snowflake | Capas RAW, BRONZE, SILVER y GOLD en la base `NYC_TAXI`. |

## Por qué ELT

Primero se cargan los datos originales sin cambios (RAW y Bronze) y después se transforman
dentro de Snowflake con dbt. Los datos crudos se conservan siempre (cualquier regla de limpieza se
puede cambiar y recalcular sin volver a descargar nada).

## Idempotencia

1. **Ingesta:** `RAW.INGESTION_LOG` guarda la huella (ETag) y las filas de cada archivo. Un archivo
   sin cambios se salta. Si cambió, en una transacción se borran sus filas y se vuelve a cargar,
   verificando que Snowflake cargó exactamente las filas del archivo.
2. **dbt:** los modelos grandes son incrementales con `delete+insert` por `_source_file`: solo se
   procesan los archivos nuevos o recargados, y se reemplazan completos.
3. **Pruebas de reconciliación:** RAW = bitácora, Bronze = RAW, Silver evalúa todo Bronze y
   Gold = Silver (viajes y montos por archivo).