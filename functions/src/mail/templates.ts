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
// El unico import de `subscriptions/` que hace esta capa, y es a una constante
// PURA (un mapa de tier→numero, sin Firestore ni admin adentro). Se prefiere a
// escribir el 2 a mano: el limite Free lo lee tambien `effective-limit.ts`, y
// dos copias del mismo numero se separan el dia que alguien mueva el plan.
import { SubscriptionTier, TIER_WEIGHT_LIMITS } from "../subscriptions/tier-config";

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
 * Los destinos finos que un mail al PF puede pedir. Es la unica fuente de
 * los valores VALIDOS de `to` — si un valor de aca no tiene case en alguno
 * de los dos routers de Dart (`lib/app/router.dart` para mobile,
 * `lib/app/coach_hub_router.dart` para el Coach Hub web, via
 * `lib/core/utils/deep_link_destination.dart`), ese mail cae al dashboard
 * en silencio: ni la app ni el Hub avisan que un `to` no matcheo nada.
 *
 * Union discriminada por `to` para que `athleteId` sea IMPOSIBLE de pasar
 * con cualquier otro destino: TypeScript rechaza `{ to: "agenda",
 * athleteId: "x" }` en tiempo de compilacion, no en runtime.
 */
export type TrainerDestination =
  | { to: "facturacion" }
  | { to: "agenda" }
  | { to: "solicitudes" }
  | { to: "alumno"; athleteId: string };

/**
 * A donde manda el CTA de un mail al PF, con el destino fino codificado en
 * el query string de `APP_ENTRY_TRAINER`.
 *
 * Sin destino: la entrada bare, igual que siempre (usa esto
 * `federated-signin-hint` via `entradaSegunRol` — ahi no hay contexto de
 * "para que" entra, asi que no hay destino fino que ofrecer).
 */
export function trainerEntry(dest?: TrainerDestination): string {
  if (!dest) return APP_ENTRY_TRAINER;
  const params = new URLSearchParams({ to: dest.to });
  if (dest.to === "alumno") params.set("id", dest.athleteId);
  return `${APP_ENTRY_TRAINER}?${params.toString()}`;
}

/**
 * El wordmark de TREINO, servido desde el propio deploy del Coach Hub.
 *
 * PNG y no SVG porque NINGUN cliente de mail renderiza SVG — el
 * `assets/logo/treino_logo.svg` del repo no sirve para esto. Se rasterizo con
 * Chrome headless y fondo transparente, en el mint de marca: el mismo
 * `#2CE5A2` del acento, que es la variante de la grilla de marca pensada para
 * fondos oscuros y la unica que ya vimos renderizar legible cuando Gmail
 * invierte el mail a claro.
 *
 * Reemplaza al lockup de marca TR + la palabra escrita aparte. El wordmark ES
 * la palabra, asi que tenerlos juntos la decia dos veces.
 */
export const LOGO_URL = "https://app.gettreino.com/email/wordmark.png";

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
    // Solo el wordmark. Antes iba la marca TR con la palabra TREINO escrita al
    // lado; ahora la imagen ES la palabra, y tenerlas juntas la decia dos veces.
    //
    // Vuelve el `alt="TREINO"`, que en el lockup anterior estaba VACIO a
    // proposito: ahi la palabra de al lado era el fallback para los clientes
    // que bloquean imagenes, asi que el alt habria sonado dos veces en un
    // lector de pantalla y ademas se recortaba dentro de la caja de 28px del
    // <img>. Sin esa palabra, el alt vuelve a ser la unica red — y en 110px
    // entra entero.
    "<tr><td style=\"padding:32px 32px 0 32px;\">",
    `<img src="${esc(LOGO_URL)}" width="110" height="56" alt="TREINO"`,
    ` style="display:block;border:0;color:${MINT};font-family:${FONT};`,
    "font-size:15px;font-weight:700;letter-spacing:2px;\"></td></tr>",
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
 * "2 alumnos" · "1 alumno" · "alumnos sin límite".
 *
 * Espejo de `cupoTexto()` en
 * `lib/features/coach_hub/.../facturacion_planes/plan_copy.dart`. Es una copia
 * a proposito y por el mismo motivo que la paleta del encabezado: un mail no
 * puede importar Dart. Si el texto cambia alla, cambia aca.
 *
 * `null` = SIN LIMITE (plan3), no un dato faltante. Interpolarlo directo
 * renderiza la palabra «null», que es exactamente el bug que en la app publico
 * un upsell diciendo «Hasta null alumnos». El tipo obliga a decidir; esta
 * funcion es donde se decide para el mail.
 *
 * El singular no es cosmetico: el limite Free es 2 hoy, pero un tier de 1 haria
 * que TODO mail del paywall dijera "1 alumnos".
 */
