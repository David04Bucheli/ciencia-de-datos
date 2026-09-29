"""Lectura y validación de la configuración (variables de entorno del archivo .env)."""
from __future__ import annotations

import os
import re
from dataclasses import dataclass
from datetime import date

TLC_BASE_URL = "https://d37ci6vzurychx.cloudfront.net"
TRIP_URL_TEMPLATE = TLC_BASE_URL + "/trip-data/yellow_tripdata_{period}.parquet"
ZONES_URL = TLC_BASE_URL + "/misc/taxi_zone_lookup.csv"

# Columnas del diccionario de datos de la TLC (marzo 2025); sirven para detectar cambios de esquema.
EXPECTED_TRIP_COLUMNS = [
    "vendorid", "tpep_pickup_datetime", "tpep_dropoff_datetime", "passenger_count",
    "trip_distance", "ratecodeid", "store_and_fwd_flag", "pulocationid", "dolocationid",
    "payment_type", "fare_amount", "extra", "mta_tax", "tip_amount", "tolls_amount",
    "improvement_surcharge", "total_amount", "congestion_surcharge", "airport_fee",
    "cbd_congestion_fee",
]

_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")
_MONTH = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
AUTH_METHODS = ("keypair", "pat", "password")


class ConfigError(Exception):
    """Error de configuración con un mensaje entendible para el usuario."""


def _env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default if default is not None else "")
    return value.strip() if value else ""


def _identifier(name: str, value: str) -> str:
    if not _IDENTIFIER.match(value):
        raise ConfigError(f"{name}='{value}' no es un nombre válido de Snowflake "
                          "(solo letras, números y guion bajo).")
    return value.upper()


def _account(value: str) -> str:
    lowered = value.lower()
    if lowered.startswith("http") or "snowflakecomputing" in lowered:
        raise ConfigError(f"SNOWFLAKE_ACCOUNT='{value}' parece una URL. Escribe solo el "
                          "identificador, por ejemplo ABCDEFG-XY12345.")
    parts = value.split(".")
    if len(parts) == 2 and "-" not in parts[1]:
        raise ConfigError(f"SNOWFLAKE_ACCOUNT='{value}' usa un punto. Escríbelo con guion: "
                          f"{parts[0]}-{parts[1]}")
    return value


def parse_month(value: str, name: str = "mes") -> date:
    if not _MONTH.match(value or ""):
        raise ConfigError(f"{name}='{value}' debe tener el formato AAAA-MM, por ejemplo 2025-01.")
    year, month = value.split("-")
    return date(int(year), int(month), 1)


def month_range(start: str, end: str) -> list[str]:
    """Lista de meses AAAA-MM entre start y end, ambos incluidos."""
    first, last = parse_month(start, "inicio"), parse_month(end, "fin")
    if first > last:
        raise ConfigError(f"El mes inicial {start} es posterior al mes final {end}.")
    months, current = [], first
    while current <= last:
        months.append(current.strftime("%Y-%m"))
        current = date(current.year + (current.month // 12), current.month % 12 + 1, 1)
    return months


@dataclass(frozen=True)
class Settings:
    account: str
    user: str
    role: str
    warehouse: str
    database: str
    auth_method: str
    private_key: str
    private_key_passphrase: str
    token: str
    password: str
    start_month: str
    end_month: str

    @classmethod
    def from_env(cls) -> "Settings":
        missing = [n for n in ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER") if not _env(n) or _env(n).startswith("<")]
        if missing:
            raise ConfigError("Faltan variables en tu archivo .env: " + ", ".join(missing))
        auth = _env("SNOWFLAKE_AUTH_METHOD", "keypair").lower()
        if auth not in AUTH_METHODS:
            raise ConfigError(f"SNOWFLAKE_AUTH_METHOD debe ser uno de {AUTH_METHODS}, no '{auth}'.")
        settings = cls(
            account=_account(_env("SNOWFLAKE_ACCOUNT")),
            user=_env("SNOWFLAKE_USER"),
            role=_env("SNOWFLAKE_ROLE"),
            warehouse=_identifier("SNOWFLAKE_WAREHOUSE", _env("SNOWFLAKE_WAREHOUSE", "NYC_TAXI_WH")),
            database=_identifier("SNOWFLAKE_DATABASE", _env("SNOWFLAKE_DATABASE", "NYC_TAXI")),
            auth_method=auth,
            private_key=_env("SNOWFLAKE_PRIVATE_KEY"),
            private_key_passphrase=_env("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"),
            token=_env("SNOWFLAKE_TOKEN"),
            password=os.getenv("SNOWFLAKE_PASSWORD", ""),
            start_month=_env("TLC_START_MONTH", "2025-01"),
            end_month=_env("TLC_END_MONTH", "2026-08"),
        )
        if settings.role.startswith("<"):
            raise ConfigError("SNOWFLAKE_ROLE todavía tiene el valor de ejemplo.")
        if auth == "keypair" and not settings.private_key:
            raise ConfigError("SNOWFLAKE_PRIVATE_KEY está vacío. Genera la llave con scripts/generate_keypair.py.")
        if auth == "pat" and not settings.token:
            raise ConfigError("SNOWFLAKE_AUTH_METHOD=pat pero SNOWFLAKE_TOKEN está vacío.")
        if auth == "password" and not settings.password:
            raise ConfigError("SNOWFLAKE_AUTH_METHOD=password pero SNOWFLAKE_PASSWORD está vacío.")
        month_range(settings.start_month, settings.end_month)  # valida el formato de los meses
        return settings