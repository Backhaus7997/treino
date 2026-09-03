#!/usr/bin/env python3
"""Genera los documentos legales publicables a partir de `docs/legal/*.md`.

FUENTE UNICA: el markdown de `docs/legal/`. Todo lo demas se genera.

    python3 scripts/build_legal_content.py            # genera
    python3 scripts/build_legal_content.py --check    # CI: falla si hay drift
    python3 scripts/build_legal_content.py --preview  # genera todo bajo build/

Salida:
  • lib/features/auth/presentation/legal/legal_content.dart

ESTE ES EL PRIMER ESLABON DE UNA CADENA DE DOS:

    docs/legal/*.md  ->  legal_content.dart  ->  web/legal/*.html
      (este script)         (eslabon)         (tool/build_legal_pages.dart)

El segundo eslabon lo hizo otra rama (PR #941) y renderiza las paginas publicas
que sirven las tiendas. Por eso este script NO emite HTML: seria una segunda
salida web compitiendo con la de `tool/build_legal_pages.dart`, que ademas viaja
sola con `flutter build web`. Cada eslabon tiene su guarda propia: el gate de
`ci.yml` compara markdown contra Dart, y `test/legal/paginas_legales_sync_test`
compara Dart contra HTML.

Despues de correr este script hay que correr el otro:

    dart run tool/build_legal_pages.dart

Por que existe: el mismo texto legal vive en la app y en el sitio, que ademas
esta en otro repositorio. Mantener copias a mano es como se desincronizo el
"Quick reference" de CLAUDE.md (ver AGENTS.md). Con texto legal el costo es
peor: si la app y el sitio dicen cosas distintas, no hay forma de probar que
acepto el usuario. Mismo patron que freezed: se edita la fuente, se corre el
generador, los archivos generados NO se tocan a mano.

Convenciones en cada .md publicable:

    <!-- treino-legal
    slug: privacidad
    title: Politica de Privacidad
    dart: kPrivacySections
    -->

  • Lo publicable arranca en `<!-- publish:start -->`, o si no hay marcador,
    en el primer encabezado `## `.
  • `<!-- publish:end -->` corta: lo que sigue es interno (anexos, specs).
  • Un `.md` sin bloque `treino-legal` se ignora por completo.

GATE DE PENDIENTES: si el texto publicable conserva marcadores `[[...]]`, el
generador ABORTA. Es deliberado — evita que un "[[PENDIENTE: sede social]]"
llegue a un usuario. `--allow-pending` lo saltea, solo para previsualizar.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "legal"
DART_OUT = ROOT / "lib/features/auth/presentation/legal/legal_content.dart"
WEB_OUT = ROOT / "build" / "legal-web"

CONTACT_EMAIL = "[[PENDIENTE]]"   # se sobreescribe desde aviso-legal.md
SITE = "gettreino.com"

BANNER_DART = (
    "// GENERADO POR scripts/build_legal_content.py — NO EDITAR A MANO.\n"
    "//\n"
    "// La fuente son los markdown de `docs/legal/`. Para cambiar un texto\n"
    "// legal se edita el .md y se corre:\n"
    "//\n"
    "//     python3 scripts/build_legal_content.py\n"
    "//\n"
    "// Editar este archivo directamente hace que la app y el sitio digan\n"
    "// cosas distintas, y entonces no hay forma de probar que acepto el\n"
    "// usuario. Ver AGENTS.md y docs/legal/README.md.\n"
)


# ----------------------------------------------------------------- parsing
FM_RE = re.compile(r"<!--\s*treino-legal\s*(.*?)-->", re.S)
FENCE_RE = re.compile(r"^```.*?^```", re.S | re.M)


def strip_fences(text: str) -> str:
    """Saca los bloques de codigo.

    Sin esto, documentar la convencion en un README —con un bloque de ejemplo
    que muestra el front matter— hace que el parser lo lea como front matter
    de verdad. Paso exactamente eso.
    """
    return FENCE_RE.sub("", text)


def front_matter(text: str) -> dict[str, str] | None:
    m = FM_RE.search(strip_fences(text))
    if not m:
        return None
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = v.strip()
    return out or None


def publishable(text: str) -> str:
    """De `<!-- publish:start -->` (o el primer `## `) a `<!-- publish:end -->`.

    Sin marcadores, publica de la primera seccion al final: sirve para los
    documentos que son 100% texto de usuario. Los que traen anexo o
    especificacion interna necesitan el `end`; los que traen preambulo para el
    equipo, el `start`.
    """
    end = text.find("<!-- publish:end -->")
    if end != -1:
        text = text[:end]
    start = text.find("<!-- publish:start -->")
    if start != -1:
        return text[start + len("<!-- publish:start -->"):]
    m = re.search(r"^## ", text, re.M)
    return text[m.start():] if m else ""


def inline(s: str) -> str:
    """Markdown inline -> texto plano. El widget Text no renderiza markup."""
    s = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", s)          # imagenes
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)      # links -> su texto
    s = re.sub(r"\*\*([^*]+)\*\*", r"\1", s)            # negrita
    s = re.sub(r"(?<!\w)\*([^*]+)\*(?!\w)", r"\1", s)   # cursiva
    s = re.sub(r"`([^`]+)`", r"\1", s)                  # codigo
    s = s.replace("&nbsp;", " ").replace("<br/>", " ").replace("<br>", " ")
    return re.sub(r"[ \t]+", " ", s).strip()


def flatten_table(rows: list[str]) -> list[str]:
    """Tabla markdown -> lineas legibles. Dos columnas quedan `a: b`."""
    cells = [[inline(c) for c in r.strip().strip("|").split("|")] for r in rows]
    cells = [c for c in cells if not all(re.fullmatch(r":?-{2,}:?", x or "-")
                                         for x in c)]
    if not cells:
        return []
    header, body = cells[0], cells[1:]
    if not body:
        return []
    out = []
    for row in body:
        if len(row) == 2:
            left, right = row
            out.append(f"• {left}: {right}" if left else f"• {right}")
        else:
            parts = [f"{h}: {v}" for h, v in zip(header, row) if v and h]
            out.append("• " + " — ".join(parts) if parts
                       else "• " + " — ".join(x for x in row if x))
    return out


def to_sections(md: str) -> list[tuple[str, str]]:
    """Markdown publicable -> [(heading, body plano)].

    Clave: un bloque (parrafo o item de lista) puede ocupar VARIAS lineas del
    markdown. Hay que acumularlas y recien despues aplicar `inline()`, porque
    un `**negrita**` partido entre dos lineas no matchea si se procesa linea
    por linea — y el `**` terminaba visible en la app.
    """
    sections: list[tuple[str, str]] = []
    heading: str | None = None
    blocks: list[str] = []    # bloques ya cerrados, ya en texto plano
    cur: list[str] = []       # lineas crudas del bloque en curso
    bullet = False            # el bloque en curso es un item de lista
    fenced = False            # dentro de un bloque de codigo
    table: list[str] = []

    def close_block():
        nonlocal bullet
        if cur:
            text = inline(" ".join(cur))
            if text:
                blocks.append(("• " + text) if bullet else text)
            cur.clear()
        bullet = False

    def close_table():
        if table:
            close_block()
            blocks.extend(flatten_table(table))
            table.clear()

    def close_section():
        close_table()
        close_block()
        if heading is not None and blocks:
            body = "\n\n".join(blocks)
            # los items de lista van pegados entre si, no separados por parrafo
            body = re.sub(r"\n\n(?=• )", "\n", body)
            sections.append((heading, body.strip()))
        blocks.clear()

    for raw in md.splitlines():
        line = raw.rstrip()

        if line.startswith("## ") and not fenced:
            close_section()
            heading = inline(line[3:]).upper()
            continue
        if heading is None:
            continue

        if line.startswith("|"):
            close_block()
            table.append(line)
            continue
        close_table()

        if not line.strip():
            close_block()
            continue
        if line.startswith("---") or line.startswith("<!--"):
            close_block()
            continue
        if line.startswith("```"):
            close_block()
            fenced = not fenced
            continue
        if fenced:
            continue
        if line.startswith("### ") or line.startswith("#### "):
            close_block()
            blocks.append(inline(line.lstrip("#").strip()))
            continue

        m_ul = re.match(r"^\s*[-*]\s+(.*)$", line)
        m_ol = re.match(r"^\s*\d+\.\s+(.*)$", line)
        if m_ul or m_ol:
            close_block()
            bullet = True
            cur.append((m_ul or m_ol).group(1))
            continue

        if line.startswith("> "):
            line = line[2:]

        # Cualquier otra linea continua el bloque en curso — sea parrafo o
        # item de lista envuelto.
        cur.append(line.strip())

    close_section()
    return sections


# ------------------------------------------------------------------ emisores
def dart_str(s: str) -> str:
    """Literal Dart de una linea. El `$` va escapado o Dart interpola."""
    s = s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
    return f"'{s}'"


def dart_body(body: str) -> str:
    """Cuerpo multilinea como literales concatenados, legibles en el diff."""
    parts = []
    for i, line in enumerate(body.split("\n")):
        nl = "\\n" if i < len(body.split("\n")) - 1 else ""
        payload = line.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
        parts.append(f"        '{payload}{nl}'")
    return "\n".join(parts)


def dart_format(path: Path) -> None:
    """Pasa `dart format` sobre la salida.

    El gate de calidad de AGENTS.md corre `dart format .`, asi que si el
    generador emitiera codigo sin formatear, el formateador lo tocaria despues
    y `--check` reportaria desfasaje para siempre. Formatear aca deja la salida
    estable.
    """
    if not shutil.which("dart"):
        print("[!] `dart` no esta en PATH: salida sin formatear.",
              file=sys.stderr)
        return
    subprocess.run(["dart", "format", str(path)],
                   check=False, capture_output=True)


def emit_dart(docs: list[dict]) -> str:
    out = [BANNER_DART, "library;", "", "/// Una seccion de un documento legal: encabezado + cuerpo.",
           "class LegalSection {", "  const LegalSection(this.heading, this.body);",
           "", "  final String heading;", "  final String body;", "}", ""]
    # Fecha POR DOCUMENTO. Los Terminos y la Politica se revisan por separado,
    # asi que una fecha global mentiria sobre uno de los dos (#941).
    for d in docs:
        out.append(f"/// Ultima revision de {d['title']}.")
        out.append(f"const String {d['date_const']} = {dart_str(d['updated'])};")
    out.append("")
    out.append("/// Email de contacto para consultas legales / de privacidad.")
    out.append(f"const String kLegalContactEmail = {dart_str(CONTACT_EMAIL)};")
    out.append("")
    for d in docs:
        out.append(f"/// {d['title']}.")
        out.append(f"/// Fuente: docs/legal/{d['file']}")
        out.append(f"const List<LegalSection> {d['dart']} = <LegalSection>[")
        for heading, body in d["sections"]:
            out.append("  LegalSection(")
            out.append(f"    {dart_str(heading)},")
            out.append(dart_body(body) + ",")
            out.append("  ),")
        out.append("];")
        out.append("")
    # indice para la pantalla Perfil -> Legales
    out.append("/// Una entrada del indice de documentos legales.")
    out.append("typedef LegalDocumentEntry = ({")
    out.append("  String title,")
    out.append("  List<LegalSection> sections,")
    out.append("  String lastUpdated,")
    out.append("});")
    out.append("")
    out.append("/// Indice de los documentos, para la entrada Perfil -> Legales.")
    out.append("const List<LegalDocumentEntry> kLegalDocuments =")
    out.append("    <LegalDocumentEntry>[")
    for d in docs:
        out.append("  (")
        out.append(f"    title: {dart_str(d['title'])},")
        out.append(f"    sections: {d['dart']},")
        out.append(f"    lastUpdated: {d['date_const']},")
        out.append("  ),")
    out.append("];")
    return "\n".join(out) + "\n"


CSS = """*,*::before,*::after{box-sizing:border-box}
:root{--bg:#FFFFFF;--surface:#F6F7F8;--ink:#0A0A0A;--muted:#5A5A5A;
--accent:#0F9C6B;--rule:#E2E5E7}
@media (prefers-color-scheme:dark){:root{--bg:#0A0A0A;--surface:#141414;
--ink:#F2F2F2;--muted:#9B9B9B;--accent:#2CE5A2;--rule:#242424}}
body{margin:0;background:var(--bg);color:var(--ink);
font-family:'Barlow',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
font-size:17px;line-height:1.65;-webkit-text-size-adjust:100%}
.wrap{max-width:44rem;margin:0 auto;padding:2.5rem 1.25rem 4rem}
a{color:var(--accent)}
header{border-bottom:1px solid var(--rule);padding-bottom:1.5rem;
margin-bottom:2rem}
.brand{font-family:'Barlow Condensed',sans-serif;font-weight:700;
letter-spacing:.06em;text-transform:uppercase;font-size:.85rem;
color:var(--accent);text-decoration:none}
h1{font-family:'Barlow Condensed',sans-serif;font-weight:700;
text-transform:uppercase;letter-spacing:.02em;font-size:2.25rem;
line-height:1.1;margin:.75rem 0 .5rem}
h2{font-family:'Barlow Condensed',sans-serif;font-weight:700;
text-transform:uppercase;letter-spacing:.02em;font-size:1.2rem;
color:var(--accent);margin:2.5rem 0 .5rem}
.updated{color:var(--muted);font-size:.9rem;margin:0}
p{margin:0 0 1rem;white-space:pre-wrap;overflow-wrap:break-word}
nav ul{list-style:none;padding:0}
nav li{border-bottom:1px solid var(--rule)}
nav li a{display:block;padding:.9rem .25rem;text-decoration:none;
color:var(--ink);font-weight:600}
nav li a:hover{color:var(--accent)}
footer{margin-top:3.5rem;padding-top:1.5rem;border-top:1px solid var(--rule);
color:var(--muted);font-size:.85rem}
footer a{margin-right:1rem;display:inline-block}
@media (max-width:480px){body{font-size:16px}h1{font-size:1.75rem}}"""

FONTS = ('<link rel="preconnect" href="https://fonts.googleapis.com">'
         '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?'
         'family=Barlow:wght@400;600;700&family=Barlow+Condensed:wght@700'
         '&display=swap">')


def esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;")
             .replace(">", "&gt;").replace('"', "&quot;"))


def page(title: str, body_html: str, docs: list[dict], updated: str) -> str:
    nav = "".join(
        f'<a href="/legal/{d["slug"]}">{esc(d["title"])}</a>' for d in docs)
    return f"""<!doctype html>
<html lang="es-AR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)} — TREINO</title>
<meta name="description" content="{esc(title)} de TREINO, servicio de BACKHAUSTIN S.A.S.">
{FONTS}<style>{CSS}</style></head><body><div class="wrap">
<header><a class="brand" href="/legal">TREINO · Legales</a>
<h1>{esc(title)}</h1>
<p class="updated">Última actualización: {esc(updated)}</p></header>
<main>{body_html}</main>
<footer>{nav}<a href="/eliminar-cuenta">Eliminar cuenta</a>
<p>TREINO es un servicio de BACKHAUSTIN S.A.S. — CUIT 30-71929587-4</p>
</footer></div></body></html>
"""


def emit_html(docs: list[dict]) -> dict[str, str]:
    files: dict[str, str] = {}
    for d in docs:
        body = "".join(
            f"<h2>{esc(h)}</h2><p>{esc(b)}</p>" for h, b in d["sections"])
        files[f"{d['slug']}.html"] = page(d["title"], body, docs, d["updated"])
    items = "".join(
        f'<li><a href="/legal/{d["slug"]}">{esc(d["title"])}</a></li>'
        for d in docs)
    idx = (f"<nav><ul>{items}"
           '<li><a href="/eliminar-cuenta">Eliminar tu cuenta</a></li>'
           "</ul></nav>")
    files["index.html"] = page("Documentos legales", idx, docs,
                               docs[0]["updated"])
    return files


# --------------------------------------------------------------------- main
ORDER = [
    "terminos-y-condiciones.md",
    "politica-de-privacidad.md",
    "descargo-medico.md",
    "consentimiento-datos-salud.md",
    "normas-de-comunidad.md",
    "contrato-entrenador.md",
    "retencion-y-borrado.md",
    "aviso-legal.md",
]

UPDATED_RE = re.compile(r"\*\*Última actualización:\*\*\s*(.+)")
PENDING_RE = re.compile(r"\[\[[^\]]*\]\]")


def load() -> tuple[list[dict], list[str]]:
    docs, pending = [], []
    known = {p.name for p in SRC.glob("*.md")}
    for name in ORDER:
        if name not in known:
            sys.exit(f"[!] falta docs/legal/{name}")
        text = (SRC / name).read_text(encoding="utf-8")
        fm = front_matter(text)
        if not fm:
            sys.exit(f"[!] {name} no tiene bloque <!-- treino-legal -->")
        md = publishable(text)
        if not md.strip():
            sys.exit(f"[!] {name}: no se encontro contenido publicable")
        for hit in PENDING_RE.findall(md):
            pending.append(f"{name}: {hit[:70]}")
        um = UPDATED_RE.search(text)
        docs.append({
            "file": name,
            "slug": fm["slug"],
            "title": fm["title"],
            "dart": fm["dart"],
            "updated": inline(um.group(1)) if um else "sin fecha",
            # kTermsSections -> kTermsLastUpdated. Los nombres de #941 salen
            # solos de esta regla, asi que nada que mapear a mano.
            "date_const": fm["dart"].replace("Sections", "LastUpdated"),
            "sections": to_sections(md),
        })
    # los demas .md son internos a proposito
    for extra in sorted(known - set(ORDER)):
        if front_matter((SRC / extra).read_text(encoding="utf-8")):
            sys.exit(f"[!] {extra} tiene front matter pero no esta en ORDER")
    return docs, pending


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="no escribe; falla si lo generado esta desactualizado")
    ap.add_argument("--preview", action="store_true",
                    help="escribe todo bajo build/, sin tocar lib/")
    ap.add_argument("--allow-pending", action="store_true",
                    help="genera aunque queden marcadores [[...]] sin resolver")
    args = ap.parse_args()

    docs, pending = load()

    global CONTACT_EMAIL
    for d in docs:
        if d["slug"] == "aviso-legal":
            m = re.search(r"[\w.+-]+@[\w-]+\.[\w.]+",
                          (SRC / d["file"]).read_text(encoding="utf-8"))
            if m:
                CONTACT_EMAIL = m.group(0)

    if pending and not args.allow_pending:
        print("[!] Hay marcadores sin resolver en el texto PUBLICABLE.\n"
              "    No se genera: un '[[PENDIENTE]]' no puede llegar a un "
              "usuario.\n"
              "    Resolvelos, o usa --allow-pending para previsualizar.\n",
              file=sys.stderr)
        for p in pending:
            print(f"      · {p}", file=sys.stderr)
        return 2

    dart = emit_dart(docs)
    dart_path = (ROOT / "build/legal-preview/legal_content.dart"
                 if args.preview else DART_OUT)

    # Para comparar hay que medir contra el MISMO formato que se escribe.
    if args.check:
        tmp = ROOT / "build" / ".legal-check.dart"
        tmp.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(dart, encoding="utf-8")
        dart_format(tmp)
        dart = tmp.read_text(encoding="utf-8")
        tmp.unlink(missing_ok=True)

        stale = []
        if not DART_OUT.exists() or DART_OUT.read_text(encoding="utf-8") != dart:
            stale.append(str(DART_OUT.relative_to(ROOT)))
        if stale:
            print("[!] Desfasaje: se edito docs/legal/ y no se regenero.\n"
                  "    Corre: python3 scripts/build_legal_content.py\n",
                  file=sys.stderr)
            for s in stale:
                print(f"      · {s}", file=sys.stderr)
            return 1
        print("[OK] Generado al dia.")
        return 0

    dart_path.parent.mkdir(parents=True, exist_ok=True)
    dart_path.write_text(dart, encoding="utf-8")
    dart_format(dart_path)

    print(f"[OK] {dart_path.relative_to(ROOT)}")
    print("     falta el segundo eslabon: dart run tool/build_legal_pages.dart")
    for d in docs:
        print(f"       {len(d['sections']):>2} secciones  {d['slug']}")
    if pending:
        print(f"\n[!] {len(pending)} marcadores sin resolver. "
              "NO publicar esta salida.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