export function cupoLabel(limit: number | null): string {
  if (limit === null) return "alumnos sin límite"; // i18n: email transaccional
  return limit === 1 ? "1 alumno" : `${limit} alumnos`;
}

/**
 * El cupo del plan Free, ya escrito. Se DERIVA de `TIER_WEIGHT_LIMITS` en vez
 * de llegar por params: es una constante del producto, no un dato del PF, y un
 * param mas es un param que el proximo productor se olvida de pasar — con el
 * agravante de que `renderMail` degrada los faltantes a vacio, asi que el
 * sintoma seria un mail que dice "pasa al límite del plan Free ()".
 */
const FREE_CUPO_LABEL = cupoLabel(TIER_WEIGHT_LIMITS.free);

/**
 * Nombre visible del plan. Espejo de `tierName()` en `plan_copy.dart`.
 *
 * El productor manda el CODIGO (`plan2`), no la etiqueta: misma regla que
 * `reason`. Un tier que no reconocemos cae a vacio y la oracion sigue leyendose
 * ("No pudimos cobrar tu suscripción."), en vez de imprimir el codigo crudo.
 */
const TIER_LABELS: Record<SubscriptionTier, string> = {
  free: "Free",
  plan1: "Plan 1",
  plan2: "Plan 2",
  plan3: "Plan 3",
};

function tierLabel(tier: string | number | undefined): string {
  const key = String(tier ?? "");
  return Object.prototype.hasOwnProperty.call(TIER_LABELS, key)
    ? TIER_LABELS[key as SubscriptionTier]
    : "";
}

/**
 * Centinela del "sin límite" al cruzar Firestore.
 *
 * `MailParams` es `Record<string, string | number>`: no hay lugar para `null`,
 * que es como `tier-config.ts` codifica "plan3, sin tope". La alternativa —
 * OMITIR el param cuando no hay tope— colapsa dos casos que significan lo
 * contrario: "sin límite" y "el productor se olvidó de mandarlo". El test que
 * renderiza todo kind con `{}` caeria en el segundo y dibujaria el primero.
 * Un centinela explicito los mantiene separados.
 */
const NO_LIMIT_PARAM = "sin-tope";

/**
 * `limit` tal como lo persiste el productor → el `number | null` del dominio,
 * o `undefined` cuando no se pudo leer.
 *
 * SON TRES ESTADOS Y HACEN FALTA LOS TRES. La version de dos —"si no es un
 * numero, devolve null"— hacia que un param ausente o roto renderizara
 * «alumnos sin límite»: el mail del paywall diciendole al PF que NO tiene tope,
 * que es la mentira mas cara que este canal puede contar y encima en la
 * direccion que le hace tomar la decision equivocada. Un limite que no sabemos
 * NO es un limite infinito. Quien consume `undefined` no escribe el numero.
 */
function limitParam(
  value: string | number | undefined,
): number | null | undefined {
  if (value === NO_LIMIT_PARAM) return null;
  const n = typeof value === "number" ? value : Number(value);
  if (value === undefined || value === "" || !Number.isFinite(n) || n < 0) {
    return undefined;
  }
  return Math.floor(n);
}

/**
 * Cuenta de alumnos bloqueados, saneada.
 *
 * Viaja por Firestore como `string | number` (`MailParams` es un mapa plano),
 * y el test de plantillas renderiza TODO kind con params vacios. Sin esto,
 * `undefined` entra como NaN y el mail dice "NaN alumnos quedaron en solo
 * lectura" — el peor render posible justo en el mail que habla de plata.
 */
