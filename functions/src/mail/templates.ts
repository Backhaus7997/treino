/**
 * Email templates for TREINO transactional mail.
 *
 * Design:
 *   - Colours come from the official Mint Magenta palette
 *     (`lib/app/theme/tokens/primitives.dart`, `docs/design-system.md`).
 *     Email cannot import Dart tokens, so the values used here are mirrored as
 *     constants and must be updated if the palette moves.
 *   - Table-based layout with fully inline styles. Gmail strips <style> blocks
 *     and Outlook's Word renderer ignores most modern CSS; tables + inline
 *     attributes are the only layout that survives everywhere.
 *   - Every template returns a plain-text part as well. A missing text/plain
 *     alternative is itself a spam signal, independent of content.
 *   - ALL interpolated values pass through `esc`. `athleteDisplayName` is
 *     user-controlled free text that reaches us straight from Firestore.
 *   - User-facing strings are es-AR, matching the notification CFs.
 */

import { MailKind, MailParams } from "./types";

// Mirrored from AppColorPrimitives — see header note.
const INK = "#0A0A0A";
const INK_CARD = "#0F1513";
const MINT = "#2CE5A2";
const BONE = "#FFFFFF";
const MUTED = "#9BA8A1";

const FONT = "Arial,Helvetica,sans-serif";

/** A rendered message, ready to hand to the sender. */
export interface RenderedMail {
  subject: string;
  html: string;
  text: string;
}

/**
 * Escapes HTML-significant characters.
 *
 * Display names are user-controlled. Without this a name containing a `<`
 * breaks the layout at best, and injects markup into the message at worst.
 */
function esc(value: string | number | undefined): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Landing pública. Destino por defecto de los CTA.
 *
 * Es el default —y no el Coach Hub— porque la MAYORÍA de estos mails van a
 * ATLETAS, que usan la app móvil, no el dashboard web del entrenador. Mandar a
 * un atleta a `app.gettreino.com` lo deja mirando una herramienta que no es
 * suya. La landing al menos explica qué es TREINO y cómo bajarla.
 *
 * TODO(deep-links): el destino correcto para un atleta es la app, no una web.
 * Hoy el repo no tiene Universal Links ni App Links configurados (ni
 * `assetlinks.json`, ni associated domains, ni `autoVerify` en el manifest),
 * así que no hay forma de abrir la app desde un mail. Cuando eso exista, estos
 * CTA tienen que apuntar ahí.
 */
export const LANDING_URL = "https://gettreino.com";

/** Coach Hub web. Solo para los mails cuyo destinatario ES el entrenador. */
export const COACH_HUB_URL = "https://app.gettreino.com";

/**
 * A donde manda el CTA cuando el destinatario NO es el entrenador.
 *
 * Antes era `LANDING_URL`, y era un error medido: `gettreino.com` es de OTRO
 * producto —gimnasios y rankings, en ingles— y dice literalmente "No custom
 * app". Un atleta que recibia "tu entrenador confirmo la sesion" tocaba el
 * boton y caia en una pagina sin login, sin descarga, y que le negaba la
 * existencia de la app que tiene instalada.
 *
 * `/abrir/alumno` es un App Link: en un telefono con la app instalada, el
 * sistema operativo la abre y esta URL nunca llega al navegador. Quien la ve
 * como pagina es porque abrio el mail en una computadora o no tiene la app.
 */
export const APP_ENTRY_ATHLETE = "https://app.gettreino.com/abrir/alumno";

/**
 * Idem para el entrenador. Es una URL distinta y no un parametro porque el
 * DESTINO es distinto: el profe tiene la app y ademas el Coach Hub web, asi
 * que abriendo desde una computadora tiene algo util que hacer. El atleta solo
 * tiene la app. Mandar a los dos al mismo lado obliga a una de las dos mitades
 * a leer instrucciones que no le corresponden.
 *
 * Reemplaza al viejo `COACH_HUB_URL` como destino de mail: mandaba al profe
 * derecho a la web incluso desde el telefono, donde la app le sirve mas.
 */
