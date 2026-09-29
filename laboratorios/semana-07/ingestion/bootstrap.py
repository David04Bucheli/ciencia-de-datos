"""Crea (si no existen) warehouse, base, esquemas y objetos RAW ejecutando infra/snowflake/*.sql."""
from __future__ import annotations

import logging
from pathlib import Path

from snowflake.connector.errors import ProgrammingError

from . import snowflake_client as sf
from .config import Settings

log = logging.getLogger(__name__)
SQL_DIR = Path(__file__).resolve().parent.parent / "infra" / "snowflake"


def _render(path: Path, settings: Settings) -> str:
    text = path.read_text(encoding="utf-8")
    return (text.replace("${SNOWFLAKE_DATABASE}", settings.database)
                .replace("${SNOWFLAKE_WAREHOUSE}", settings.warehouse))


def _strip_comments(sql: str) -> str:
    return "\n".join(line for line in sql.splitlines() if not line.strip().startswith("--")).strip()


def _ensure(conn, kind: str, name: str, create_sql: str) -> None:
    """Crea el warehouse/base solo si no existe (funciona también con roles sin permiso de crear)."""
    if sf.execute(conn, f"SHOW {kind} LIKE %s", (name,)):
        log.info("%s ya existe: se reutiliza.", name)
        return
    try:
        sf.execute(conn, create_sql)
        log.info("%s creado.", name)
    except ProgrammingError as exc:
        raise SystemExit(f"No se pudo crear {name}: {exc.msg}. Tu rol no tiene permiso; "
                         "usa en .env uno que ya exista.") from exc


def run(settings: Settings) -> None:
    conn = sf.connect(settings, use_context=False)
    try:
        statements = [s.strip() for s in _render(SQL_DIR / "01_compute_and_database.sql", settings).split(";")]
        _ensure(conn, "WAREHOUSES", settings.warehouse,
                _strip_comments(next(s for s in statements if "CREATE WAREHOUSE" in s)))
        _ensure(conn, "DATABASES", settings.database,
                _strip_comments(next(s for s in statements if "CREATE DATABASE" in s)))
        sf.execute(conn, f"USE WAREHOUSE {settings.warehouse}")

        for name in ("02_schemas.sql", "03_raw_objects.sql"):
            log.info("Ejecutando infra/snowflake/%s", name)
            for cur in conn.execute_string(_render(SQL_DIR / name, settings), remove_comments=True):
                cur.close()
        log.info("Infraestructura lista: %s.{RAW, BRONZE, SILVER, GOLD}", settings.database)
    finally:
        conn.close()