function countParam(value: string | number | undefined): number {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

/**
 * La frase que explica POR QUE bajo el limite.
 *
 * Recibe un CODIGO (`paused`, `cancelled-expired`, …), no la frase ya armada.
 * Es la regla del outbox: la cola guarda QUE paso, nunca prosa renderizada, asi
 * que un arreglo de copy alcanza a los mails que ya estan encolados sin
 * re-encolar nada. Mandar la oracion desde el productor rompia esa propiedad y
 * ademas repartia el copy en dos archivos.
 *
 * Un codigo desconocido cae en una frase neutra y CIERTA en vez de tirar: el
 * mail sigue siendo util —el limite nuevo y los bloqueados son los datos que
 * importan— y no inventa una causa. Mismo criterio que el estado "denegado sin
 * explicación" del PR #758: no afirmar una causa que no se puede probar.
 */
function downgradeReason(reason: string | number | undefined): string {
  switch (String(reason ?? "")) {
  case "paused":
    return "Pausaste tu suscripción."; // i18n: email transaccional
  case "cancelled-expired":
    return "Se terminó el período que tenías pagado.";
  case "pending":
    return "Tu suscripción todavía no está confirmada.";
  case "tier-change":
    return "Cambiaste de plan.";
  default:
    return "Cambió tu suscripción.";
  }
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

    // ── Molestia reportada durante la sesion ────────────────────────────────
    //
    // NO NOMBRA EL EJERCICIO, y es deliberado — mismo razonamiento de
    // `appointment-series-created`. Este mail esta deduplicado POR SESION (ver
    // `notify-exercise-feedback.ts`), asi que lo produce el PRIMER reporte de
    // la sesion en dispararse. Si el alumno reporta molestia en tres
    // ejercicios, escribir "una molestia en Sentadilla" es peor que no nombrar
    // ninguno: el PF se arma un modelo mental del alcance que es falso, y este
    // mail existe justamente para que abra la app YA.
    //
    // TAMPOCO lleva `text` ni `photoUrl` del reporte. Es la misma regla que ya
    // aplica el push (dato de salud, ver el header de
    // `notify-exercise-feedback.ts`), y por mail pesa MAS: un push se descarta,
    // un mail se queda en la bandeja para siempre y ademas pasa por Resend, que
    // es un tercero. El detalle vive en la app, detras del read gateado de
    // `firestore.rules`. Si algun dia alguien quiere enriquecer este cuerpo,
    // el problema a resolver primero es ese, no el copy.
    //
    // Sin `prefKey`: no hay un ajuste razonable que diga "no me avises cuando a
    // mi alumno le duele algo". Las otras filas de `kNotifTypes` son negocio o
    // social y se pueden querer menos; esta no.
  case "discomfort-reported":
    return build(
      "Un alumno reportó una molestia", // i18n: email transaccional
      "Molestia reportada",
      [
        [strong(params.athleteName), " reportó una molestia durante su sesión."],
        ["El detalle queda en la app: es información de salud y no viaja por mail."],
        ["Entrá a su ficha para ver qué ejercicio fue y qué escribió."],
      ],
      "VER AL ALUMNO",
      ctaUrl,
    );

    // ── Suscripcion del PF: el cobro fallo, hay ventana ─────────────────────
    //
    // NO LLEVA FECHA DE CORTE, y es la decision mas importante de este copy.
    //
    // La tentacion es escribir "si no se cobra antes del <fecha>, pasas a Free".
    // El unico instante que tenemos en el documento es `currentPeriodEnd`, que
    // es el PAGADO-HASTA — no la fecha del corte. El corte llega cuando MP
    // termina de reintentar y el status deja de ser `grace`, y esa ventana la
    // decide MP, no nosotros: hoy ni siquiera existe la integracion (ninguna CF
    // escribe `subscription`). Poner `currentPeriodEnd` ahi seria dar por cierta
    // una fecha que no controlamos, en el mail donde el PF va a basar cuando
    // mover la plata.
    //
    // Es exactamente la regla 11.1 de AGENTS.md aplicada al copy: si no lo
    // podes verificar, escribi lo que SI sabes. Y lo que sabemos es completo sin
    // la fecha: que fallo, que todavia no cambio nada, que pasa si no entra, y
    // que hacer. El dato que falta es el unico que no cambia la accion.
    //
    // `currentPeriodEnd` SI se usa — como scope de dedupe, donde una fecha que
    // se corre unos dias no miente nadie. Ver `subscription-mail.ts`.
  case "subscription-grace": {
    const tier = tierLabel(params.tier);
    const limit = limitParam(params.limit);

    return build(
      "No pudimos cobrar tu suscripción de TREINO", // i18n: email transaccional
      "No pudimos cobrar tu suscripción",
      [
        tier
          ? ["No pudimos cobrar tu suscripción ", strong(tier),
            ". Vamos a reintentar los próximos días."]
          : ["No pudimos cobrar tu suscripción. Vamos a reintentar los próximos días."],
        // El limite solo se nombra si se conoce. Sin el, la frase sigue siendo
        // cierta y completa: lo que el PF necesita saber acá es que TODAVIA no
        // cambio nada.
        //
        // El plan3 NO puede usar `cupoLabel` acá. Esa funcion devuelve un
        // SUSTANTIVO ("alumnos sin límite"), que encaja en "tu plan incluye ___"
        // y en "el plan Free (___)" pero no despues de "seguís con": salia
        // "seguís con alumnos sin límite". Se ve leyendo el mail renderizado y
        // no leyendo el codigo, que es por lo que esta frase esta partida.
        limit === undefined
          ? ["Por ahora no cambia nada y tus alumnos no pierden nada."]
          : limit === null
            ? ["Por ahora no cambia nada: seguís ", strong("sin límite de alumnos"),
              " y tus alumnos no pierden nada."]
            : ["Por ahora no cambia nada: seguís con ", strong(cupoLabel(limit)),
              " y tus alumnos no pierden nada."],
        [
          "Si el cobro no entra, tu cuenta pasa al límite del plan Free (",
          strong(FREE_CUPO_LABEL),
          "). Sobre los alumnos que queden fuera de ese cupo vas a poder verlos, ",
          "pero no editarles rutinas ni notas.",
        ],
        ["Revisá tu medio de pago para que no se corte."],
      ],
      "REGULARIZAR MI SUSCRIPCIÓN",
      ctaUrl,
    );
  }

  // ── Suscripcion del PF: el limite ya bajo ───────────────────────────────
  //
  // La linea de "tus alumnos no pierden nada" NO ES RELLENO. El PR #758 la
  // nombra como el peor error posible de todo este trabajo: sugerir que el
  // alumno perdio algo es falso —conserva rutinas, historial y chat— y ademas
  // le mueve la presion a quien no decide. Lo que se frena es que el PF
  // trabaje sobre el. Si alguna vez hay que recortar este mail, esta linea es
  // la ultima que se va.
  //
  // El vocabulario ("en solo lectura", "verlos pero no editarles rutinas ni
  // notas") esta copiado LITERAL de `blocked_students_screen.dart`. Son el
  // mismo hecho contado por dos canales: si divergen, el PF cree que son dos
  // problemas distintos.
  //
  // `blockedCount` puede ser 0 legitimamente — una bajada de tier con pocos
  // alumnos baja el limite sin dejar a nadie afuera. En ese caso la linea NO
  // se dibuja: "0 alumnos quedaron en solo lectura" es ruido que hace dudar
  // de todo el resto del mail.
  case "subscription-downgraded": {
    const blocked = countParam(params.blockedCount);
    const limit = limitParam(params.limit);
    const lines: Line[] = [
      limit === undefined
        ? [downgradeReason(params.reason), " Tu cuenta pasa a un límite más bajo."]
        : [downgradeReason(params.reason), " Tu cuenta pasa a un límite de ",
          strong(cupoLabel(limit)), "."],
    ];
    // "Ampliá tu plan" es el pedido correcto SOLO cuando el PF bajo de plan a
    // proposito. En una pausa, un `pending` o un vencimiento el problema no es
    // que el plan sea chico —puede ser el mas caro— sino que la suscripcion no
    // esta al dia, y mandarlo a comprar mas de algo que ya pago es el consejo
    // equivocado con la plata de otro. Es la misma bifurcacion que hace el PR
    // #758 en el boton de `blocked_students_screen.dart`.
    //
    // Una causa DESCONOCIDA cae del lado de "regularizar": es el pedido mas
    // neutro de los dos y no le atribuye al PF una decision que no sabemos si
    // tomo.
    const esBajadaDePlan = String(params.reason ?? "") === "tier-change";

    if (blocked > 0) {
      lines.push(
        [
          blocked === 1
            ? "1 alumno quedó en solo lectura: "
            : `${blocked} alumnos quedaron en solo lectura: `,
          "los podés ver, pero no editarles rutinas ni notas.",
        ],
        ["Tus alumnos no pierden nada: conservan sus rutinas, su historial y el chat."],
        [
          esBajadaDePlan
            ? "Para volver a trabajar con todos, ampliá tu plan."
            : "Para volver a trabajar con todos, poné tu suscripción al día.",
        ],
      );
    } else {
      // SIN BLOQUEADOS EL MAIL CAMBIA DE SENTIDO, no solo de largo.
      //
      // Con la lista fija decia "Para volver a trabajar con todos, ampliá tu
      // plan" a un PF que YA esta trabajando con todos: un pedido de plata
      // sobre un problema que no existe. Y "tus alumnos no pierden nada"
      // introduce una preocupacion que nadie tenia. Lo unico cierto y util acá
      // es que el limite cambio y que no lo toco — la misma frase que usa la
      // pantalla del PR #758 para este estado.
      lines.push(["Ninguno de tus alumnos quedó fuera de tu cupo."]);
    }

    return build(
      blocked > 0
        ? "Algunos de tus alumnos quedaron en solo lectura" // i18n: transaccional
        : "Cambió tu límite de alumnos en TREINO",
      blocked > 0 ? "Alumnos en solo lectura" : "Cambió tu límite",
      lines,
      esBajadaDePlan ? "AMPLIAR MI PLAN" : "REGULARIZAR MI SUSCRIPCIÓN",
      ctaUrl,
    );
  }

  default: {
    // Exhaustiveness guard: adding a MailKind without a template fails to
    // compile here rather than shipping a blank email.
    const never: never = kind;
    throw new Error(`renderMail: unhandled kind ${String(never)}`);
  }
  }
}
