"""Carga idempotente de los archivos mensuales de Yellow Taxi en RAW.YELLOW_TRIPDATA.

Por cada mes:
  1. Pregunta al servidor de la TLC si el archivo existe y cuál es su huella (ETag).
  2. Si ya se cargó ese mismo archivo (misma huella y mismas filas), lo salta.
  3. Si no: lo descarga, lo sube al stage interno (copia del original en Snowflake) y,
     dentro de una transacción, BORRA las filas previas de ese archivo y lo vuelve a
     cargar con COPY INTO. Así una re-ejecución nunca duplica filas.
  4. Verifica que Snowflake cargó exactamente las filas que dice el archivo.
  5. Registra el resultado en RAW.INGESTION_LOG.
"""
from __future__ import annotations

import json
import logging
import tempfile
from dataclasses import dataclass
from pathlib import Path

import pyarrow.parquet as pq

from . import snowflake_client as sf
from . import tlc
from .config import EXPECTED_TRIP_COLUMNS, TRIP_URL_TEMPLATE, Settings, month_range

log = logging.getLogger(__name__)
STAGE_DIR = "@RAW.TLC_STAGE/yellow"

COPY_SQL = """
COPY INTO RAW.YELLOW_TRIPDATA
FROM @RAW.TLC_STAGE/yellow/
FILES = ('{file_name}')
FILE_FORMAT = (FORMAT_NAME = 'RAW.FF_PARQUET')
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
INCLUDE_METADATA = (
    _SOURCE_FILE = METADATA$FILENAME,
    _FILE_ROW_NUMBER = METADATA$FILE_ROW_NUMBER,
    _FILE_LAST_MODIFIED = METADATA$FILE_LAST_MODIFIED,
    _LOADED_AT = METADATA$START_SCAN_TIME
)
ON_ERROR = ABORT_STATEMENT
FORCE = TRUE
"""

MERGE_LOG_SQL = """
MERGE INTO RAW.INGESTION_LOG t
USING (SELECT %(source_file)s AS source_file) s
ON t.source_file = s.source_file
WHEN MATCHED THEN UPDATE SET
    dataset = %(dataset)s, source_period = TO_DATE(%(period)s || '-01'), source_url = %(url)s,
    etag = %(etag)s, content_length = %(content_length)s, source_last_modified = %(last_modified)s,
    file_rows = %(file_rows)s, rows_loaded = %(rows_loaded)s, source_columns = %(columns)s,
    status = %(status)s, message = %(message)s,
    attempts = COALESCE(t.attempts, 0) + 1, updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
    source_file, dataset, source_period, source_url, etag, content_length, source_last_modified,
    file_rows, rows_loaded, source_columns, status, message, attempts, updated_at
) VALUES (
    %(source_file)s, %(dataset)s, TO_DATE(%(period)s || '-01'), %(url)s, %(etag)s, %(content_length)s,
    %(last_modified)s, %(file_rows)s, %(rows_loaded)s, %(columns)s, %(status)s, %(message)s, 1,
    CURRENT_TIMESTAMP()
)
"""


@dataclass
class MonthResult:
    period: str
    status: str          # LOADED | SKIPPED | NOT_AVAILABLE | FAILED
    rows: int = 0
    message: str = ""


def _log_state(conn, *, file_name, period, url, status, message="", remote=None,
               file_rows=None, rows_loaded=None, columns=None):
    sf.execute(conn, MERGE_LOG_SQL, {
        "source_file": file_name, "dataset": "yellow_tripdata", "period": period, "url": url,
        "etag": remote.etag if remote else None,
        "content_length": remote.content_length if remote else None,
        "last_modified": remote.last_modified if remote else None,
        "file_rows": file_rows, "rows_loaded": rows_loaded,
        "columns": ",".join(columns) if columns else None,
        "status": status, "message": message[:2000] if message else None,
    })


def _previous_state(conn, file_name: str) -> dict | None:
    rows = sf.fetch_all_dict(conn, "SELECT * FROM RAW.INGESTION_LOG WHERE source_file = %s", (file_name,))
    return rows[0] if rows else None


def _rows_in_raw(conn, file_name: str) -> int:
    row = sf.fetch_one(conn, "SELECT COUNT(*) FROM RAW.YELLOW_TRIPDATA WHERE ENDSWITH(_SOURCE_FILE, %s)",
                       ("/" + file_name,))
    return int(row[0])


def _check_schema(file_name: str, columns: list[str]) -> None:
    """Avisa si la TLC cambió las columnas del archivo (schema drift)."""
    present = {c.lower() for c in columns}
    missing = [c for c in EXPECTED_TRIP_COLUMNS if c not in present]
    extra = [c for c in columns if c.lower() not in EXPECTED_TRIP_COLUMNS]
    if missing:
        log.warning("%s: faltan columnas esperadas %s (se cargarán como NULL).", file_name, missing)
    if extra:
        log.warning("%s: columnas nuevas no previstas %s (no se cargan).", file_name, extra)


