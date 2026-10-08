#!/usr/bin/env python3
"""Genera docs/legal/briefing-revision-legal.pdf desde el markdown del briefing.

Reusa el renderizador de `build_legal_docs_pdf.py` en vez de duplicarlo: el
markdown sigue siendo la fuente unica y esto es una salida mas.

    python3 scripts/build_briefing_pdf.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate, Frame, NextPageTemplate, PageBreak, PageTemplate, Spacer,
)

from build_legal_guide_pdf import MUTED, P, RULE, callout, table  # noqa: E402
from build_legal_docs_pdf import render_markdown  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "legal" / "BRIEFING-revision-legal.md"
OUT = ROOT / "docs" / "legal" / "briefing-revision-legal.pdf"


def on_page(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.4)
        canvas.line(22 * mm, 282 * mm, 187 * mm, 282 * mm)
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(22 * mm, 285 * mm, "TREINO — Briefing para revisión legal")
        canvas.drawRightString(187 * mm, 285 * mm, "BACKHAUSTIN S.A.S.")
        canvas.drawCentredString(104.5 * mm, 12 * mm, str(doc.page))
    canvas.restoreState()


def main() -> int:
    flow: list = [Spacer(1, 45 * mm)]
    flow.append(P("TREINO", "cover_t"))
    flow.append(P("Briefing para revisión legal", "cover_t"))
    flow.append(Spacer(1, 14))
    flow.append(P("Qué revisar, qué no, y las siete preguntas que necesitamos "
                  "dictaminadas.", "cover_s"))
    flow.append(Spacer(1, 26))
    flow.append(table([
        ["Cliente", "BACKHAUSTIN S.A.S. — CUIT 30-71929587-4"],
        ["Sede", "Molino de Torres 5301, Córdoba Capital (CP 5021)"],
        ["Contacto", "treino@gettreino.com"],
        ["Acompaña a", "documentos-legales-treino.pdf — 10 borradores"],
    ], [32, 133], header=False))
    flow.append(Spacer(1, 22))
    flow.append(callout(
        "<b>La aplicación todavía no está publicada.</b> Cualquier corrección "
        "que surja de esta revisión se puede aplicar antes de que haya usuarios "
        "reales, que es la única ventana en que sale barata.", warn=True))

    flow.append(NextPageTemplate("body"))
    flow.append(PageBreak())
    render_markdown(SRC.read_text(encoding="utf-8"), flow)

    doc = BaseDocTemplate(
        str(OUT), pagesize=A4,
        title="TREINO — Briefing para revisión legal",
        author="BACKHAUSTIN S.A.S.", subject="Alcance y preguntas de la revisión")
    cover = Frame(22 * mm, 20 * mm, 165 * mm, 250 * mm, id="cover",
                  leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    body = Frame(22 * mm, 20 * mm, 165 * mm, 255 * mm, id="body",
                 leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([
        PageTemplate(id="cover", frames=[cover], onPage=on_page),
        PageTemplate(id="body", frames=[body], onPage=on_page),
    ])
    doc.build(flow)
    print(f"OK -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
