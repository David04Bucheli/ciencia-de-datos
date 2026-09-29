"""Uso:
    python -m ingestion bootstrap   # crea warehouse, base, esquemas y tablas RAW
    python -m ingestion zones       # carga la tabla de zonas
    python -m ingestion trips       # carga los meses de TLC_START_MONTH a TLC_END_MONTH
    python -m ingestion trips --start 2025-01 --end 2025-03 --force-reload true
    python -m ingestion all         # bootstrap + zones + trips
"""
from __future__ import annotations

import argparse
import logging
import sys

from . import bootstrap, load_trips, load_zones
from .config import ConfigError, Settings


def _bool(value: str) -> bool:
    return str(value).strip().lower() in ("1", "true", "yes", "si", "sí", "y")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m ingestion")
    parser.add_argument("command", choices=["bootstrap", "zones", "trips", "all"])
    parser.add_argument("--start", help="Mes inicial AAAA-MM (por defecto TLC_START_MONTH)")
    parser.add_argument("--end", help="Mes final AAAA-MM (por defecto TLC_END_MONTH)")
    parser.add_argument("--force-reload", default="false", help="true = recarga aunque no haya cambios")
    parser.add_argument("--fail-on-missing", default="false", help="true = falla si falta algún mes")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, stream=sys.stdout,
                        format="%(asctime)s %(levelname)-7s %(message)s", datefmt="%H:%M:%S")
    logging.getLogger("snowflake.connector").setLevel(logging.WARNING)

    try:
        settings = Settings.from_env()
    except ConfigError as exc:
        logging.error("Configuración inválida: %s", exc)
        return 2

    if args.command in ("bootstrap", "all"):
        bootstrap.run(settings)
    if args.command in ("zones", "all"):
        load_zones.run(settings)
    if args.command in ("trips", "all"):
        load_trips.run(settings, start=args.start, end=args.end,
                       force=_bool(args.force_reload), fail_on_missing=_bool(args.fail_on_missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())