export const APP_ENTRY_TRAINER = "https://app.gettreino.com/abrir/profe";

/**
 * La marca TR, servida desde el propio deploy del Coach Hub (`web/email/`).
 *
 * PNG y no SVG porque NINGUN cliente de mail renderiza SVG — el logo del repo
 * (`assets/logo/treino_logo.svg`) no sirve para esto. Sale del foreground del
 * adaptive icon, que ya viene con fondo transparente, recortado a la marca:
 * un cuadrado negro sobre la tarjeta `#0F1513` dibujaria un recuadro visible,
 * porque los dos negros no son el mismo.
 *
 * Se sirve desde `app.gettreino.com` y no desde los `web/icons/` que ya
 * existian: esos siguen siendo los del template de Flutter.
 */
export const LOGO_URL = "https://app.gettreino.com/email/logo.png";

/**
 * Wraps body markup in the branded shell.
 *
 * @param heading  - Large headline, already escaped.
 * @param bodyHtml - Pre-escaped inner markup.
 * @param ctaLabel - Button text; omit for a mail with no action.
 * @param ctaHref  - Button target. Defaults to the app. The auth mails pass the
 *                   one-time link the Admin SDK minted, which is why this is a
 *                   parameter at all.
 */
function layout(
  heading: string,
  bodyHtml: string,
  preheader: string,
  ctaLabel?: string,
  ctaHref: string = APP_ENTRY_ATHLETE,
): string {
  // Hace falta la etiqueta Y el destino. Sin destino, `ctaHref` llega como ""
  // —los mails de auth pasan el `actionLink` crudo, y `sendQueuedMail` lo BORRA
  // del documento despues de enviar— y se dibujaba un boton con `href=""`, que
  // en un mail no va a ningun lado. Mejor sin boton que con uno muerto.
  const cta = ctaLabel && ctaHref
    ? [
      "<tr><td style=\"padding:8px 32px 32px 32px;\">",
      `<a href="${esc(ctaHref)}" style="display:inline-block;`,
      `background:${MINT};color:${INK};font-weight:700;font-size:15px;`,
      "text-decoration:none;padding:14px 28px;border-radius:8px;",
      `font-family:${FONT};">${esc(ctaLabel)}</a>`,
      "</td></tr>",
    ].join("")
    : "";

  return [
    "<!doctype html>",
    "<html lang=\"es-AR\"><head><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
    "<meta name=\"color-scheme\" content=\"dark\">",
    "<title>TREINO</title></head>",
    `<body style="margin:0;padding:0;background:${INK};">`,
    // Preheader: la linea gris que la bandeja muestra al lado del asunto. Sin
    // esto el cliente agarra lo primero que encuentre en el HTML.
    "<div style=\"display:none;max-height:0;overflow:hidden;opacity:0;\">",
    esc(preheader),
    // Relleno invisible: sin el, el cliente sigue leyendo el cuerpo y pega el
    // resto del mail atras del preheader en la vista previa.
    "&#8199;&#65279;&zwnj;".repeat(60),
    "</div>",
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"",
    ` style="background:${INK};padding:32px 16px;"><tr><td align="center">`,
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"",
    ` style="max-width:520px;background:${INK_CARD};border-radius:16px;">`,
    // Lockup: marca + palabra. La palabra NO es decorativa — es el fallback.
    // Outlook y Gmail-sin-imagenes no cargan el <img>, y un header que es solo
    // logo desaparece entero para esa gente.
    "<tr><td style=\"padding:32px 32px 0 32px;\">",
    "<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\"><tr>",
    "<td style=\"padding-right:10px;\" valign=\"middle\">",
    // `alt=""` A PROPOSITO, y no `alt="TREINO"`. Medido sobre el render con
    // imagenes bloqueadas: el alt se dibuja DENTRO de la caja de 28px del
    // <img>, asi que "TREINO" se recorta a "TRE" y queda "TRE TREINO" al lado
    // del wordmark. Un fallback que se ve roto es peor que no tenerlo. La
    // marca de al lado ES el fallback, y ademas un lector de pantalla que
    // encuentre las dos cosas leeria "TREINO TREINO".
    `<img src="${esc(LOGO_URL)}" width="28" height="44" alt=""`,
    " style=\"display:block;border:0;\"></td>",
    "<td valign=\"middle\"><div style=\"font-size:13px;letter-spacing:2px;",
    `color:${MINT};font-weight:700;font-family:${FONT};">TREINO</div>`,
    "</td></tr></table></td></tr>",
    "<tr><td style=\"padding:20px 32px 0 32px;\">",
    `<h1 style="margin:0;font-size:24px;line-height:1.25;color:${BONE};`,
    `font-family:${FONT};">${heading}</h1></td></tr>`,
    "<tr><td style=\"padding:16px 32px 24px 32px;font-size:15px;",
    `line-height:1.6;color:${MUTED};font-family:${FONT};">${bodyHtml}</td></tr>`,
    cta,
    "</table>",
    "<div style=\"max-width:520px;padding:20px 8px;font-size:12px;",
    `line-height:1.6;color:${MUTED};font-family:${FONT};">`,
    "Recibís este mail porque tenés una cuenta en TREINO.<br>",
    `<a href="${esc(LANDING_URL)}" style="color:${MUTED};">gettreino.com</a>`,
    "</div>",
    "</td></tr></table></body></html>",
  ].join("");
}

