"""Conexión a Snowflake con el método de autenticación elegido en el .env."""
from __future__ import annotations

import base64
import logging

import snowflake.connector
from cryptography.hazmat.primitives import serialization

from .config import Settings

log = logging.getLogger(__name__)
QUERY_TAG = "nyc_taxi_lab_ingestion"   # etiqueta para reconocer nuestras consultas en Snowflake


def load_private_key_der(private_key: str, passphrase: str = "") -> bytes:
    """Convierte la llave del .env (una línea base64 o un PEM) al formato que pide el conector."""
    password = passphrase.encode() if passphrase else None
    text = private_key.strip().strip('"').strip("'")
    if text.startswith("-----BEGIN"):
        key = serialization.load_pem_private_key(text.replace("\\n", "\n").encode(), password=password)
    else:
        key = serialization.load_der_private_key(base64.b64decode(text), password=password)
    return key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                             serialization.NoEncryption())


def connect(settings: Settings, use_context: bool = True):
    """Abre una conexión. Con use_context=False no fija warehouse/base (útil antes de crearlos)."""
    params = {
        "account": settings.account,
        "user": settings.user,
        "application": "nyc_taxi_lab",
        "session_parameters": {"QUERY_TAG": QUERY_TAG},
        "login_timeout": 60,
    }
    if settings.role:
        params["role"] = settings.role
    if use_context:
        params["warehouse"] = settings.warehouse
        params["database"] = settings.database

    if settings.auth_method == "keypair":
        params["private_key"] = load_private_key_der(settings.private_key, settings.private_key_passphrase)
    elif settings.auth_method == "pat":
        params["authenticator"] = "PROGRAMMATIC_ACCESS_TOKEN"
        params["token"] = settings.token
    else:
        params["password"] = settings.password

    log.info("Conectando a Snowflake (cuenta %s, usuario %s)...", settings.account, settings.user)
    return snowflake.connector.connect(**params)


def fetch_one(conn, sql: str, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def fetch_all_dict(conn, sql: str, params=None) -> list[dict]:
    with conn.cursor(snowflake.connector.DictCursor) as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def execute(conn, sql: str, params=None) -> list:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        try:
            return cur.fetchall()
        except snowflake.connector.errors.InterfaceError:
            return []