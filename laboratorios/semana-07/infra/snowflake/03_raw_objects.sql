-- Infraestructura en Snowflake (3/3): objetos de aterrizaje (RAW)
USE DATABASE ${SNOWFLAKE_DATABASE};
USE SCHEMA RAW;

CREATE FILE FORMAT IF NOT EXISTS FF_PARQUET
  TYPE = PARQUET
  USE_LOGICAL_TYPE = TRUE          -- interpreta bien las fechas/horas del Parquet
  COMMENT = 'Archivos mensuales de viajes (Parquet)';

CREATE FILE FORMAT IF NOT EXISTS FF_CSV
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  COMMENT = 'Tabla de zonas de taxi (CSV)';

-- Stage interno: copia de cada archivo ORIGINAL descargado
CREATE STAGE IF NOT EXISTS TLC_STAGE
  FILE_FORMAT = (FORMAT_NAME = 'FF_PARQUET')
  COMMENT = 'Copia de los archivos originales de la TLC (yellow/ y zones/)';

-- Viajes tal como vienen en el Parquet + 4 columnas de metadata que llena el COPY
CREATE TABLE IF NOT EXISTS YELLOW_TRIPDATA (
    VENDORID               NUMBER(38,0),
    TPEP_PICKUP_DATETIME   TIMESTAMP_NTZ,
    TPEP_DROPOFF_DATETIME  TIMESTAMP_NTZ,
    PASSENGER_COUNT        NUMBER(38,0),
    TRIP_DISTANCE          FLOAT,
    RATECODEID             NUMBER(38,0),
    STORE_AND_FWD_FLAG     VARCHAR,
    PULOCATIONID           NUMBER(38,0),
    DOLOCATIONID           NUMBER(38,0),
    PAYMENT_TYPE           NUMBER(38,0),
    FARE_AMOUNT            FLOAT,
    EXTRA                  FLOAT,
    MTA_TAX                FLOAT,
    TIP_AMOUNT             FLOAT,
    TOLLS_AMOUNT           FLOAT,
    IMPROVEMENT_SURCHARGE  FLOAT,
    TOTAL_AMOUNT           FLOAT,
    CONGESTION_SURCHARGE   FLOAT,
    AIRPORT_FEE            FLOAT,
    CBD_CONGESTION_FEE     FLOAT,
    _SOURCE_FILE           VARCHAR,        -- archivo de origen (yellow/yellow_tripdata_AAAA-MM.parquet)
    _FILE_ROW_NUMBER       NUMBER(38,0),   -- número de fila dentro del archivo
    _FILE_LAST_MODIFIED    TIMESTAMP_NTZ,  -- fecha del archivo en el stage
    _LOADED_AT             TIMESTAMP_LTZ   -- momento de la carga
)
COMMENT = 'Viajes Yellow Taxi tal como los publica la TLC';

CREATE TABLE IF NOT EXISTS TAXI_ZONE_LOOKUP (
    LOCATIONID    NUMBER(38,0),
    BOROUGH       VARCHAR,
    ZONE          VARCHAR,
    SERVICE_ZONE  VARCHAR,
    _SOURCE_FILE  VARCHAR,
    _LOADED_AT    TIMESTAMP_LTZ
)
COMMENT = 'Tabla de zonas de taxi de la TLC tal como se publica';

-- Bitácora: una fila por archivo con su último estado (idempotencia + auditoría)
CREATE TABLE IF NOT EXISTS INGESTION_LOG (
    SOURCE_FILE           VARCHAR NOT NULL,
    DATASET               VARCHAR,
    SOURCE_PERIOD         DATE,
    SOURCE_URL            VARCHAR,
    ETAG                  VARCHAR,
    CONTENT_LENGTH        NUMBER(38,0),
    SOURCE_LAST_MODIFIED  VARCHAR,
    FILE_ROWS             NUMBER(38,0),
    ROWS_LOADED           NUMBER(38,0),
    SOURCE_COLUMNS        VARCHAR,
    STATUS                VARCHAR,       -- LOADED | NOT_AVAILABLE | FAILED
    MESSAGE               VARCHAR,
    ATTEMPTS              NUMBER(38,0),
    UPDATED_AT            TIMESTAMP_LTZ,
    CONSTRAINT PK_INGESTION_LOG PRIMARY KEY (SOURCE_FILE)
)
COMMENT = 'Estado de ingesta por archivo';