/**
 * Un valor resaltado dentro de una línea (nombres, fechas, importes).
 *
 * Es una CLASE y no un string con markup a propósito. Antes `strong()` devolvía
 * HTML ya armado y la parte de texto plano se obtenía quitándole los tags con
 * `replace(/<[^>]+>/g, "")`. CodeQL marcó eso como
 * `js/incomplete-multi-character-sanitization` (severidad alta) y tiene razón:
 * una sola pasada de ese regex puede CREAR un tag que antes no existía —
 * `<<a>script>` queda en `<script>`.
 *
 * Acá no era explotable, porque todo lo que viene del usuario ya pasó por
 * `esc()` antes de llegar, y el resultado va a text/plain, no a HTML. Pero el
 * arreglo correcto no es endurecer el regex: es dejar de derivar un formato del
 * otro. Con segmentos, cada representación se construye desde la MISMA fuente
 * estructurada y ninguna tiene que adivinar dónde termina la otra.
 */
class Highlight {
  constructor(readonly value: string) {}
}

/** Texto literal nuestro, o un valor resaltado. */
type Segment = string | Highlight;

/** Una línea del cuerpo: copy propio intercalado con valores. */
type Line = Segment[];

/** Marca un valor como resaltado. El escape ocurre por formato, no acá. */
function strong(value: string | number | undefined): Highlight {
  return new Highlight(String(value ?? ""));
}

/** Renderiza una línea a HTML. Todo se escapa, venga de donde venga. */
function lineToHtml(line: Line): string {
  return line
    .map((seg) =>
      seg instanceof Highlight
        ? `<strong style="color:${BONE};">${esc(seg.value)}</strong>`
        : esc(seg),
    )
    .join("");
}

/** Renderiza una línea a texto plano. Sin entidades: es text/plain. */
function lineToText(line: Line): string {
  return line
    .map((seg) => (seg instanceof Highlight ? seg.value : seg))
    .join("");
}

/**
 * Builds both MIME parts from a heading, body lines, and an optional CTA.
 *
 * When the CTA points somewhere other than the app, the raw URL is appended to
 * the text/plain part. A password-reset mail whose only link lives inside an
 * HTML anchor is unusable for anyone reading in plain text — and unusable is
 * the same as broken when it is the path back into a locked account.
 */
