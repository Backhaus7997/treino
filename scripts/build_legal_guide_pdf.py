#!/usr/bin/env python3
"""Genera docs/legal/guia-legal-treino.pdf — la guia de decisiones y tramites.

Uso:
    python3 scripts/build_legal_guide_pdf.py

Requiere reportlab. El contenido vive en CONTENT, abajo: para actualizar la
guia se edita esa lista, no el codigo de layout.

IMPORTANTE: las fuentes Type1 de reportlab codifican en WinAnsi (CP1252). No
metas flechas, tildes de verificacion ni emoji: salen como cuadrados negros.
Usa "->", "[OK]", "[!]" y el bullet "•", que si estan en CP1252.
"""

from reportlab.lib import colors
from reportlab.lib.enums import TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate, Frame, KeepTogether, NextPageTemplate, PageBreak,
    PageTemplate, Paragraph, Spacer, Table, TableStyle,
)

OUT = "docs/legal/guia-legal-treino.pdf"

INK = colors.HexColor("#0A0A0A")
MUTED = colors.HexColor("#5A5A5A")
RULE = colors.HexColor("#D8D8D8")
ACCENT = colors.HexColor("#0F9C6B")   # mint oscurecido: legible sobre blanco
MAGENTA = colors.HexColor("#8B1A9E")
BAND = colors.HexColor("#F4F4F4")
WARNBG = colors.HexColor("#FDF3F6")

_ss = getSampleStyleSheet()


def _s(name, **kw):
    base = dict(fontName="Helvetica", fontSize=9.5, leading=14, textColor=INK)
    base.update(kw)
    return ParagraphStyle(name, parent=_ss["Normal"], **base)


ST = {
    "h1": _s("h1", fontName="Helvetica-Bold", fontSize=17, leading=21,
             spaceBefore=6, spaceAfter=10, textColor=INK),
    "h2": _s("h2", fontName="Helvetica-Bold", fontSize=12.5, leading=16,
             spaceBefore=14, spaceAfter=6, textColor=MAGENTA),
    "h3": _s("h3", fontName="Helvetica-Bold", fontSize=10.5, leading=14,
             spaceBefore=10, spaceAfter=4, textColor=INK),
    "p": _s("p", alignment=TA_JUSTIFY, spaceAfter=6),
    "small": _s("small", fontSize=8.5, leading=12, textColor=MUTED,
                spaceAfter=4),
    "bullet": _s("bullet", alignment=TA_JUSTIFY, leftIndent=11,
                 bulletIndent=2, spaceAfter=3),
    "callout": _s("callout", fontSize=9.5, leading=14, alignment=TA_JUSTIFY),
    "cell": _s("cell", fontSize=8.5, leading=11.5),
    "cellb": _s("cellb", fontName="Helvetica-Bold", fontSize=8.5, leading=11.5),
    "cover_t": _s("cover_t", fontName="Helvetica-Bold", fontSize=34,
                  leading=38, textColor=INK),
    "cover_s": _s("cover_s", fontSize=13, leading=19, textColor=MUTED),
}


def P(t, s="p"):
    return Paragraph(t, ST[s])


def bullets(items):
    return [Paragraph(f"•&nbsp;&nbsp;{i}", ST["bullet"]) for i in items]


def table(rows, widths, header=True):
    data = [[Paragraph(c, ST["cellb"] if (header and r == 0) else ST["cell"])
             for c in row] for r, row in enumerate(rows)]
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1 if header else 0)
    style = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, RULE),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ]
    if header:
        style += [("BACKGROUND", (0, 0), (-1, 0), BAND),
                  ("LINEBELOW", (0, 0), (-1, 0), 0.9, ACCENT)]
    t.setStyle(TableStyle(style))
    return t


def callout(text, warn=False):
    t = Table([[Paragraph(text, ST["callout"])]], colWidths=[165 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), WARNBG if warn else BAND),
        ("LINEBEFORE", (0, 0), (0, -1), 2.2, MAGENTA if warn else ACCENT),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    return t


def decision(num, titulo, que, importa, opciones, reco, desbloquea):
    """Bloque de una decision. Se mantiene junto en la misma pagina."""
    parts = [Paragraph(f"D{num}. {titulo}", ST["h2"]),
             P(f"<b>Qué hay que definir.</b> {que}"),
             P(f"<b>Por qué importa.</b> {importa}")]
    if opciones:
        parts.append(Paragraph("Opciones", ST["h3"]))
        parts.append(table(opciones, [42, 62, 61]))
        parts.append(Spacer(1, 6))
    parts.append(callout(f"<b>Recomendación.</b> {reco}"))
    parts.append(Spacer(1, 5))
    parts.append(P(f"<b>Qué desbloquea.</b> {desbloquea}", "small"))
    return parts


def resolved(num, titulo, respuesta, datos, consecuencias, pendiente=None):
    """Bloque de una decision ya tomada."""
    parts = [Paragraph(f"D{num}. {titulo}  —  RESUELTA", ST["h2"]),
             callout(f"<b>Respuesta.</b> {respuesta}")]
    parts.append(Spacer(1, 7))
    parts.append(Paragraph("Datos para los documentos", ST["h3"]))
    parts.append(table(datos, [45, 120], header=False))
    parts.append(Spacer(1, 8))
    parts.append(Paragraph("Qué se dispara a partir de esto", ST["h3"]))
    parts.append(table(consecuencias, [50, 115]))
    if pendiente:
        parts.append(Spacer(1, 7))
        parts.append(callout(pendiente, warn=True))
    return parts


