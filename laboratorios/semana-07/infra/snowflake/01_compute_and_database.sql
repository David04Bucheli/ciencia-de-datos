-- Infraestructura en Snowflake (1/3): cómputo y base de datos.
-- La ejecuta: python -m ingestion bootstrap  (solo crea lo que no existe)

-- Warehouse = el motor que ejecuta las consultas. XSMALL + auto-suspend 60 s = costo mínimo.
CREATE WAREHOUSE IF NOT EXISTS ${SNOWFLAKE_WAREHOUSE}
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Laboratorio NYC Taxi: warehouse de la tuberia ELT';

CREATE DATABASE IF NOT EXISTS ${SNOWFLAKE_DATABASE}
  COMMENT = 'Laboratorio NYC Taxi: capas RAW, BRONZE, SILVER y GOLD';