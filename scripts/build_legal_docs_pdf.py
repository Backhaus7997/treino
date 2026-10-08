#!/usr/bin/env python3
"""Compila los nueve documentos legales en un PDF unico, para revision.

    python3 scripts/build_legal_docs_pdf.py     -> docs/legal/documentos-legales-treino.pdf

Destinatario: quien tiene que decidir y quien tiene que revisar (Product Owner,
abogado). No es lo que se publica — para eso esta
`scripts/build_legal_content.py`, que emite el .dart de la app y el HTML del
sitio desde los MISMOS markdown.

Este script NO duplica contenido: lee `docs/legal/*.md`, igual que el otro
generador. Lo unico que se reusa de `build_legal_guide_pdf` son los estilos de
presentacion, que se importan en vez de copiarse.

Los marcadores `[[...]]` se renderizan RESALTADOS: son las decisiones y
revisiones pendientes, y en este PDF cumplen la funcion de checklist en
contexto.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate, Frame, NextPageTemplate, PageBreak, PageTemplate,
    Paragraph, Spacer,
)

from build_legal_guide_pdf import (  # noqa: E402  — estilos compartidos
    ACCENT, MUTED, P, RULE, ST, callout, table,
)
from build_legal_content import ORDER, front_matter  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "legal"
OUT = ROOT / "docs" / "legal" / "documentos-legales-treino.pdf"

PENDING_RE = re.compile(r"\[\[(.+?)\]\]", re.S)
FENCE_RE = re.compile(r"^```", re.M)


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def inline(s: str) -> str:
    """Markdown inline -> markup de reportlab."""
    s = esc(s)
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"`([^`]+)`", r"<font face='Courier'>\1</font>", s)
    return re.sub(r"[ \t]+", " ", s).strip()


def is_pending(text: str) -> bool:
    return "[[" in text


def render_markdown(md: str, flow: list) -> int:
    """Renderiza markdown a flowables. Devuelve cuantos pendientes encontro."""
    pend = 0
    para: list[str] = []
    tbl: list[str] = []
    fenced = False

    def flush_para():
        nonlocal pend
        if not para:
            return
        text = " ".join(para)
        para.clear()
        if is_pending(text):
            pend += len(PENDING_RE.findall(text))
            body = PENDING_RE.sub(
                lambda m: f"<b>{inline(m.group(1))}</b>", text)
            # El marcador ya trae su etiqueta ("PENDIENTE —", "REVISIÓN
            # LEGAL —", etc.): agregarle otra da "PENDIENTE — PENDIENTE —".
            flow.append(callout(body, warn=True))
            flow.append(Spacer(1, 7))
        else:
            flow.append(Paragraph(inline(text), ST["p"]))

    def flush_table():
        nonlocal pend
        if not tbl:
            return
        rows = [[c.strip() for c in r.strip().strip("|").split("|")]
                for r in tbl]
        tbl.clear()
        rows = [r for r in rows
                if not all(re.fullmatch(r":?-{2,}:?", (c or "-")) for c in r)]
        if not rows:
            return
        pend += sum(len(PENDING_RE.findall(c)) for r in rows for c in r)
        cols = max(len(r) for r in rows)
        rows = [r + [""] * (cols - len(r)) for r in rows]
        # anchos: primera columna mas angosta cuando hay muchas
        total = 165
        widths = ([total / cols] * cols if cols <= 2
                  else [total * 0.26] + [total * 0.74 / (cols - 1)] * (cols - 1))
        clean = [[PENDING_RE.sub(lambda m: m.group(1), c) for c in r]
                 for r in rows]
        flow.append(table(clean, widths))
        flow.append(Spacer(1, 8))

    for raw in md.splitlines():
        line = raw.rstrip()

        if FENCE_RE.match(line):
            flush_para()
            fenced = not fenced
            continue
        if fenced:
            flow.append(Paragraph(
                f"<font face='Courier' size='8'>{esc(line)}</font>",
                ST["small"]))
            continue

        if line.startswith("|"):
            flush_para()
            tbl.append(line)
            continue
        flush_table()

        if not line.strip():
            flush_para()
            continue
        if line.startswith("<!--"):
            continue
        if re.fullmatch(r"-{3,}", line.strip()):
            flush_para()
            continue

        if line.startswith("### "):
            flush_para()
            flow.append(Paragraph(inline(line[4:]), ST["h3"]))
            continue
        if line.startswith("## "):
            flush_para()
            flow.append(Paragraph(inline(line[3:]), ST["h2"]))
            continue
        if line.startswith("# "):
            flush_para()
            flow.append(Paragraph(inline(line[2:]), ST["h1"]))
            continue

        if line.startswith("> "):
            para.append(line[2:])
            continue
        m = re.match(r"^\s*(?:[-*]|\d+\.)\s+(.*)$", line)
        if m:
            flush_para()
            content = m.group(1)
            if is_pending(content):
                pend += len(PENDING_RE.findall(content))
                content = PENDING_RE.sub(
                    lambda x: f"<b>{x.group(1)}</b>", content)
            flow.append(Paragraph(f"•&nbsp;&nbsp;{inline(content)}",
                                  ST["bullet"]))
            continue

        para.append(line.strip())

    flush_table()
    flush_para()
    return pend


def on_page(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.4)
        canvas.line(22 * mm, 282 * mm, 187 * mm, 282 * mm)
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(22 * mm, 285 * mm,
                          "TREINO — Documentos legales (borradores)")
        canvas.drawRightString(187 * mm, 285 * mm, "BACKHAUSTIN S.A.S.")
        canvas.drawCentredString(104.5 * mm, 12 * mm, str(doc.page))
    canvas.restoreState()


def main() -> int:
    docs = []
    for name in ORDER:
        text = (SRC / name).read_text(encoding="utf-8")
        fm = front_matter(text) or {}
        docs.append({"file": name, "title": fm.get("title", name),
                     "text": text})

    flow: list = []
    flow.append(Spacer(1, 40 * mm))
    flow.append(P("TREINO", "cover_t"))
    flow.append(P("Documentos legales", "cover_t"))
    flow.append(Spacer(1, 14))
    flow.append(P("Los nueve documentos redactados, en estado de borrador, "
                  "para revisión del Product Owner y del asesor legal.",
                  "cover_s"))
    flow.append(Spacer(1, 26))
    flow.append(table([
        ["Titular", "BACKHAUSTIN S.A.S. — CUIT 30-71929587-4"],
        ["Sede", "Molino de Torres 5301, Córdoba Capital (CP 5021)"],
        ["Contacto", "treino@gettreino.com"],
        ["Estado", "BORRADORES — ninguno publicado"],
    ], [32, 133], header=False))
    flow.append(Spacer(1, 22))
    flow.append(callout(
        "<b>Cómo leer este documento.</b> Los bloques resaltados marcan lo que "
        "falta resolver: son las decisiones pendientes y los puntos que tiene "
        "que dictaminar el abogado. Funcionan como checklist en contexto — "
        "cada uno está donde impacta, no en una lista aparte.<br/><br/>"
        "Dos documentos <b>no se publican sin revisión legal</b>: el Descargo "
        "Médico y los Términos para Entrenadores.<br/><br/>"
        "Algunos traen un anexo final marcado como interno: es la "
        "especificación de lo que hay que construir para que el documento sea "
        "cierto. No forma parte del texto que ve el usuario.", warn=True))

    flow.append(NextPageTemplate("body"))
    flow.append(PageBreak())

    flow.append(P("Contenido", "h1"))
    rows = [["#", "Documento", "Estado"]]
    for i, d in enumerate(docs, 1):
        n = len(PENDING_RE.findall(d["text"]))
        rows.append([str(i), d["title"],
                     f"{n} pendiente{'s' if n != 1 else ''}" if n
                     else "sin pendientes"])
    flow.append(table(rows, [10, 110, 45]))
    flow.append(Spacer(1, 12))
    flow.append(P("Fuente: docs/legal/*.md del repositorio. Este PDF se genera "
                  "con scripts/build_legal_docs_pdf.py — no se edita a mano.",
                  "small"))

    total = 0
    for d in docs:
        flow.append(PageBreak())
        total += render_markdown(d["text"], flow)

    doc = BaseDocTemplate(
        str(OUT), pagesize=A4,
        title="TREINO — Documentos legales (borradores)",
        author="BACKHAUSTIN S.A.S.",
        subject="Borradores para revisión")
    cover = Frame(22 * mm, 20 * mm, 165 * mm, 250 * mm, id="cover",
                  leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    body = Frame(22 * mm, 20 * mm, 165 * mm, 255 * mm, id="body",
                 leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([
        PageTemplate(id="cover", frames=[cover], onPage=on_page),
        PageTemplate(id="body", frames=[body], onPage=on_page),
    ])
    doc.build(flow)
    print(f"OK -> {OUT.relative_to(ROOT)}  ({total} marcadores resaltados)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
