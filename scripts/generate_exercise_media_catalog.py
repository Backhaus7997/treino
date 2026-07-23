#!/usr/bin/env python3
"""Genera el catálogo Dart de imágenes de ejercicios de Biblioteca (Coach Hub web).

Lee DOS fuentes:
1. `docs/exercises_catalog.json` (429 ejercicios, curado por el usuario a
   partir de Free Exercise DB — ver `MEDIA-SOURCES.md`): `name_es`/`name_en`/
   `image_urls`/`has_media`/`media_confidence` por ejercicio.
2. `scripts/exercise_media_verified.json` (273 fotos `high`+`medium`
   verificadas VISUALMENTE, imagen por imagen, por agentes con visión IA el
   2026-07-23 — ver `_meta` dentro del archivo): listas `verified` (la foto
   SÍ corresponde al ejercicio), `wrong` (la foto NO corresponde — típico:
   una variante de equipamiento comparte por error la imagen base de OTRA
   variante) y `unsure`.

**La verificación visual manda sobre `media_confidence`**: el catálogo
generado incluye SOLO los ejercicios cuyo `name_es` está en `verified`,
sin importar si su `media_confidence` original era `high` o `medium` (las
listas `wrong`/`unsure` NUNCA se usan para incluir nada — se conservan en
`exercise_media_verified.json` íntegras solo para trazabilidad/auditoría).

Emite UN solo `const Map<String, String>` Dart (`exerciseMediaCatalog`):
cada ejercicio verificado aporta DOS claves (`name_es` y `name_en`,
normalizadas) apuntando a la MISMA URL (la primera de `image_urls`).

IMPORTANTE — sin fallback por variante de equipamiento: una ronda anterior
de este generador agregaba un mapa de "nombre base" (sin el sufijo de
equipamiento) como fallback para variantes no cubiertas exactas. La
verificación visual demostró que eso era INSEGURO — variantes de
equipamiento (ej. "Curl de Bíceps (Barra)" vs "(Mancuerna)" vs "(Polea)")
casi nunca pueden compartir imagen sin mostrar el equipamiento equivocado.
Ese fallback fue removido; el resolver (`exercise_image_resolver.dart`)
hace SOLO lookup exacto.

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
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_JSON = REPO_ROOT / "docs" / "exercises_catalog.json"
VERIFIED_JSON = REPO_ROOT / "scripts" / "exercise_media_verified.json"
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


def build_catalog(
    exercises: list[dict], verified_names: set[str]
) -> dict[str, str]:
    """Mapa clave-normalizada → URL, SOLO para `name_es` en `verified_names`."""
    catalog: dict[str, str] = {}
    for entry in exercises:
        if entry.get("name_es") not in verified_names:
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


def render_dart(catalog: dict[str, str], *, source_count: int, verified_count: int) -> str:
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    lines = [
        "// GENERATED FILE — DO NOT EDIT BY HAND.",
        "//",
        "// Fuente: docs/exercises_catalog.json "
        f"({source_count} ejercicios totales; ver MEDIA-SOURCES.md), filtrado por",
        "// scripts/exercise_media_verified.json (verificación VISUAL",
        "// imagen-por-imagen, no por media_confidence — ver su _meta).",
        f"// Filtro: name_es en la lista \"verified\" ({verified_count} ejercicios).",
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

    verified_data = json.loads(VERIFIED_JSON.read_text(encoding="utf-8"))
    verified_names = set(verified_data["verified"])

    catalog = build_catalog(exercises, verified_names)

    # Advertencia de mantenimiento: nombres en "verified" que no matchearon
    # ningún `name_es` real del catálogo (typos, notas mezcladas, etc.) — no
    # rompe la generación, pero silenciosamente los deja afuera.
    catalog_names = {e.get("name_es") for e in exercises}
    unmatched = sorted(verified_names - catalog_names)
    if unmatched:
        print(
            f"WARN: {len(unmatched)} nombre(s) de \"verified\" no matchean "
            "ningún name_es de docs/exercises_catalog.json (se ignoran):",
            file=sys.stderr,
        )
        for name in unmatched:
            print(f"  - {name!r}", file=sys.stderr)

    dart_source = render_dart(
        catalog, source_count=len(exercises), verified_count=len(verified_names)
    )
    # `newline=""` prevents Python from translating the `\n` we wrote into
    # `\r\n` on Windows — the generated file must stay LF like the rest of
    # the repo (git core.autocrlf handles the working-tree checkout, but we
    # don't want the generator itself to introduce CRLF into the blob).
    with open(OUTPUT_DART, "w", encoding="utf-8", newline="") as f:
        f.write(dart_source)
    print(
        f"OK: {len(catalog)} entradas escritas en "
        f"{OUTPUT_DART.relative_to(REPO_ROOT)} "
        f"(de {len(verified_names)} ejercicios verificados visualmente, "
        f"{len(exercises)} en el catálogo fuente)."
    )


if __name__ == "__main__":
    main()
