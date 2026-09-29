# Imagen de la tubería: código de ingesta (Python) + proyecto dbt.
# Kestra ejecuta cada paso del flujo dentro de un contenedor de esta imagen.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DBT_PROJECT_DIR=/app/dbt/nyc_taxi \
    DBT_PROFILES_DIR=/app/dbt/nyc_taxi \
    DBT_SEND_ANONYMOUS_USAGE_STATS=False

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY infra ./infra
COPY ingestion ./ingestion
COPY scripts ./scripts
COPY dbt ./dbt

# 1) Si los archivos se guardaron en Windows (saltos de línea CRLF), se pasan a
#    formato Linux (LF) para que se ejecuten sin errores dentro del contenedor.
# 2) Si ya existe el proyecto dbt, se descargan sus paquetes (dbt_utils).
RUN find /app -type f \( -name "*.sh" -o -name "*.py" -o -name "*.sql" -o -name "*.yml" -o -name "*.csv" \) \
        -exec sed -i 's/\r$//' {} + \
    && if [ -f /app/dbt/nyc_taxi/dbt_project.yml ]; then cd /app/dbt/nyc_taxi && dbt deps; fi

CMD ["python", "scripts/check_connection.py"]