"""Descarga de archivos publicados por la NYC TLC (con reintentos)."""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from pathlib import Path

import requests

log = logging.getLogger(__name__)
USER_AGENT = "nyc-taxi-lab/1.0 (laboratorio academico)"
NOT_PUBLISHED = {403, 404}   # así responde el servidor cuando el mes aún no está publicado


@dataclass(frozen=True)
class RemoteFile:
    url: str
    available: bool
    status_code: int
    etag: str = ""
    content_length: int = 0
    last_modified: str = ""


def _retry(fn, what: str, attempts: int = 4):
    for attempt in range(1, attempts + 1):
        try:
            return fn()
        except (requests.ConnectionError, requests.Timeout, requests.HTTPError) as exc:
            if attempt == attempts:
                raise
            wait = 5 * attempt
            log.warning("Fallo al %s (intento %d/%d): %s. Reintento en %ds...", what, attempt, attempts, exc, wait)
            time.sleep(wait)


def head(url: str) -> RemoteFile:
    """Pregunta si el archivo existe y obtiene su huella (ETag) y tamaño, sin descargarlo."""
    def _do():
        resp = requests.head(url, allow_redirects=True, timeout=30, headers={"User-Agent": USER_AGENT})
        if resp.status_code in NOT_PUBLISHED:
            return RemoteFile(url=url, available=False, status_code=resp.status_code)
        resp.raise_for_status()
        return RemoteFile(url=url, available=True, status_code=resp.status_code,
                          etag=resp.headers.get("ETag", "").strip('"'),
                          content_length=int(resp.headers.get("Content-Length", 0) or 0),
                          last_modified=resp.headers.get("Last-Modified", ""))
    return _retry(_do, f"consultar {url}")


def download(url: str, dest: Path, expected_size: int = 0) -> Path:
    """Descarga en bloques (no carga el archivo completo en memoria)."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")

    def _do():
        started = time.time()
        with requests.get(url, stream=True, timeout=(15, 300), headers={"User-Agent": USER_AGENT}) as resp:
            resp.raise_for_status()
            with open(tmp, "wb") as fh:
                for chunk in resp.iter_content(chunk_size=8 * 1024 * 1024):
                    fh.write(chunk)
        size = tmp.stat().st_size
        if expected_size and size != expected_size:
            raise requests.HTTPError(f"descarga incompleta: {size} de {expected_size} bytes")
        tmp.replace(dest)
        log.info("Descargado %s (%.1f MB en %.0fs)", dest.name, size / 1e6, time.time() - started)
        return dest

    return _retry(_do, f"descargar {url}")