#!/usr/bin/env python3
"""Genera el catálogo Dart de imágenes de ejercicios de Biblioteca (Coach Hub web).

Lee `docs/exercises_catalog.json` (429 ejercicios, curado por el usuario a
partir de Free Exercise DB — ver `MEDIA-SOURCES.md`) y emite un
`const Map<String, String>` Dart con SOLO las entradas de confianza alta:
`has_media == true` y `media_confidence == "high"`.

Cada entrada aporta DOS claves (name_es y name_en, normalizadas) apuntando a
la MISMA URL (la primera de `image_urls`) — así el resolver de la app
(`exercise_image_resolver.dart`) matchea sin importar en qué idioma llegue
`exercise.name`. Si dos ejercicios distintos normalizan a la misma clave, la
PRIMERA entrada del JSON gana (no se pisa silenciosamente).

Normalización de clave — DEBE ser idéntica a `_normalizeExerciseKey` en
`exercise_image_resolver.dart` (Dart): minúsculas, sin tildes/diacríticos
(vocales españolas + ñ/ç), espacios colapsados, trim. Mismo mapeo de
caracteres que `foldSearch` (lib/features/workout/application/exercise_filter.dart).

Uso:
    python scripts/generate_exercise_media_catalog.py

No requiere dependencias externas (stdlib únicamente).
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_JSON = REPO_ROOT / "docs" / "exercises_catalog.json"
OUTPUT_DART = (
    REPO_ROOT
    / "lib"
    / "features"
    / "coach_hub"
    / "presentation"
    / "sections"
    / "biblioteca"
    / "exercise_media_catalog.dart"
)

# Mismo mapeo que `foldSearch` (exercise_filter.dart) — mantener en paridad.
_FROM = "áàäâãéèëêíìïîóòöôõúùüûñç"
_TO = "aaaaaeeeeiiiiooooouuuunc"
_FOLD_TABLE = str.maketrans(_FROM, _TO)

_WHITESPACE_RE = re.compile(r"\s+")


def normalize_key(raw: str) -> str:
    """lowercase → sin tildes/diacríticos → espacios colapsados → trim."""
    folded = raw.lower().translate(_FOLD_TABLE)
    return _WHITESPACE_RE.sub(" ", folded).strip()


def escape_dart_single_quoted(s: str) -> str:
    """Escapa `'` y `\\` para un literal Dart entre comillas simples.

    (No hay apóstrofes/comillas en el catálogo actual — verificado — pero
    esto evita romper la regeneración si el catálogo fuente cambia.)
    """
    return s.replace("\\", "\\\\").replace("'", "\\'")


def build_catalog(exercises: list[dict]) -> dict[str, str]:
    catalog: dict[str, str] = {}
    for entry in exercises:
        if not entry.get("has_media") or entry.get("media_confidence") != "high":
            continue
        image_urls = entry.get("image_urls") or []
        if not image_urls:
            continue
        url = image_urls[0]
        for field in ("name_es", "name_en"):
            name = entry.get(field)
            if not name:
                continue
            key = normalize_key(name)
            if not key:
                continue
            catalog.setdefault(key, url)
    return catalog


def render_dart(catalog: dict[str, str], *, source_count: int) -> str:
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    lines = [
        "// GENERATED FILE — DO NOT EDIT BY HAND.",
        "//",
        "// Fuente: docs/exercises_catalog.json "
        f"({source_count} ejercicios totales; ver MEDIA-SOURCES.md).",
        "// Filtro: has_media == true && media_confidence == \"high\".",
        f"// Generado: {generated_at} (UTC)",
        f"// Entradas: {len(catalog)} (claves name_es + name_en, deduplicadas)",
        "// Regenerar: python scripts/generate_exercise_media_catalog.py",
        "library;",
        "",
        "/// Mapa clave-normalizada → URL de imagen de demostración del ejercicio.",
        "///",
        "/// Clave normalizada vía `_normalizeExerciseKey` en",
        "/// `exercise_image_resolver.dart` (minúsculas + sin tildes + espacios",
        "/// colapsados + trim) — NO usar este mapa directamente, usar",
        "/// `exerciseImageUrl(nombre)`.",
        "const Map<String, String> exerciseMediaCatalog = {",
    ]
    for key in sorted(catalog):
        url = catalog[key]
        lines.append(
            f"  '{escape_dart_single_quoted(key)}': "
            f"'{escape_dart_single_quoted(url)}',"
        )
    lines.append("};")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    data = json.loads(SOURCE_JSON.read_text(encoding="utf-8"))
    exercises = data["exercises"]
    catalog = build_catalog(exercises)
    dart_source = render_dart(catalog, source_count=len(exercises))
    # `newline=""` prevents Python from translating the `\n` we wrote into
    # `\r\n` on Windows — the generated file must stay LF like the rest of
    # the repo (git core.autocrlf handles the working-tree checkout, but we
    # don't want the generator itself to introduce CRLF into the blob).
    with open(OUTPUT_DART, "w", encoding="utf-8", newline="") as f:
        f.write(dart_source)
    print(
        f"OK: {len(catalog)} entradas escritas en "
        f"{OUTPUT_DART.relative_to(REPO_ROOT)} "
        f"(de {len(exercises)} ejercicios fuente)."
    )


if __name__ == "__main__":
    main()
