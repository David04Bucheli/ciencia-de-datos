"""Prueba la conexión a Snowflake con los datos del .env y explica los errores comunes."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from ingestion import snowflake_client as sf  # noqa: E402
from ingestion.config import ConfigError, Settings  # noqa: E402

HINTS = {
    "JWT token is invalid": "La llave no está registrada en tu usuario o no coincide. "
                            "Ejecuta secrets/alter_user.sql en Snowflake y compara la huella.",
    "Incorrect username or password": "Usuario incorrecto. Revisa SNOWFLAKE_USER.",
    "MFA": "Tu usuario exige MFA para contraseñas. Usa SNOWFLAKE_AUTH_METHOD=keypair.",
    "Could not connect": "No se pudo llegar a Snowflake. Revisa SNOWFLAKE_ACCOUNT "
                         "(formato ORGANIZACION-CUENTA) y tu conexión a internet.",
    "Role": "El rol no existe o no está asignado a tu usuario. Revisa SNOWFLAKE_ROLE.",
}


def main() -> int:
    try:
        settings = Settings.from_env()
    except ConfigError as exc:
        print(f"\n[ERROR] Configuración: {exc}\n")
        return 2
    try:
        conn = sf.connect(settings, use_context=False)
    except Exception as exc:  # noqa: BLE001
        message = str(exc)
        print(f"\n[ERROR] No se pudo conectar:\n  {message}\n")
        for needle, hint in HINTS.items():
            if needle.lower() in message.lower():
                print(f"Sugerencia: {hint}\n")
                break
        return 1
    try:
        user, role, version = sf.fetch_one(conn, "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_VERSION()")
        print(f"\n[OK] Conexión exitosa a Snowflake  |  usuario: {user}  |  rol: {role}  |  versión: {version}\n")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())