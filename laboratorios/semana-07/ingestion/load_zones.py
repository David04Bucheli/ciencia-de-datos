"""Carga taxi_zone_lookup.csv en RAW.TAXI_ZONE_LOOKUP (reemplazo completo, idempotente)."""
from __future__ import annotations

import csv
import logging
import tempfile
from pathlib import Path

from . import snowflake_client as sf
from . import tlc
from .config import ZONES_URL, Settings

log = logging.getLogger(__name__)
FILE_NAME = "taxi_zone_lookup.csv"

COPY_SQL = f"""
COPY INTO RAW.TAXI_ZONE_LOOKUP (LOCATIONID, BOROUGH, ZONE, SERVICE_ZONE, _SOURCE_FILE, _LOADED_AT)
FROM (
    SELECT $1, $2, $3, $4, METADATA$FILENAME, METADATA$START_SCAN_TIME
    FROM @RAW.TLC_STAGE/zones/
)
FILES = ('{FILE_NAME}')
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_CSV')
ON_ERROR = ABORT_STATEMENT
FORCE = TRUE
"""

LOG_SQL = """
MERGE INTO RAW.INGESTION_LOG t
USING (SELECT %(f)s AS source_file) s ON t.source_file = s.source_file
WHEN MATCHED THEN UPDATE SET dataset = 'taxi_zone_lookup', source_url = %(url)s, etag = %(etag)s,
    content_length = %(len)s, source_last_modified = %(lm)s, file_rows = %(rows)s, rows_loaded = %(rows)s,
    status = 'LOADED', message = 'ok', attempts = COALESCE(t.attempts, 0) + 1, updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (source_file, dataset, source_url, etag, content_length, source_last_modified,
    file_rows, rows_loaded, status, message, attempts, updated_at)
VALUES (%(f)s, 'taxi_zone_lookup', %(url)s, %(etag)s, %(len)s, %(lm)s, %(rows)s, %(rows)s, 'LOADED', 'ok', 1,
    CURRENT_TIMESTAMP())
"""


def run(settings: Settings) -> int:
    remote = tlc.head(ZONES_URL)
    if not remote.available:
        raise SystemExit(f"No se pudo acceder a {ZONES_URL} (HTTP {remote.status_code}).")

    with tempfile.TemporaryDirectory(prefix="zones_") as tmp:
        local = tlc.download(ZONES_URL, Path(tmp) / FILE_NAME)
        with open(local, newline="", encoding="utf-8") as fh:
            file_rows = sum(1 for _ in csv.reader(fh)) - 1  # sin encabezado

        conn = sf.connect(settings)
        try:
            sf.execute(conn, "USE SCHEMA RAW")
            sf.execute(conn, f"PUT 'file://{local.as_posix()}' @RAW.TLC_STAGE/zones "
                             "AUTO_COMPRESS = FALSE OVERWRITE = TRUE")
            sf.execute(conn, "BEGIN")
            try:
                sf.execute(conn, "DELETE FROM RAW.TAXI_ZONE_LOOKUP")
                result = sf.execute(conn, COPY_SQL)
                rows_loaded = sum(int(r[3]) for r in result if len(r) > 3 and str(r[3]).isdigit())
                if rows_loaded != file_rows:
                    raise RuntimeError(f"Se cargaron {rows_loaded} zonas pero el archivo tiene {file_rows}")
                sf.execute(conn, LOG_SQL, {"f": FILE_NAME, "url": ZONES_URL, "etag": remote.etag,
                                           "len": remote.content_length, "lm": remote.last_modified,
                                           "rows": rows_loaded})
                sf.execute(conn, "COMMIT")
            except Exception:
                sf.execute(conn, "ROLLBACK")
                raise
        finally:
            conn.close()

    log.info("Zonas de taxi cargadas: %d filas en RAW.TAXI_ZONE_LOOKUP", rows_loaded)
    return rows_loaded