# ---------------------------------------------------------------- contenido
def build_story():
    S = []
    A = S.append
    sp = lambda h=8: S.append(Spacer(1, h))

    # ---- portada
    A(Spacer(1, 45 * mm))
    A(P("TREINO", "cover_t"))
    A(P("Guía legal de lanzamiento", "cover_t"))
    sp(14)
    A(P("Decisiones que dependen de vos, trámites a iniciar y documentos "
        "pendientes, para publicar en App Store y Google Play.", "cover_s"))
    sp(28)
    A(table([
        ["Fecha", "31 de agosto de 2026"],
        ["Verificado contra", "código de la app y reglas de Firestore"],
        ["Complementa", "docs/legal/ (9 documentos redactados)"],
        ["Titular", "BACKHAUSTIN S.A.S. — CUIT 30-71929587-4"],
        ["Destinatario", "Product Owner / titular de la decisión"],
        ["Preparado por", "Equipo de desarrollo"],
        ["Estado", "Ningún documento publicado todavía"],
    ], [40, 125], header=False))
    sp(24)
    A(callout(
        "<b>Esto no es asesoramiento legal.</b> Es un relevamiento técnico de qué "
        "hace tu aplicación y qué exige publicarla. Las referencias a normativa "
        "argentina requieren verificación de vigencia por un profesional: hay "
        "reforma de la ley de datos personales en trámite.", warn=True))

    A(NextPageTemplate("body"))
    A(PageBreak())

    # ---- 1
    A(P("1. Cómo se lee esta guía", "h1"))
    A(P("El trabajo legal de TREINO se parte en tres, y el orden no es "
        "opcional: cada capa depende de la anterior."))
    sp(4)
    A(table([
        ["Capa", "Quién la resuelve", "Estado"],
        ["<b>Decisiones</b> — quién sos, a quién le vendés, "
         "desde qué edad, cómo cobrás",
         "Vos, y sólo vos", "Pendiente. Bloquea todo lo demás"],
        ["<b>Trámites</b> — inscripciones, contratos con proveedores, "
         "casillas, URLs",
         "Vos, con el contador y el abogado", "Pendiente"],
        ["<b>Documentos</b> — los trece textos",
         "Redacción conjunta; dos exigen revisión legal",
         "9 de 13 redactados"],
    ], [58, 48, 59]))
    sp(10)
    A(P("Los cuatro documentos ya redactados son los que salían de leer el "
        "código: se escribieron contra el modelo de datos y las reglas de "
        "Firestore, no contra una plantilla. Viven en <b>docs/legal/</b>. "
        "Los otros nueve esperan las decisiones de la sección 3."))

    A(P("1.1 Quién resuelve qué", "h3"))
    A(P("La separación importa, porque buena parte de lo que sigue no se puede "
        "resolver desde el rol técnico aunque se tenga el acceso."))
    sp(4)
    A(table([
        ["Tipo", "Qué incluye", "Quién"],
        ["<b>Decisión</b>",
         "Edad mínima, países de operación, cómo se cobra, si la plataforma "
         "intermedia dinero, política de reembolsos, titularidad de las "
         "cuentas de las tiendas",
         "<b>Product Owner</b> o titular. No es del desarrollador, aunque "
         "tenga las credenciales"],
        ["<b>Trámite</b>",
         "Inscripción ante la AAIP, D-U-N-S, conversión de cuentas, acuerdos "
         "con proveedores, contratación del abogado, registro de marca",
         "Titular, con contador y escribano"],
        ["<b>Redacción</b>",
         "Los trece documentos legales",
         "Equipo de desarrollo, con revisión legal en dos de ellos"],
        ["<b>Implementación</b>",
         "Reporte y bloqueo, consentimiento de salud, control de edad, página "
         "de borrado, descargo visible, arrepentimiento",
         "Equipo de desarrollo"],
    ], [26, 84, 55]))

    A(P("2. Dónde estás parado", "h1"))
    A(P("Trece documentos. <b>Nueve redactados, tres bloqueados por decisiones "
        "pendientes y uno que no es un documento sino una pantalla.</b> Más "
        "tres bloqueantes duros de publicación que siguen sin solución "
        "empezada."))
    sp(4)
    A(P("2.1 Los trece documentos", "h3"))
    A(table([
        ["#", "Documento", "Estado", "Depende de"],
        ["1", "Política de Privacidad", "<b>Borrador listo</b>", "—"],
        ["2", "Normas de Comunidad", "<b>Borrador listo</b>", "—"],
        ["3", "Retención y borrado", "<b>Borrador listo</b>", "—"],
        ["4", "Auditoría del texto vigente", "<b>Entregado</b>", "—"],
        ["5", "Términos y Condiciones",
         "<b>Borrador listo</b>, con 3 cláusulas marcadas", "D2, D3, D4/D6"],
        ["6", "Descargo médico",
         "<b>Borrador listo</b>", "<b>abogado</b>"],
        ["7", "Contrato del Entrenador",
         "<b>Borrador listo</b>", "<b>abogado</b>"],
        ["8", "Términos de suscripción", "Bloqueado", "D4, D6"],
        ["9", "Botón de arrepentimiento y baja", "Bloqueado", "D4, D6"],
        ["10", "Consentimiento de datos de salud", "<b>Borrador listo</b>", "—"],
        ["11", "Aviso legal / identificación", "<b>Borrador listo</b>", "—"],
        ["12", "Política de cookies (web)", "Bloqueado", "D3 + relevar la landing"],
        ["13", "Licencias de software libre", "No es documento", "Desarrollo"],
    ], [8, 62, 45, 50]))
    sp(10)
    A(P("2.2 Los tres bloqueantes duros", "h3"))
    A(P("Sin estos tres, la app no se publica. No es una cuestión de "
        "prolijidad: son rechazo en revisión."))
    sp(4)
    A(table([
        ["Bloqueante", "Quién lo exige", "Por qué falta hoy"],
        ["<b>Política de privacidad en URL pública</b>",
         "Apple y Google", "No existe publicada. El texto in-app está y es "
         "un borrador con errores materiales"],
        ["<b>Reportar contenido y bloquear usuarios</b>",
         "Apple, Guideline 1.2",
         "No existe nada en el código. La app tiene feed, chat y reseñas: "
         "tres superficies de contenido de usuarios, cero moderación"],
        ["<b>URL web de eliminación de cuenta</b>",
         "Google Play",
         "El borrado in-app funciona bien. Falta la página accesible sin "
         "instalar la app"],
    ], [45, 35, 85]))
    sp(8)
    A(P("Y un cuarto, que no es de las tiendas sino de coherencia legal: "
        "<b>las cuentas de Apple y de Play están a nombre personal, y el "
        "nombre público de Play es una tercera empresa distinta del titular.</b> "
        "Tiene sección propia — la 4 — porque es la más urgente y la única con "
        "una fecha encima."))
    sp(8)
    A(callout(
        "El segundo no se arregla escribiendo. Es desarrollo: dos features "
        "nuevas, reglas de servidor y una vista de revisión. Está "
        "especificado en <b>docs/legal/normas-de-comunidad.md</b>, en el anexo."))

    A(PageBreak())

    # ---- 3 decisiones
    A(P("3. Las seis decisiones", "h1"))
    A(P("Ninguna de estas la puede tomar un abogado por vos, ni yo. Son "
        "definiciones de negocio. Hasta que no estén, los nueve documentos "
        "pendientes no se pueden escribir sin inventar. "
        "<b>D1 y D5 ya están resueltas; quedan cuatro.</b>"))

    for block in resolved(
        1, "Quién es el titular de TREINO",
        "Hay sociedad constituida: <b>BACKHAUSTIN S.A.S.</b>, inscripta en el "
        "Registro Público de Córdoba. Era la opción recomendada — con datos de "
        "salud y suscripciones de por medio, la separación patrimonial no es un "
        "lujo.",
        [["Razón social", "<b>BACKHAUSTIN S.A.S.</b>"],
         ["CUIT", "30-71929587-4"],
         ["Constitución", "23 de enero de 2026, bajo Ley 27.349"],
         ["Inscripción", "Resolución de la Dirección General de Inspección de "
          "Personas Jurídicas de Córdoba, 5 de febrero de 2026. "
          "Expte. 0007-288597/2026"],
         ["Matrícula", "N° 46468-A — Protocolo de Contratos y Disoluciones"],
         ["Jurisdicción", "Provincia de Córdoba, República Argentina"]],
        [["Frente", "Qué hay que hacer"],
         ["<b>Los trece documentos</b>",
          "Todos identifican ahora a BACKHAUSTIN S.A.S. con su CUIT y "
          "matrícula. Los cuatro borradores ya están actualizados. La fórmula "
          "es: «TREINO es un servicio prestado por BACKHAUSTIN S.A.S.»"],
         ["<b>Cuentas de las tiendas</b>",
          "<b>Verificado: las dos están a nombre personal.</b> Es el punto más "
          "urgente y tiene sección propia — ver la 4"],
         ["<b>Acuerdos con proveedores</b>",
          "Los de Google Cloud, Resend y Vercel se aceptan a nombre de "
          "BACKHAUSTIN S.A.S. Si ya los aceptaste como persona, hay que "
          "rehacerlos"],
         ["<b>Inscripción ante la AAIP</b>",
          "Ya se puede hacer: la base se registra a nombre de la sociedad, con "
          "su CUIT"],
         ["<b>Marca TREINO</b>",
          "Los Términos afirman que la marca y el diseño son propiedad de "
          "TREINO. Conviene que eso tenga respaldo: registro de la marca ante "
          "el INPI a nombre de la sociedad. No bloquea el lanzamiento, pero "
          "sostiene la cláusula"],
         ["<b>Libros digitales</b>",
          "El artículo 2 de la resolución de IPJ remite a la Resolución 58/18 "
          "«G». Es cumplimiento societario, no de la app — pero es tuyo y "
          "conviene que lo lleve el contador desde el arranque"]],
        "<b>Ojo con la jurisdicción en los Términos.</b> Tener la sociedad en "
        "Córdoba no significa que puedas mandar todos los conflictos a "
        "tribunales cordobeses. En relaciones de consumo, la competencia se fija "
        "en el domicilio del consumidor, y una cláusula que lo desplace se tiene "
        "por no escrita. Es una de las cosas puntuales que tiene que resolver el "
        "abogado, no una plantilla."):
        A(block)

    A(PageBreak())

    for block in decision(
        2, "Edad mínima",
        "Desde qué edad se puede crear una cuenta, y qué pasa con los menores.",
        "Los términos vigentes dicen 16 años. El código no lo verifica en "
        "ningún lado: la fecha de nacimiento es un campo opcional del editor "
        "de perfil, no del alta, y ninguna regla la compara contra un mínimo. "
        "Es una cláusula que el propio sistema no hace cumplir — frente a un "
        "reclamo eso no sostiene nada.",
        [["Opción", "A favor", "En contra"],
         ["<b>18 años</b>",
          "Limpio. Sin consentimiento parental, sin régimen especial de "
          "menores, coherente con vender suscripciones y tratar datos de salud",
          "Perdés el segmento adolescente, que en fitness existe"],
         ["<b>16 con consentimiento parental</b>",
          "Mantenés el segmento",
          "Exige un flujo de verificación parental que hoy no existe y que no "
          "es trivial de construir bien"],
         ["<b>13-15</b>",
          "Máximo alcance",
          "Entrás en régimen reforzado de protección de menores en varias "
          "jurisdicciones. Con datos de salud, no lo haría"]],
        "18 años. Y con gate real en el alta, no una cláusula decorativa: "
        "fecha de nacimiento obligatoria al registrarse y validación en "
        "servidor. Un menor cargando medidas corporales y fotos de lesiones en "
        "tu base es un problema que no querés tener.",
        "Términos y Condiciones (5), sección de menores de la Política de "
        "Privacidad (1), y una tarea de desarrollo en el alta."):
        A(block)

    sp(6)

    for block in decision(
        3, "En qué países operás",
        "Si el servicio se ofrece sólo en Argentina, en Latinoamérica, o "
        "también en Europa o Estados Unidos.",
        "Define qué normativa se te aplica encima de la argentina. La ficha de "
        "Play ya tiene metadata en es-419, que es Latinoamérica entera. Si "
        "entra un usuario europeo, entra el RGPD: encargado de tratamiento, "
        "base legal por finalidad, portabilidad, y posiblemente representante "
        "en la Unión. Es un salto de escala en el trabajo, no un párrafo más.",
        [["Opción", "A favor", "En contra"],
         ["<b>Sólo Argentina</b>",
          "Un solo marco: Ley 25.326 y Defensa del Consumidor. La mitad del "
          "trabajo",
          "Techo de mercado. Ampliar después obliga a rehacer los documentos"],
         ["<b>Latinoamérica</b>",
          "Mercado natural del producto y del idioma",
          "Cada país tiene su ley de datos. Brasil tiene LGPD, que es exigente"],
         ["<b>Global, incluida la UE</b>",
          "Sin límite",
          "RGPD completo. No lo haría en el lanzamiento"]],
        "Lanzá en Argentina y redactá pensando en Latinoamérica: mismo "
        "esfuerzo, y no te obliga a rehacer todo cuando crezcas. Dejá la UE "
        "explícitamente afuera en los Términos por ahora — se puede sumar "
        "después, con trabajo dedicado.",
        "Política de Privacidad (1), Términos (5), cookies (12), y el alcance "
        "de la revisión del abogado."):
        A(block)

    A(PageBreak())

    for block in decision(
        4, "Cómo cobrás la suscripción del entrenador",
        "Qué medio de pago procesa los 12.000, 22.000 o 39.000 pesos mensuales "
        "que ya están definidos en el código.",
        "Hoy no hay ningún procesador integrado: la tabla de precios existe en "
        "el servidor, el cobro no. Y hay un tema de plataforma que conviene "
        "mirar antes de decidir: el paywall vive en el Coach Hub web, no en el "
        "binario móvil, lo cual hoy te esquiva la comisión de las tiendas. "
        "Pero si esa suscripción amplía límites que el entrenador experimenta "
        "<i>dentro</i> de la app de iOS, Apple puede exigir compra integrada "
        "igual, por su regla 3.1.1. Es una pregunta abierta que hay que "
        "resolver antes de descongelar ese trabajo.",
        [["Opción", "A favor", "En contra"],
         ["<b>Pasarela local en la web</b> (Mercado Pago u otra)",
          "Sin comisión de tiendas. Cobro en pesos, medios locales",
          "Hay que revisar el riesgo de la regla 3.1.1 de Apple"],
         ["<b>Compra integrada en la app</b>",
          "Sin fricción y sin riesgo de rechazo",
          "Comisión de tienda, y hay que construir todo el flujo"],
         ["<b>Transferencia manual</b>",
          "Cero integración. Sirve para validar",
          "No escala, y complica el arrepentimiento y la baja automática"]],
        "Para arrancar, pasarela local en la web — pero <b>resolver el punto "
        "de Apple antes</b> de construirlo, no después. Y hay un agravante "
        "que sale de D5: está prevista una <b>suscripción del alumno</b> a "
        "futuro. Un plan pago de consumidor, dentro de una app de consumo, "
        "tiene mucho menos margen frente a la regla 3.1.1 que una "
        "suscripción profesional del entrenador. Conviene decidir el modelo "
        "de cobro contemplando ese escenario desde ahora, no cuando llegue.",
        "Términos de suscripción (8), arrepentimiento y baja (9), y la "
        "sección de facturación de la Política de Privacidad."):
        A(block)

    A(PageBreak())

    for block in resolved(
        5, "Cómo cobra el entrenador a su alumno",
        "<b>TREINO no intermedia esa plata.</b> Es sólo la vía de comunicación "
        "entre las partes. El único dinero que la plataforma maneja es la "
        "suscripción del entrenador, y a futuro la del alumno.",
        [["Alumno paga al PF", "<b>Fuera de TREINO.</b> Acuerdo directo entre "
          "las dos personas. La app registra la deuda y muestra dónde pagar, "
          "pero no toca el dinero"],
         ["PF paga a TREINO", "Suscripción por planes. Hoy 12.000 / 22.000 / "
          "39.000 ARS mensuales"],
         ["Alumno paga a TREINO", "<b>A futuro.</b> Suscripción del alumno, "
          "todavía sin definir"]],
        [["Frente", "Qué hay que hacer"],
         ["<b>Lo que se evita</b>",
          "No sos intermediario financiero por el flujo alumno-PF: no entra "
          "régimen de proveedor de servicios de pago ni las obligaciones de "
          "prevención de lavado asociadas a mover fondos de terceros. Es la "
          "decisión correcta para esta etapa"],
         ["<b>Lo que hay que decir, y hoy no se dice</b>",
          "La app <b>facilita</b> ese pago aunque no lo procese: registra la "
          "deuda con monto y estado, y publica el alias de cobro del "
          "entrenador. Facilitar no es procesar, pero el usuario no tiene por "
          "qué saberlo. Va escrito en dos lugares: la cláusula de los Términos "
          "y un aviso <b>visible en la pantalla de pagos</b>"],
         ["<b>Los reclamos igual van a llegar</b>",
          "Si un alumno paga y no recibe el servicio, va a reclamarle a "
          "TREINO, no al PF. No intermediar no te saca del medio a los ojos "
          "del usuario. La mitigación es divulgación clara más un canal de "
          "reporte — que es el mismo que exige Apple y que hay que construir "
          "igual"],
         ["<b>El contrato del PF</b>",
          "Tiene que decir que el acuerdo económico con el alumno es "
          "exclusivamente suyo, que TREINO no garantiza el cobro ni la "
          "prestación, y que el alias que publica es responsabilidad suya"]],
        "<b>Ojo con el alias de cobro.</b> Se verificó el 2026-08-31: "
        "`paymentAlias` vive en `trainerPublicProfiles`, cuya regla de lectura "
        "es `if request.auth != null` — o sea, <b>cualquier usuario logueado "
        "puede leer el alias de cobro de cualquier entrenador</b>, esté "
        "vinculado o no. En Argentina un alias resuelve al nombre del titular "
        "de la cuenta. Con este modelo de pagos, ese dato es el riel de cobro y "
        "merece vivir en un documento que sólo lean los alumnos vinculados, "
        "como ya se hace con los permisos de perfil y de sesiones. No bloquea "
        "el lanzamiento; es trabajo de producto."):
        A(block)

    sp(6)

    for block in decision(
        6, "Reembolsos y baja",
        "Qué pasa si un entrenador se arrepiente, quiere la baja, o pide "
        "devolución.",
        "En Argentina esto no es del todo negociable. La Ley de Defensa del "
        "Consumidor es de orden público —lo que pactes por debajo del piso "
        "legal se tiene por no escrito— y la Resolución 424/2020 obliga a "
        "tener botón de arrepentimiento y baja en línea, visibles, en el sitio "
        "que vende. No es una cláusula: es un botón que tiene que existir.",
        None,
        "Definí el plazo de arrepentimiento respetando el mínimo legal, baja "
        "en línea sin llamada ni mail, y proporcionalidad en el reembolso. "
        "Escribilo simple: si el texto es simple y generoso, no hay conflicto "
        "que gestionar. Este es un caso donde ser prolijo sale más barato que "
        "ser astuto.",
        "Términos de suscripción (8), arrepentimiento y baja (9), y "
        "desarrollo en el Coach Hub web."):
        A(block)

    A(PageBreak())

    # ---- 4 cuentas de tiendas
    A(P("4. Cuentas de las tiendas", "h1"))
    A(callout(
        "<b>Decisión del Product Owner, y la más urgente del documento.</b> El "
        "equipo de desarrollo tiene acceso a las dos consolas, pero cambiar la "
        "titularidad de una cuenta de desarrollador no es una tarea técnica: "
        "compromete a la sociedad, define a quién le paga la tienda y quién "
        "responde ante el usuario.", warn=True))
    sp(8)

    A(P("4.1 Estado verificado", "h3"))
    A(P("Ambas consolas se revisaron el 31 de agosto de 2026. Las dos están a "
        "nombre personal."))
    sp(4)
    A(table([
        ["", "Apple Developer Program", "Google Play Console"],
        ["<b>Tipo de cuenta</b>", "<b>Individual</b>", "<b>Personal</b>"],
        ["Identificador", "Team ID J66AQRRM96",
         "Developer account ID 6318906944253642995"],
        ["Nombre legal", "Martin Backhaus", "Martin Backhaus"],
        ["Nombre público", "Martin Backhaus",
         "<b>Code assurance dev</b>"],
        ["Domicilio cargado", "Cordoba, Córdoba 5000, Argentina "
         "(incompleto: «Cordoba» figura como calle)",
         "MZA 9 LOTE 21 S/N, Córdoba 5021, Argentina"],
        ["Sitio declarado", "—", "code-assurance.com"],
        ["Correo de la cuenta", "—", "martin.backhaus@code-assurance.com"],
        ["Vencimiento", "<b>5 de septiembre de 2026, US$99</b>", "—"],
    ], [30, 67, 68]))

    sp(10)
    A(P("4.2 El problema no es sólo el tipo de cuenta", "h3"))
    A(P("Hay <b>tres identidades distintas</b> declarando ser responsables del "
        "mismo producto:"))
    sp(4)
    A(table([
        ["Dónde", "Qué dice"],
        ["Documentos legales", "BACKHAUSTIN S.A.S. — CUIT 30-71929587-4"],
        ["Play, nombre público en la ficha", "<b>Code assurance dev</b>"],
        ["Play y Apple, nombre legal", "Martin Backhaus"],
        ["Sitio declarado en Play", "code-assurance.com, no gettreino.com"],
        ["La aplicación", "TREINO"],
    ], [55, 110]))
    sp(8)
    A(P("Un usuario que abra TREINO en Play va a ver que la publica «Code "
        "assurance dev», una empresa que no figura en ninguno de los trece "
        "documentos legales — y que tampoco es la titular. Eso deja de ser una "
        "cuestión de prolijidad: es identificación defectuosa del proveedor "
        "frente al consumidor, que es justamente lo que la normativa de "
        "defensa del consumidor exige que esté claro."))

    sp(8)
    A(P("4.3 El domicilio publicado", "h3"))
    A(P("La cuenta de Play tiene cargado <b>MZA 9 LOTE 21 S/N, Córdoba 5021</b> "
        "como domicilio legal de una persona humana. Play publica el domicilio "
        "del desarrollador en la ficha para las cuentas que monetizan."))
    sp(4)
    A(callout(
        "<b>Verificar antes de publicar.</b> Si esa condición aplica al caso, "
        "queda expuesto en la tienda un domicilio particular. Con cuenta de "
        "organización se publica la sede social de BACKHAUSTIN S.A.S. en su "
        "lugar. Es una razón adicional, e independiente de las legales, para "
        "hacer el cambio antes del lanzamiento."))

    A(PageBreak())

    A(P("4.4 La bifurcación", "h3"))
    A(P("Para Apple el camino es uno solo: convertir la cuenta existente de "
        "Individual a Organization. Para Play hay dos, y cuál conviene depende "
        "de un dato que el equipo de desarrollo no puede determinar."))
    sp(4)
    A(table([
        ["Camino", "Cuándo conviene", "Costo"],
        ["<b>Convertir</b> la cuenta actual a organización = BACKHAUSTIN "
         "S.A.S., y cambiarle el nombre público a TREINO o Backhaustin",
         "Si TREINO es lo único publicado en esa cuenta",
         "Sin costo adicional. Sin transferencia de app"],
        ["<b>Crear una cuenta nueva</b> para la sociedad y mover TREINO con "
         "App transfers",
         "Si «Code assurance dev» es una cuenta en uso para otros productos, "
         "que convertirla arrastraría entera",
         "US$25 y tiempos de espera de la transferencia"],
    ], [55, 65, 45]))
    sp(8)
    A(callout(
        "<b>Pregunta abierta para el Product Owner:</b> ¿la cuenta de Play "
        "tiene otras aplicaciones además de TREINO, o «Code assurance dev» se "
        "usa para otros productos? De esa respuesta sale cuál de los dos "
        "caminos se toma.", warn=True))

    sp(10)
    A(P("4.5 Qué hay que hacer, y en qué orden", "h3"))
    A(table([
        ["#", "Paso", "Plazo"],
        ["1", "<b>Tramitar el número D-U-N-S</b> para BACKHAUSTIN S.A.S. Lo "
         "exigen Apple y Google para cuentas de organización. Lo emite Dun "
         "&amp; Bradstreet, es gratis. Apple tiene un buscador para ver si ya "
         "existe uno emitido. Datos: CUIT 30-71929587-4, matrícula 46468-A",
         "<b>Es el paso más largo: puede demorar semanas, más aún si la "
         "sociedad es nueva y no tiene registro previo. Arranca primero</b>"],
        ["2", "<b>Dejar que la membresía de Apple se renueve</b> el 5 de "
         "septiembre",
         "Una membresía vencida saca las apps de la tienda y complica el "
         "trámite. Los US$99 son irrelevantes frente a eso"],
        ["3", "Responder la pregunta de 4.4 y elegir camino para Play",
         "Product Owner"],
        ["4", "Pedir la conversión a Apple. Piden el D-U-N-S y acreditar "
         "facultades para obligar a la sociedad",
         "Después del D-U-N-S"],
        ["5", "Ejecutar el camino elegido en Play, y corregir el nombre "
         "público y el sitio declarado",
         "Después del D-U-N-S"],
        ["6", "Cargar en ambas la <b>sede social real</b> de la sociedad",
         "Es además el dato que falta para cerrar los documentos legales"],
    ], [8, 82, 75]))
    sp(8)
    A(callout(
        "<b>El momento es ahora, y es barato.</b> La aplicación todavía no "
        "está publicada — el registro de cambios dice «Primera versión pública "
        "de TREINO». Sin app publicada no hay reseñas, calificaciones ni "
        "instalaciones atadas a la ficha, así que en Apple es conversión de "
        "cuenta y no transferencia. Una vez publicada, lo mismo se convierte "
        "en un trámite con soporte, esperas y riesgo sobre la ficha viva."))

    A(PageBreak())

    # ---- 5 tramites
    A(P("5. Trámites a iniciar", "h1"))
    A(P("Ninguno es difícil. Varios tienen demora, así que conviene "
        "arrancarlos en paralelo mientras se redactan los documentos."))
    sp(4)
    A(table([
        ["Trámite", "Ante quién", "Nota"],
        ["<b>Constitución de la sociedad</b>, si elegís esa vía",
         "Escribano o IGJ / Registro provincial",
         "Es el de mayor demora. Si va, arrancá por acá"],
        ["<b>Inscripción de la base de datos</b>",
         "AAIP — Registro Nacional de Bases de Datos",
         "Formulario en línea. Obligatorio para quien trata datos personales. "
         "No requiere abogado"],
        ["<b>Casilla de contacto real</b>",
         "Vos", "Bajo gettreino.com. Tiene que estar atendida: es el canal de "
         "ejercicio de derechos y el contacto que exige Apple"],
        ["<b>Aceptar el acuerdo de tratamiento de datos de Google</b>",
         "Consola de Google Cloud",
         "No se redacta, se acepta. Es el respaldo de que Firebase es "
         "encargado del tratamiento"],
        ["<b>Ídem con Resend y con Vercel</b>",
         "Sus paneles", "Mismo trámite, dos minutos cada uno"],
        ["<b>Conversión de las cuentas de las tiendas</b>",
         "Apple y Google",
         "Ver la sección 4. Incluye el trámite del D-U-N-S, que es el de mayor "
         "plazo de todo este documento"],
        ["<b>Registro de la marca TREINO</b>",
         "INPI",
         "A nombre de la sociedad. No bloquea el lanzamiento, pero da respaldo "
         "a la cláusula de propiedad intelectual de los Términos"],
        ["<b>Publicar las URLs legales</b>",
         "Vercel, proyecto de la landing",
         "gettreino.com/legal/privacidad, /terminos, /comunidad, "
         "/eliminar-cuenta. Después cargarlas en las dos tiendas"],
        ["<b>Contratar abogado</b>",
         "Especialista en consumo y protección de datos",
         "Con los borradores en la mano es una revisión, no una redacción. "
         "Ver la sección siguiente"],
    ], [45, 45, 75]))

    sp(10)
    A(P("6. Qué llevarle al abogado", "h1"))
    A(P("Acá es donde se ahorra plata de verdad. Un abogado cobrando por hora "
        "para descubrir qué hace tu app es el peor uso posible del "
        "presupuesto. Llevale esto y la conversación arranca en el minuto "
        "cero."))
    sp(4)
    A(P("6.1 El material", "h3"))
    S.extend(bullets([
        "Los cuatro documentos de <b>docs/legal/</b>, empezando por la "
        "auditoría — le muestra en dos páginas qué recolecta la app y dónde el "
        "texto vigente miente.",
        "Las declaraciones de privacidad de las tiendas, en "
        "<b>store/privacy/</b>: son el inventario de datos ya verificado "
        "contra el binario.",
        "Esta guía, con las decisiones ya tomadas.",
    ]))
    sp(6)
    A(P("6.2 Las preguntas concretas", "h3"))
    A(P("No le pidas «que revise todo». Pedile esto:"))
    sp(4)
    A(table([
        ["#", "Pregunta", "Por qué"],
        ["1", "<b>¿El descargo médico resiste?</b> Alguien se lesiona "
         "siguiendo una rutina que generó la IA de la app, o el plan de un "
         "entrenador de la plataforma. ¿Qué texto y qué flujo de aceptación "
         "necesito?",
         "Es el riesgo más grande del producto y el documento que no se "
         "corrige después"],
        ["2", "<b>¿Cómo evito que un entrenador reclame relación de "
         "dependencia?</b> No quiero el texto del contrato: quiero saber qué "
         "puedo y qué no puedo hacer operativamente.",
         "Rige la primacía de la realidad: el contrato pesa poco, la conducta "
         "pesa todo. Lo que necesitás es el manual de operación, no la "
         "cláusula"],
        ["3", "<b>¿Qué puedo conservar tras un pedido de supresión?</b> Hoy "
         "retengo el registro de pagos, la puntuación de las reseñas y el hilo "
         "de chat del otro participante.",
         "Es la decisión de retención ya tomada en el código. Necesita "
         "validación, no rediseño"],
        ["4", "<b>¿La suscripción del entrenador puede cobrarse fuera de las "
         "tiendas?</b> El paywall vive en la web, pero amplía límites que se "
         "usan dentro de la app de iOS.",
         "Define si se puede seguir con pasarela local o hay que integrar "
         "compra en la app"],
    ], [8, 82, 75]))

    A(PageBreak())

    # ---- 6 producto
    A(P("7. El trabajo de producto que se dispara", "h1"))
    A(P("Buena parte del cumplimiento no se escribe: se programa. Un documento "
        "que promete algo que la app no hace es peor que no tenerlo, porque "
        "queda registrado que lo prometiste."))
    sp(4)
    A(table([
        ["Tarea", "Por qué", "Bloquea"],
        ["<b>Reportar contenido</b> en feed, chat, reseñas y perfiles",
         "Apple 1.2. Hoy no existe", "Sí"],
        ["<b>Bloquear usuarios</b>, con filtrado en reglas de servidor",
         "Apple 1.2. Un bloqueo que se esquiva leyendo la base no es un bloqueo",
         "Sí"],
        ["<b>Página pública de eliminación de cuenta</b>",
         "Google Play la exige accesible sin instalar la app", "Sí"],
        ["<b>Consentimiento de datos de salud</b>, separado del checkbox de "
         "términos",
         "Los datos de salud son categoría sensible y exigen consentimiento "
         "expreso. Hoy van dentro del consentimiento genérico", "Sí"],
        ["<b>Gate de edad en el alta</b>",
         "Hoy la edad no se pide ni se valida al registrarse", "Sí"],
        ["<b>Descargo médico visible</b> en el onboarding y antes de la "
         "primera rutina generada por IA",
         "Un descargo enterrado en la sección 3 de los términos protege menos "
         "que uno que el usuario ve y acepta", "Sí"],
        ["<b>Botón de arrepentimiento y baja en línea</b> en el Coach Hub",
         "Resolución 424/2020. Aplica al sitio que vende",
         "Sí, cuando cobres"],
        ["<b>Opción de desactivar la analítica</b>",
         "Hoy se activa incondicionalmente al arrancar la app, sin salida",
         "No, pero conviene"],
        ["<b>Aviso de qué se conserva</b> en la confirmación de borrado",
         "Se retienen tres cosas y el usuario no se entera", "No"],
        ["<b>Filtrado de términos vetados</b> en textos publicables",
         "Es el mínimo de filtrado que pide Apple 1.2", "Sí"],
    ], [62, 78, 25]))

    sp(10)
    A(P("8. Orden de trabajo", "h1"))
    A(P("Las dependencias reales, en orden. Nada de lo de abajo se puede "
        "hacer antes de lo de arriba."))
    sp(4)
    A(table([
        ["Etapa", "Qué pasa", "Quién"],
        ["<b>1. Decidir</b>",
         "Las cuatro decisiones pendientes de la sección 3. D1 y D5 ya están",
         "Product Owner"],
        ["<b>1.b Cuentas de tiendas</b>",
         "Tramitar el D-U-N-S ya, dejar renovar Apple el 5/9 y elegir camino "
         "para Play. Corre en paralelo con todo lo demás y es lo de mayor "
         "plazo. Ver sección 4",
         "Product Owner"],
        ["<b>2. Identificar</b>",
         "[OK] Sociedad constituida e inscripta. Falta el domicilio de la sede social, la casilla atendida y verificar a nombre de quién están las cuentas de las tiendas",
         "Vos"],
        ["<b>3. Completar los borradores</b>",
         "Rellenar los pendientes de los cuatro documentos ya escritos",
         "Desarrollo"],
        ["<b>4. Redactar los nueve restantes</b>",
         "Términos, descargo, contrato del PF, suscripción, arrepentimiento, "
         "consentimiento de salud, aviso legal, cookies, licencias",
         "Desarrollo"],
        ["<b>5. Revisión legal</b>",
         "Con las cuatro preguntas de la sección 6.2",
         "Abogado"],
        ["<b>6. Construir</b>",
         "Reporte, bloqueo, consentimiento de salud, gate de edad, URL de "
         "borrado, descargo visible",
         "Desarrollo"],
        ["<b>7. Publicar</b>",
         "URLs en gettreino.com, texto portado a la app, enlaces cargados en "
         "las dos tiendas",
         "Desarrollo"],
        ["<b>8. Inscribir</b>",
         "Base de datos ante la AAIP, acuerdos de tratamiento aceptados",
         "Titular"],
    ], [32, 88, 45]))
    sp(10)
    A(callout(
        "<b>Lo que se puede arrancar hoy, sin esperar ninguna decisión:</b> el "
        "trámite del D-U-N-S, la casilla de contacto bajo gettreino.com, los "
        "acuerdos de tratamiento en las tres consolas, y el desarrollo de "
        "reporte y bloqueo. Esas cuatro cosas no dependen de nada de lo que "
        "queda por decidir, y son las de mayor plazo."))

    A(PageBreak())

    # ---- anexo
    A(P("Anexo. Los cinco hallazgos críticos", "h1"))
    A(P("Resumen de la auditoría del texto legal vigente, que hoy se muestra "
        "in-app. Detalle completo, con evidencia de código, en "
        "<b>docs/legal/AUDITORIA-legal-vigente.md</b>."))
    sp(4)
    A(table([
        ["#", "Hallazgo"],
        ["C1", "<b>La política no menciona datos de salud, y la app recolecta "
         "siete tipos.</b> Más de veinte medidas corporales, dolores "
         "reportados con foto, check-in diario de ánimo y dolor, planes de "
         "alimentación, tests de rendimiento. Son categoría sensible y exigen "
         "consentimiento expreso. El equipo ya se lo declaró a Google en la "
         "ficha de Play — y no se lo dijo al usuario"],
        ["C2", "<b>«Tu ubicación no es visible para otros usuarios» es "
         "falso.</b> Para el entrenador, la ubicación precisa de trabajo se "
         "publica en su perfil y se dibuja en el mapa. Es a propósito, es el "
         "modelo de negocio — pero el documento dice lo contrario"],
        ["C3", "<b>El entrenador lleva registros privados sobre el alumno que "
         "el alumno nunca ve.</b> Notas, seguimiento y archivos. Son datos "
         "personales del alumno y el derecho de acceso los alcanza. No están "
         "declarados en ningún lado, y ni el alumno ni el entrenador lo saben"],
        ["C4", "<b>La cláusula de edad no se puede cumplir.</b> Dice 16 años; "
         "el sistema nunca verifica la edad. Un chico de doce crea cuenta sin "
         "fricción"],
        ["C5", "<b>El responsable del tratamiento no está identificado.</b> "
         "«TREINO» no es un sujeto de derecho, y la casilla de contacto "
         "publicada está en un dominio que el proyecto no usa"],
    ], [10, 155]))
    sp(10)
    A(P("Además: siete omisiones de tratamiento no declarado —chat, Resend, "
        "Google Places, el proveedor del mapa, notificaciones, feed y "
        "rankings, alias de cobro— y seis puntos medios. Y un hallazgo que no "
        "es un documento: no existe forma de reportar contenido ni de bloquear "
        "usuarios."))

    sp(14)
    A(P("Qué quedó entregado", "h2"))
    A(table([
        ["Archivo", "Qué es"],
        ["docs/legal/AUDITORIA-legal-vigente.md",
         "18 hallazgos con evidencia de código, ordenados por severidad"],
        ["docs/legal/politica-de-privacidad.md",
         "Reemplazo completo, escrito contra el modelo de datos real"],
        ["docs/legal/normas-de-comunidad.md",
         "Documento publicable, más la especificación de reporte y bloqueo"],
        ["docs/legal/retencion-y-borrado.md",
         "Qué se borra, qué se conserva y por qué. URL de referencia para Play"],
        ["docs/legal/README.md", "Índice y pasos previos a publicar"],
    ], [62, 103]))
    sp(10)
    A(P("Los cuatro son borradores y tienen marcados sus pendientes. Ninguno "
        "está publicado.", "small"))

    return S