function build(
  subject: string,
  heading: string,
  lines: Line[],
  ctaLabel?: string,
  ctaHref?: string,
): RenderedMail {
  const bodyHtml = lines
    .map((l) => `<p style="margin:0 0 12px 0;">${lineToHtml(l)}</p>`)
    .join("");

  const textLines = [heading, "", ...lines.map(lineToText)];
  if (ctaHref) textLines.push("", ctaHref);

  // El preheader se DERIVA de la primera linea del cuerpo, no es un parametro
  // por template. Un campo mas que cada `case` tiene que acordarse de pasar es
  // un campo que el proximo MailKind va a olvidar, y el sintoma —una vista
  // previa con basura en la bandeja— no lo agarra ningun test que no lo busque
  // a proposito. Derivarlo lo hace imposible de olvidar, y la primera linea ES
  // el resumen del mail: si no lo fuera, el problema seria el copy.
  const preheader = lines.length > 0 ? lineToText(lines[0]) : heading;

  return {
    subject,
    html: layout(heading, bodyHtml, preheader, ctaLabel, ctaHref),
    text: textLines.join("\n"),
  };
}

/**
 * Renders a queued mail.
 *
 * Missing params degrade to an empty string rather than throwing: a template
 * gap must not strand a queue document in permanent failure.
 *
 * @param kind   - Selects the template.
 * @param params - Template values, as persisted on the queue doc.
 */