def load_month(conn, period: str, workdir: Path, force: bool) -> MonthResult:
    file_name = f"yellow_tripdata_{period}.parquet"
    url = TRIP_URL_TEMPLATE.format(period=period)

    remote = tlc.head(url)
    if not remote.available:
        previous = _previous_state(conn, file_name)
        if previous and previous["STATUS"] == "LOADED":
            return MonthResult(period, "SKIPPED", previous["ROWS_LOADED"] or 0,
                               f"servidor respondió {remote.status_code}; se conserva la carga previa")
        _log_state(conn, file_name=file_name, period=period, url=url, status="NOT_AVAILABLE",
                   message=f"HTTP {remote.status_code}: la TLC aún no publica este mes")
        return MonthResult(period, "NOT_AVAILABLE", 0, f"HTTP {remote.status_code}")

    previous = _previous_state(conn, file_name)
    if (not force and previous and previous["STATUS"] == "LOADED"
            and previous["ETAG"] == remote.etag
            and int(previous["CONTENT_LENGTH"] or 0) == remote.content_length):
        rows_now = _rows_in_raw(conn, file_name)
        if rows_now == int(previous["ROWS_LOADED"] or -1):
            return MonthResult(period, "SKIPPED", rows_now, "sin cambios desde la última carga")
        log.warning("%s: RAW tiene %s filas pero la bitácora dice %s; se recarga.",
                    file_name, rows_now, previous["ROWS_LOADED"])

    local = workdir / file_name
    try:
        tlc.download(url, local, remote.content_length)
        metadata = pq.read_metadata(local)       # solo lee el pie del archivo, no los datos
        file_rows = metadata.num_rows
        columns = [metadata.schema.column(i).name for i in range(metadata.num_columns)]
        _check_schema(file_name, columns)

        # Copia del archivo ORIGINAL al stage interno de Snowflake
        sf.execute(conn, f"PUT 'file://{local.as_posix()}' {STAGE_DIR} "
                         "AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 4")

        # Reemplazo atómico de las filas de ESTE archivo (idempotencia)
        sf.execute(conn, "BEGIN")
        try:
            deleted = sf.execute(conn, "DELETE FROM RAW.YELLOW_TRIPDATA WHERE ENDSWITH(_SOURCE_FILE, %s)",
                                 ("/" + file_name,))
            copy_rows = sf.execute(conn, COPY_SQL.format(file_name=file_name))
            rows_loaded = sum(int(r[3]) for r in copy_rows if len(r) > 3 and str(r[3]).isdigit())
            if rows_loaded != file_rows:
                raise RuntimeError(f"Snowflake cargó {rows_loaded} filas pero el archivo tiene {file_rows}")
            _log_state(conn, file_name=file_name, period=period, url=url, status="LOADED",
                       message="ok", remote=remote, file_rows=file_rows, rows_loaded=rows_loaded,
                       columns=columns)
            sf.execute(conn, "COMMIT")
        except Exception:
            sf.execute(conn, "ROLLBACK")
            raise
        replaced = int(deleted[0][0]) if deleted else 0
        note = f"reemplazó {replaced:,} filas previas" if replaced else "carga nueva"
        return MonthResult(period, "LOADED", rows_loaded, note)
    except Exception as exc:  # se registra el fallo y se sigue con el siguiente mes
        log.exception("Error cargando %s", file_name)
        _log_state(conn, file_name=file_name, period=period, url=url, status="FAILED",
                   message=str(exc), remote=remote)
        return MonthResult(period, "FAILED", 0, str(exc)[:200])
    finally:
        local.unlink(missing_ok=True)


def run(settings: Settings, start: str | None = None, end: str | None = None,
        force: bool = False, fail_on_missing: bool = False) -> list[MonthResult]:
    months = month_range(start or settings.start_month, end or settings.end_month)
    log.info("Meses a procesar: %s a %s (%d meses)%s", months[0], months[-1], len(months),
             " [recarga forzada]" if force else "")
    results: list[MonthResult] = []
    conn = sf.connect(settings)
    try:
        sf.execute(conn, "USE SCHEMA RAW")
        with tempfile.TemporaryDirectory(prefix="tlc_") as tmp:
            for period in months:
                result = load_month(conn, period, Path(tmp), force)
                results.append(result)
                log.info("%s -> %-13s %12s filas  %s", period, result.status, f"{result.rows:,}", result.message)
    finally:
        conn.close()

    _print_summary(results)
    failed = [r.period for r in results if r.status == "FAILED"]
    missing = [r.period for r in results if r.status == "NOT_AVAILABLE"]
    if failed:
        raise SystemExit(f"Fallaron {len(failed)} meses: {failed}. Revisa el log y vuelve a ejecutar.")
    if missing and fail_on_missing:
        raise SystemExit(f"Meses aún no publicados por la TLC: {missing}")
    return results


def _print_summary(results: list[MonthResult]) -> None:
    counts = {s: sum(1 for r in results if r.status == s) for s in ("LOADED", "SKIPPED", "NOT_AVAILABLE", "FAILED")}
    total_rows = sum(r.rows for r in results if r.status in ("LOADED", "SKIPPED"))
    missing = [r.period for r in results if r.status == "NOT_AVAILABLE"]
    log.info("=" * 70)
    log.info("RESUMEN: %d cargados, %d sin cambios, %d no publicados, %d con error | %s filas en RAW",
             counts["LOADED"], counts["SKIPPED"], counts["NOT_AVAILABLE"], counts["FAILED"], f"{total_rows:,}")
    if missing:
        log.warning("Meses que la TLC todavía no publica (se cargarán en la próxima ejecución): %s", missing)
    log.info("=" * 70)
    # Línea especial que Kestra convierte en "outputs" de la tarea (paso 9)
    print("::" + json.dumps({"outputs": {
        "months_loaded": counts["LOADED"], "months_unchanged": counts["SKIPPED"],
        "months_not_available": counts["NOT_AVAILABLE"], "months_failed": counts["FAILED"],
        "missing_months": ",".join(missing), "raw_rows": total_rows,
    }}) + "::")