# ------------------------------------------------------------------ layout
def on_page(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setStrokeColor(RULE)
        canvas.setLineWidth(0.4)
        canvas.line(22 * mm, 282 * mm, 187 * mm, 282 * mm)
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(22 * mm, 285 * mm, "TREINO — Guía legal de lanzamiento")
        canvas.drawRightString(187 * mm, 285 * mm, "31 de agosto de 2026")
        canvas.drawCentredString(104.5 * mm, 12 * mm, str(doc.page))
    canvas.restoreState()


def main():
    doc = BaseDocTemplate(
        OUT, pagesize=A4,
        title="TREINO — Guía legal de lanzamiento",
        author="Equipo TREINO", subject="Decisiones, trámites y documentos legales",
    )
    frame_cover = Frame(22 * mm, 20 * mm, 165 * mm, 250 * mm, id="cover",
                        leftPadding=0, rightPadding=0,
                        topPadding=0, bottomPadding=0)
    frame_body = Frame(22 * mm, 20 * mm, 165 * mm, 255 * mm, id="body",
                       leftPadding=0, rightPadding=0,
                       topPadding=0, bottomPadding=0)
    doc.addPageTemplates([
        PageTemplate(id="cover", frames=[frame_cover], onPage=on_page),
        PageTemplate(id="body", frames=[frame_body], onPage=on_page),
    ])
    doc.build(build_story())
    print(f"OK -> {OUT}")


if __name__ == "__main__":
    main()