export function renderMail(kind: MailKind, params: MailParams): RenderedMail {
  // Destino del CTA. Los productores pasan `ctaUrl` cuando el destinatario es
  // el entrenador; el resto cae al landing. Se resuelve una sola vez acá para
  // que la URL entre TAMBIEN en la parte de texto plano — un CTA que solo vive
  // dentro de un <a> no existe para quien lee en texto.
  const ctaUrl = params.ctaUrl ? String(params.ctaUrl) : APP_ENTRY_ATHLETE;

  switch (kind) {
  // ── Auth ─────────────────────────────────────────────────────────────────
  //
  // `actionLink` es el link de un solo uso que minta el Admin SDK
  // (`generatePasswordResetLink` / `generateEmailVerificationLink`). Apunta al
  // action handler que Firebase ya hostea, asi que NO hace falta una pagina
  // propia para que esto funcione.
  //
  // El copy no nombra al usuario ni dice si la cuenta existe: estos mails son
  // el unico canal donde una diferencia de texto filtraria que una direccion
  // esta registrada, y el flujo entero se diseño para no filtrarlo
  // (REQ-AUTH-011).
  case "password-reset":
    return build(
      "Restablecé tu contraseña de TREINO", // i18n: email transaccional
      "Restablecer contraseña",
      [
        ["Recibimos un pedido para cambiar la contraseña de tu cuenta."],
        ["El link vence en una hora y se puede usar una sola vez."],
        [
          "Si no lo pediste vos, ignorá este mail: tu contraseña no cambia " +
              "hasta que alguien complete el formulario.",
        ],
      ],
      "CAMBIAR MI CONTRASEÑA",
      String(params.actionLink ?? ""),
    );

  // Va EN LUGAR del reseteo cuando la cuenta no tiene contraseña que
  // restablecer. Sin `actionLink`: no hay nada que un link pueda resolver.
  //
  // El copy no nombra al usuario ni confirma que la cuenta exista para nadie
  // mas que para el dueño del buzon — que es justamente quien tiene derecho a
  // saber como entra a su propia cuenta. La respuesta del callable sigue siendo
  // identica en las tres ramas, asi que la anti-enumeracion no se toca.
  case "federated-signin-hint":
    return build(
      "Cómo entrar a tu cuenta de TREINO", // i18n: email transaccional
      "Entrá con Google o Apple",
      [
        ["Recibimos un pedido para cambiar la contraseña de tu cuenta."],
        [
          "Esa cuenta no usa contraseña: se creó con ",
          strong("Iniciar sesión con Google o Apple"),
          ", así que entrás con ese botón.",
        ],
        ["Si no lo pediste vos, no hace falta que hagas nada."],
      ],
      "IR A TREINO",
      ctaUrl,
    );

  case "email-verification":
    return build(
      "Confirmá tu email en TREINO",
      "Confirmá tu email",
      [
        ["Tocá el botón para confirmar que esta dirección es tuya."],
        ["Es el último paso para tener la cuenta activa."],
      ],
      "CONFIRMAR MI EMAIL",
      String(params.actionLink ?? ""),
    );

  case "appointment-confirmed":
    return build(
      "Tu sesión quedó confirmada", // i18n: email transaccional
      "Sesión confirmada",
      [
        [strong(params.trainerName), " confirmó tu sesión."],
        [strong(params.dateLabel), " a las ", strong(params.timeLabel), "."],
        ["Si no podés ir, cancelá con más de 24 horas de anticipación."],
      ],
      "VER MI AGENDA",
      ctaUrl,
    );

    // NOTE: deliberately states no session count and no date range. This mail
    // is produced by the FIRST trigger of a batched series to fire, and at that
    // moment the rest of the WriteBatch may not have committed — any count read
    // there would be a partial one. Telling an athlete "3 sessions" when there
    // are 36 is worse than not telling them a number at all, so the agenda does
    // the work and the copy stays true.
  case "appointment-series-created":
    return build(
      "Tu entrenador te agendó nuevas sesiones",
      "Tenés sesiones nuevas",
      [
        [strong(params.trainerName), " te agendó una serie de sesiones recurrentes."],
        ["Las tenés todas cargadas en tu agenda, con día y horario."],
      ],
      "VER MI AGENDA",
      ctaUrl,
    );

  case "appointment-cancelled":
    return build(
      "Se canceló una sesión",
      "Sesión cancelada",
      [
        [
          strong(params.otherName),
          " canceló la sesión del ",
          strong(params.dateLabel),
          " a las ",
          strong(params.timeLabel),
          ".",
        ],
        ["El horario vuelve a estar disponible en la agenda."],
      ],
      "VER MI AGENDA",
      ctaUrl,
    );

    // Same partial-batch reasoning as `appointment-series-created`.
  case "appointment-series-cancelled":
    return build(
      "Se cancelaron sesiones de tu serie",
      "Sesiones canceladas",
      [
        [strong(params.otherName), " canceló sesiones de una serie recurrente."],
        ["Revisá tu agenda para ver cómo quedó."],
      ],
      "VER MI AGENDA",
      ctaUrl,
    );

  case "link-requested":
    return build(
      "Tenés una solicitud de vinculación",
      "Nueva solicitud",
      [
        [strong(params.athleteName), " quiere entrenar con vos."],
        ["Aceptá la solicitud para empezar a armarle la rutina."],
      ],
      "VER SOLICITUD",
      ctaUrl,
    );

  case "link-accepted":
    return build(
      "¡Ya estás vinculado!",
      "Vinculación aceptada",
      [
        [strong(params.trainerName), " aceptó tu solicitud."],
        ["Ya podés ver las rutinas que te asigne y hablar por el chat."],
      ],
      "IR A MI ENTRENADOR",
      ctaUrl,
    );

  case "payment-overdue":
    return build(
      "Tenés un pago pendiente",
      "Pago vencido",
      [
        ["Tenés un pago pendiente con ", strong(params.trainerName), "."],
        [strong(params.amountLabel), " — vencía el ", strong(params.dueLabel), "."],
        ["Coordiná el pago con tu entrenador para seguir entrenando."],
      ],
      "VER MIS PAGOS",
      ctaUrl,
    );

  default: {
    // Exhaustiveness guard: adding a MailKind without a template fails to
    // compile here rather than shipping a blank email.
    const never: never = kind;
    throw new Error(`renderMail: unhandled kind ${String(never)}`);
  }
  }
}
