-- Infraestructura en Snowflake (2/3): esquemas = capas de la arquitectura
USE DATABASE ${SNOWFLAKE_DATABASE};

CREATE SCHEMA IF NOT EXISTS RAW
  COMMENT = 'Aterrizaje: archivos originales de la TLC y tablas cargadas tal cual llegan';
CREATE SCHEMA IF NOT EXISTS BRONZE
  COMMENT = 'Bronze (dbt): datos como la fuente + metadata de linaje';
CREATE SCHEMA IF NOT EXISTS SILVER
  COMMENT = 'Silver (dbt): datos limpios, tipados, estandarizados y deduplicados';
CREATE SCHEMA IF NOT EXISTS GOLD
  COMMENT = 'Gold (dbt): esquema estrella para analisis';