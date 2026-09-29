"""Genera un par de llaves RSA para que la tubería entre a Snowflake sin contraseña.

Crea en secrets/ (que NO se sube a GitHub): rsa_key.p8 (privada), rsa_key.pub (pública)
y alter_user.sql (para registrar la llave pública). Además escribe la llave privada en .env.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import re
import sys
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "secrets"
ENV_FILE = ROOT / ".env"


def read_env_value(name: str) -> str:
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        if line.startswith(name + "="):
            return line.split("=", 1)[1].strip()
    return ""


def write_env_values(values: dict[str, str]) -> None:
    """Reemplaza (o agrega) variables en .env sin tocar el resto del archivo."""
    with open(ENV_FILE, encoding="utf-8", newline="") as fh:   # conserva los saltos de línea de Windows
        text = fh.read()
    newline = "\r\n" if "\r\n" in text else "\n"
    for name, value in values.items():
        pattern = re.compile(rf"^{name}=[^\r\n]*", re.MULTILINE)
        line = f"{name}={value}"
        if pattern.search(text):
            text = pattern.sub(lambda _: line, text)
        else:
            text = text.rstrip("\r\n") + newline + line + newline
    with open(ENV_FILE, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--overwrite", action="store_true", help="reemplaza llaves existentes")
    args = parser.parse_args()

    if not ENV_FILE.exists():
        print("No encuentro el archivo .env. Créalo primero (paso 2).")
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    private_path = OUT_DIR / "rsa_key.p8"
    if private_path.exists() and not args.overwrite:
        print("Ya existe secrets/rsa_key.p8. Para crear otra llave agrega --overwrite "
              "(y vuelve a registrar la nueva llave pública en Snowflake).")
        return 1

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_der = key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                                    serialization.NoEncryption())
    private_pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                    serialization.NoEncryption())
    public_der = key.public_key().public_bytes(serialization.Encoding.DER,
                                               serialization.PublicFormat.SubjectPublicKeyInfo)
    public_pem = key.public_key().public_bytes(serialization.Encoding.PEM,
                                               serialization.PublicFormat.SubjectPublicKeyInfo)
    public_b64 = base64.b64encode(public_der).decode()
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(public_der).digest()).decode()

    private_path.write_bytes(private_pem)
    (OUT_DIR / "rsa_key.pub").write_bytes(public_pem)

    user = read_env_value("SNOWFLAKE_USER")
    target = user if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", user or "") else "<TU_USUARIO>"
    (OUT_DIR / "alter_user.sql").write_text(
        "-- Registra la llave publica en tu usuario de Snowflake (ejecutalo en una hoja SQL).\n"
        f"ALTER USER {target} SET RSA_PUBLIC_KEY = '{public_b64}';\n\n"
        "-- Comprobacion: en el resultado busca la fila RSA_PUBLIC_KEY_FP. Debe decir:\n"
        f"--   {fingerprint}\n"
        f"DESC USER {target};\n",
        encoding="utf-8",
    )

    write_env_values({
        "SNOWFLAKE_AUTH_METHOD": "keypair",
        "SNOWFLAKE_PRIVATE_KEY": base64.b64encode(private_der).decode(),
    })

    print("\nListo:")
    print("  - secrets/rsa_key.p8 y secrets/rsa_key.pub creados (NO se suben a GitHub)")
    print("  - Tu .env ya tiene SNOWFLAKE_PRIVATE_KEY y SNOWFLAKE_AUTH_METHOD=keypair")
    print("  - Siguiente: abre secrets/alter_user.sql y ejecútalo en Snowflake")
    print(f"\nHuella de tu llave pública: {fingerprint}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())