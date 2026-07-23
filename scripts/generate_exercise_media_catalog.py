#!/usr/bin/env python3
"""Genera el catálogo Dart de imágenes de ejercicios de Biblioteca (Coach Hub web).

Lee `docs/exercises_catalog.json` (429 ejercicios, curado por el usuario a
partir de Free Exercise DB — ver `MEDIA-SOURCES.md`) y emite DOS
`const Map<String, String>` Dart, ambos con entradas `has_media == true` y
`media_confidence` en `{"high", "medium"}` (low/none quedan afuera — riesgo
de imagen equivocada):

1. `exerciseMediaCatalog` — mapa EXACTO: cada entrada aporta DOS claves
   (name_es y name_en, normalizadas) apuntando a la MISMA URL (la primera de
   `image_urls`). Si dos ejercicios distintos normalizan a la misma clave,
   gana la entrada `high` (se procesan primero); entre high o entre medium,
   gana la PRIMERA del JSON (no se pisa silenciosamente).
2. `exerciseMediaBaseCatalog` — mapa de FALLBACK por "nombre base" (nombre
   sin el sufijo de equipamiento entre paréntesis, ej. "Sentadilla (Barra)"
   → "sentadilla"), SOLO para bases INEQUÍVOCAS: bases para las que existe
   EXACTAMENTE UN ejercicio del catálogo (entre high+medium, contando
   name_es y name_en). Si 2+ ejercicios distintos comparten la misma base
   (ej. "Curl de Bíceps (Barra)" / "(Mancuerna)" / "(Polea)"...), la base
   queda AMBIGUA y se excluye — nunca se muestra una imagen que podría
   corresponder al equipamiento equivocado. Bases que ya son una clave del
   mapa exacto se excluyen (no aportan valor, `exerciseImageUrl` ya las
   resuelve en el paso (a)).

Estos dos mapas alimentan el resolver de la app
(`exercise_image_resolver.dart`), que hace: (a) lookup exacto por nombre; si
falla y el nombre trae un sufijo `(...)`, (b) lookup de la base (nombre sin
ese sufijo) contra el mapa de fallback; si tampoco hay match, (c) `null`.
Esto cubre nombres de la Biblioteca con variantes de equipamiento que el
catálogo curado no tiene exactas (ej. Biblioteca "Press Arnold (Polea)" →
matchea la base inequívoca "press arnold" del catálogo, que solo tiene
`Press Arnold (Mancuerna)`).

Normalización de clave — DEBE ser idéntica a `_normalizeExerciseKey` en
`exercise_image_resolver.dart` (Dart): minúsculas, sin tildes/diacríticos
(vocales españolas + ñ/ç), espacios colapsados, trim. Mismo mapeo de
caracteres que `foldSearch` (lib/features/workout/application/exercise_filter.dart).
El sufijo de equipamiento removido para el nombre base es el último grupo
`(...)` al final del string (si lo hay).

Uso:
    python scripts/generate_exercise_media_catalog.py

No requiere dependencias externas (stdlib únicamente).
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
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
# Sufijo de equipamiento: un único grupo "(...)" pegado al final del string,
# con espacio opcional antes. Ej. "Sentadilla (Barra)" → base "Sentadilla".
_TRAILING_PAREN_RE = re.compile(r"\s*\([^)]*\)\s*$")

_INCLUDED_CONFIDENCE = ("high", "medium")


def normalize_key(raw: str) -> str:
    """lowercase → sin tildes/diacríticos → espacios colapsados → trim."""
    folded = raw.lower().translate(_FOLD_TABLE)
    return _WHITESPACE_RE.sub(" ", folded).strip()


def base_key(raw: str) -> str:
    """`normalize_key` tras remover un sufijo de equipamiento final "(...)".

    Si no hay sufijo, equivale a `normalize_key(raw)` (la clave base es el
    nombre completo).
    """
    without_suffix = _TRAILING_PAREN_RE.sub("", raw)
    return normalize_key(without_suffix)


def escape_dart_single_quoted(s: str) -> str:
    """Escapa `'` y `\\` para un literal Dart entre comillas simples.

    (No hay apóstrofes/comillas en el catálogo actual — verificado — pero
    esto evita romper la regeneración si el catálogo fuente cambia.)
    """
    return s.replace("\\", "\\\\").replace("'", "\\'")


def build_catalogs(exercises: list[dict]) -> tuple[dict[str, str], dict[str, str]]:
    """Devuelve `(exact_catalog, base_catalog)` — ver docstring del módulo."""
    included = [
        entry
        for entry in exercises
        if entry.get("has_media")
        and entry.get("media_confidence") in _INCLUDED_CONFIDENCE
    ]
    # `high` antes que `medium` así, en colisión de clave exacta, gana la
    # entrada de mayor confianza.
    included.sort(key=lambda e: _INCLUDED_CONFIDENCE.index(e["media_confidence"]))

    exact: dict[str, str] = {}
    for entry in included:
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
            exact.setdefault(key, url)

    # Bases candidatas: base normalizada → {índices de entradas que la
    # producen} — usado solo para detectar ambigüedad (2+ ejercicios
    # distintos comparten la misma base).
    base_candidates: dict[str, set[int]] = defaultdict(set)
    url_by_index: dict[int, str] = {}
    for idx, entry in enumerate(included):
        image_urls = entry.get("image_urls") or []
        if not image_urls:
            continue
        url_by_index[idx] = image_urls[0]
        for field in ("name_es", "name_en"):
            name = entry.get(field)
            if not name:
                continue
            base = base_key(name)
            if not base:
                continue
            base_candidates[base].add(idx)

    base_catalog: dict[str, str] = {}
    for base, indices in base_candidates.items():
        if base in exact:
            continue  # ya cubierto por el match exacto (paso a)
        if len(indices) != 1:
            continue  # ambigua: 2+ ejercicios distintos comparten esta base
        (idx,) = indices
        base_catalog[base] = url_by_index[idx]

    return exact, base_catalog


def render_dart(
    exact: dict[str, str],
    base_catalog: dict[str, str],
    *,
    source_count: int,
) -> str:
    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    lines = [
        "// GENERATED FILE — DO NOT EDIT BY HAND.",
        "//",
        "// Fuente: docs/exercises_catalog.json "
        f"({source_count} ejercicios totales; ver MEDIA-SOURCES.md).",
        "// Filtro: has_media == true && media_confidence in {\"high\", \"medium\"}.",
        f"// Generado: {generated_at} (UTC)",
        f"// Entradas exactas: {len(exact)} (claves name_es + name_en, deduplicadas)",
        f"// Entradas base (fallback de equipamiento, bases inequívocas): {len(base_catalog)}",
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
    for key in sorted(exact):
        url = exact[key]
        lines.append(
            f"  '{escape_dart_single_quoted(key)}': "
            f"'{escape_dart_single_quoted(url)}',"
        )
    lines.append("};")
    lines.append("")
    lines.extend(
        [
            "/// Fallback por nombre BASE (sin sufijo de equipamiento entre",
            "/// paréntesis) → URL, SOLO para bases inequívocas del catálogo (un único",
            "/// ejercicio fuente por base). Usado por `exerciseImageUrl` cuando el",
            "/// nombre de Biblioteca trae una variante de equipamiento",
            "/// (ej. \"Press Arnold (Polea)\") que no matchea exacto contra",
            "/// [exerciseMediaCatalog] pero cuya base (\"press arnold\") sí identifica",
            "/// un único ejercicio del catálogo curado — NO usar este mapa",
            "/// directamente, usar `exerciseImageUrl(nombre)`.",
            "const Map<String, String> exerciseMediaBaseCatalog = {",
        ]
    )
    for key in sorted(base_catalog):
        url = base_catalog[key]
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
    exact, base_catalog = build_catalogs(exercises)
    dart_source = render_dart(exact, base_catalog, source_count=len(exercises))
    # `newline=""` prevents Python from translating the `\n` we wrote into
    # `\r\n` on Windows — the generated file must stay LF like the rest of
    # the repo (git core.autocrlf handles the working-tree checkout, but we
    # don't want the generator itself to introduce CRLF into the blob).
    with open(OUTPUT_DART, "w", encoding="utf-8", newline="") as f:
        f.write(dart_source)
    print(
        f"OK: {len(exact)} entradas exactas + {len(base_catalog)} entradas "
        f"base escritas en {OUTPUT_DART.relative_to(REPO_ROOT)} "
        f"(de {len(exercises)} ejercicios fuente)."
    )


if __name__ == "__main__":
    main()
