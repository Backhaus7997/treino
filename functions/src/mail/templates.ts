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

import { KINDS_DE_PUBLICIDAD, MailKind, MailParams } from "./types";
// Los unicos imports de `subscriptions/` que hace esta capa, y los dos son a
// constantes PURAS (mapas de tier→numero, sin Firestore ni admin adentro). Se
// prefieren a escribir los numeros a mano: el limite Free lo lee tambien
// `effective-limit.ts`, los precios los cobra el checkout, y dos copias del
// mismo numero se separan el dia que alguien mueva el plan.
import {
  SubscriptionTier,
  TIER_CUSTOM_EXERCISE_LIMITS,
  TIER_LABELS,
  TIER_PRICES_ARS,
  TIER_TEMPLATE_LIMITS,
  TIER_WEIGHT_LIMITS,
} from "../subscriptions/tier-config";
import {
  ATHLETE_PRICES_ARS,
  ATHLETE_PRO_MAX_OWN_ROUTINES,
  ATHLETE_PRO_MAX_ROUTINE_DAYS,
  ATHLETE_PRO_MAX_ROUTINE_WEEKS,
} from "../subscriptions/athlete-plan-config";
import { formatArs, formatShortDateAR } from "./format";

// Mirrored from AppColorPrimitives — see header note.
const INK = "#0A0A0A";
const INK_CARD = "#0F1513";
const MINT = "#2CE5A2";
const BONE = "#FFFFFF";
const MUTED = "#9BA8A1";
// Morado de la marca para los títulos grandes de las cards de planes: el magenta
// de `AppColorPrimitives` (#C123E0) aclarado hasta 4,8:1 sobre `PLAN_CARD` (el
// magenta puro da 3,5:1 y no alcanza para texto de 16 px).
const MORADO = "#D457EC";

// Las cards de planes (`planesToHtml`): `white06` (relleno) y `white10` (borde)
// de AppColorPrimitives, compuestos sobre `INK_CARD`. El kit despega una
// superficie de la card que la contiene subiendo el relleno, sin sombras. Van
// resueltos a hex porque Outlook no respeta el alpha ni en fondos ni en bordes.
const PLAN_CARD = "#1D2321";
const PLAN_CARD_BORDE = "#343938";

const FONT = "Arial,Helvetica,sans-serif";

/** A rendered message, ready to hand to the sender. */
export interface RenderedMail {
  subject: string;
  html: string;
  text: string;
}

/**
 * Lo que `sendQueuedMail` decide al ENVIAR y la plantilla no puede saber sola.
 * Sin opciones, el mail sale exactamente como siempre.
 */
export interface OpcionesDeMail {
  /**
   * La URL de baja de los correos promocionales (`baja-de-promocionales.ts`).
   * Con ella el pie lleva el aviso destacado, el link y las transcripciones
   * legales, en HTML y en texto plano. Sin ella el pie es el de siempre.
   */
  bajaDePromocionales?: string;
  /**
   * `false` omite el bloque de venta de un mail operativo (hoy `limit-reached`:
   * la línea «hay planes más grandes» y el botón VER LOS PLANES; y
   * `email-code-*`: el bloque de pagos y su botón). Los demás kinds no tienen
   * bloque que omitir y lo ignoran.
   * Default `true`.
   */
  comercial?: boolean;
}

// ── Las transcripciones del pie de baja ─────────────────────────────────────
//
// Textuales: la Disposición DNPDP 4/2009 (art. 1) pide que el correo de
// publicidad directa transcriba los dos textos, no que los parafrasee. Fuentes
// en `openspec/changes/baja-de-correos-promocionales/design.md` §2. NO se
// retocan para que «suenen mejor»: una paráfrasis deja de ser la transcripción.
const TRANSCRIPCION_LEY_25326 =
  "Ley 25.326, art. 27, inc. 3: \"El titular podrá en cualquier momento " +
  "solicitar el retiro o bloqueo de su nombre de los bancos de datos a los que " +
  "se refiere el presente artículo.\"";

const TRANSCRIPCION_DECRETO_1558 =
  "Decreto 1558/01, Anexo I, art. 27, párrafo 3: \"En toda comunicación con " +
  "fines de publicidad que se realice por correo, teléfono, correo electrónico, " +
  "Internet u otro medio a distancia a conocer, se deberá indicar, en forma " +
  "expresa y destacada, la posibilidad del titular del dato de solicitar el " +
  "retiro o bloqueo, total o parcial, de su nombre de la base de datos. A pedido " +
  "del interesado, se deberá informar el nombre del responsable o usuario del " +
  "banco de datos que proveyó la información.\"";

// Lo pide la segunda oración del párrafo 3, y es el responsable que declara
// `docs/legal/politica-de-privacidad.md`.
const RESPONSABLE_DEL_BANCO = "Responsable: BACKHAUSTIN S.A.S. — CUIT 30-71929587-4";

const AVISO_PROMOCIONAL =
  "Recibís este correo promocional porque tenés una cuenta en TREINO. " +
  "Si no querés recibir más, ";

const TEXTO_DEL_LINK_DE_BAJA = "dejá de recibir correos promocionales";

/**
 * El término que la Disposición DNPDP 4/2009, art. 2, manda poner «en el
 * encabezado» del correo de publicidad directa no consentida previamente. Se
 * antepone SÓLO al asunto de los kinds de `KINDS_DE_PUBLICIDAD`: el cuerpo y el
 * texto plano no cambian. La cita completa, la decisión del 2026-10-02 y el
 * porqué de los dos mixtos que no lo llevan están en esa constante.
 */
const PREFIJO_DE_PUBLICIDAD = "Publicidad: ";

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
 * Landing pública de TREINO. Hoy vive **sólo en el pie** del mail, como el
 * link de texto «gettreino.com» que dice de dónde viene el correo.
 *
 * ── Lo que este comentario decía y ya no es cierto ──
 *
 * Decía «destino por defecto de los CTA», y que lo era porque la mayoría de
 * estos mails van a atletas. Dejó de serlo cuando [APP_ENTRY_ATHLETE] lo
 * reemplazó: hoy ningún CTA apunta acá. El único uso es `renderEmail`.
 *
 * Y traía un `TODO(deep-links)` que afirmaba que «el repo no tiene Universal
 * Links ni App Links configurados (ni `assetlinks.json`, ni associated
 * domains, ni `autoVerify` en el manifest)». **Las tres cosas existen**,
 * verificadas el 2026-09-17:
 *
 * - `web/well-known/assetlinks.json`
 * - `applinks:app.gettreino.com` en `ios/Runner/Runner.entitlements:13`
 * - `android:autoVerify="true"` sobre `app.gettreino.com` en
 *   `android/app/src/main/AndroidManifest.xml:61-66`
 *
 * O sea que el TODO ya estaba cumplido por el propio [APP_ENTRY_ATHLETE] que
 * vive doce líneas más abajo, y seguía pidiendo que se hiciera. Regla 11.1 de
 * `AGENTS.md`: una advertencia falsa es peor que ninguna.
 */
export const LANDING_URL = "https://gettreino.com";

/**
 * A donde manda el CTA cuando el destinatario NO es el entrenador.
 *
 * `/abrir/alumno` es un App Link: en un telefono con la app instalada, el
 * sistema operativo la abre y esta URL nunca llega al navegador. Quien la ve
 * como pagina es porque abrio el mail en una computadora o no tiene la app.
 * Esa es la razon de que exista, y no cambia.
 *
 * ── ⚠️ La justificacion que estaba escrita aca era FALSA ──
 *
 * Decia que `LANDING_URL` habia sido «un error medido» porque `gettreino.com`
 * «es de OTRO producto —gimnasios y rankings, en ingles— y dice literalmente
 * "No custom app"».
 *
 * Verificado abriendo la URL el 2026-09-17: `gettreino.com` **es la landing de
 * TREINO**, en castellano, con `/es/user` para el alumno y `/es/gym` para el
 * entrenador. No hay ningun "No custom app" ni nada en ingles.
 *
 * La DECISION sigue siendo la correcta y por eso no se toca: un App Link que
 * abre la app le gana a cualquier pagina web. Lo que se corrige es el motivo,
 * porque un comentario que describe mal el mundo manda a la proxima persona a
 * resolver un problema que no existe — y este ya lo hizo: hay un doc del repo
 * (`docs/legal/ESTADO.md:228`) que dice lo contrario de este parrafo, y quien
 * leyera los dos no tenia forma de saber cual creer.
 */
export const APP_ENTRY_ATHLETE = "https://app.gettreino.com/abrir/alumno";

/**
 * Idem para el entrenador. Es una URL distinta y no un parametro porque el
 * DESTINO es distinto: el profe tiene la app y ademas el Coach Hub web, asi
 * que abriendo desde una computadora tiene algo util que hacer. El atleta solo
 * tiene la app. Mandar a los dos al mismo lado obliga a una de las dos mitades
 * a leer instrucciones que no le corresponden.
 *
 * Reemplazo a una constante `COACH_HUB_URL` —ya borrada— que apuntaba a la
 * raiz de `app.gettreino.com`: mandaba al profe derecho a la web incluso desde
 * el telefono, donde la app le sirve mas. Esa constante sobrevivio sin un solo
 * uso desde entonces, declarando en su dartdoc un rol que ya no cumplia.
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
 *
 * `facturacion` esta EXCLUIDO del tipo del parametro: ese destino no pasa por
 * acá, va por `trainerWebCheckout()`.
 */
export function trainerEntry(
  dest?: Exclude<TrainerDestination, { to: "facturacion" }>,
): string {
  if (!dest) return APP_ENTRY_TRAINER;
  const params = new URLSearchParams({ to: dest.to });
  if (dest.to === "alumno") params.set("id", dest.athleteId);
  return `${APP_ENTRY_TRAINER}?${params.toString()}`;
}

/**
 * A donde manda el CTA de los mails de PLATA del PF (`subscription-grace`,
 * `subscription-downgraded`, `limit-reached`, `exercise-limit-reached`): el
 * Coach Hub web, no la app.
 *
 * NO usa `trainerEntry({ to: "facturacion" })` a propósito, aunque el destino
 * fino sea el mismo. `APP_ENTRY_TRAINER` es un App Link: en un teléfono con la
 * app instalada, el sistema operativo la abre — y la app no vende
 * (`resolvePlanCheckout` sólo da punto de compra en el Coach Hub web, bajo
 * `kIsWeb`; `plan_checkout.dart:240`). El PF que lee uno de estos mails en el
 * teléfono tocaría el botón y no tendría cómo pagar: el Coach Hub web es
 * donde contrata (`docs/legal/contrato-entrenador.md` §8.4,
 * `docs/legal/terminos-suscripcion.md` §3).
 *
 * El dartdoc de `APP_ENTRY_TRAINER` dice que en el teléfono la app le sirve
 * más al profe que la web, y sigue siendo cierto para todo lo demás. Para
 * pagar, no: es lo único que la app no hace.
 *
 * El Coach Hub lee `to` de `Uri.base.queryParameters` al arrancar y lo aplica
 * al aterrizar en la landing, DESPUÉS del login (`coachHubRedirect`,
 * `lib/app/coach_hub_router.dart`; `_coachHubPathFor` manda `facturacion` a
 * `/facturacion/planes`). Por eso la URL es la RAÍZ: en una ruta protegida el
 * `to` se ignora a propósito. Y es el MISMO lugar donde ya aterriza hoy el PF
 * de escritorio: `vercel.json` redirige `/abrir/profe` a la raíz conservando el
 * query (el redirect del #923). El checkout de MP vuelve a esta misma URL
 * (`BACK_URL` en `mp/create-preapproval.ts`).
 */
export function trainerWebCheckout(): string {
  const to: TrainerDestination["to"] = "facturacion";
  return `https://app.gettreino.com/?${new URLSearchParams({ to }).toString()}`;
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
 * Hubo un boton "hero" (a todo el ancho, letra grande y borde animado) para el
 * mail del tope del plan free. Se saco con ese mail: empujaba a pagar a alguien
 * que recien se enteraba de que Pro existe, y es de lo que se asocia a
 * Promociones. Todos los mails usan el mismo boton.
 *
 * @param heading  - Large headline, already escaped.
 * @param bodyHtml - Pre-escaped inner markup.
 * @param ctaLabel - Button text; omit for a mail with no action.
 * @param ctaHref  - Button target. Defaults to the app. The auth mails pass the
 *                   one-time link the Admin SDK minted, which is why this is a
 *                   parameter at all.
 * @param bajaUrl  - URL de baja de los correos promocionales. Con ella el pie
 *                   cambia (ver `pieDeBaja`); sin ella queda como siempre.
 */
function layout(
  heading: string,
  bodyHtml: string,
  preheader: string,
  ctaLabel?: string,
  ctaHref: string = APP_ENTRY_ATHLETE,
  bajaUrl?: string,
): string {
  // Hace falta la etiqueta Y el destino. Sin destino, `ctaHref` llega como ""
  // —los mails de auth pasan el `actionLink` crudo, y `sendQueuedMail` lo BORRA
  // del documento despues de enviar— y se dibujaba un boton con `href=""`, que
  // en un mail no va a ningun lado. Mejor sin boton que con uno muerto.
  const cta = ctaLabel && ctaHref
    ? [
      "<tr><td style=\"padding:8px 32px 32px 32px;\">",
      `<a href="${esc(ctaHref)}" style="display:inline-block;`,
      `background:${MINT};color:${INK};font-weight:700;`,
      "font-size:15px;padding:14px 28px;border-radius:8px;",
      `text-decoration:none;font-family:${FONT};">${esc(ctaLabel)}</a>`,
      "</td></tr>",
    ].join("")
    : "";

  return [
    "<!doctype html>",
    "<html lang=\"es-AR\"><head><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
    "<meta name=\"color-scheme\" content=\"dark\">",
    "<title>TREINO</title>",
    "</head>",
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
    bajaUrl ? pieDeBaja(bajaUrl) : pieComun(),
    "</td></tr></table></body></html>",
  ].join("");
}

/** El pie de siempre: de dónde viene el correo. */
function pieComun(): string {
  return [
    "<div style=\"max-width:520px;padding:20px 8px;font-size:12px;",
    `line-height:1.6;color:${MUTED};font-family:${FONT};">`,
    "Recibís este mail porque tenés una cuenta en TREINO.<br>",
    `<a href="${esc(LANDING_URL)}" style="color:${MUTED};">gettreino.com</a>`,
    "</div>",
  ].join("");
}

/**
 * El pie de un correo promocional (Decreto 1558/01, Anexo I, art. 27, párr. 3).
 *
 * Dos bloques, y la diferencia entre ellos es el punto: la norma pide que la
 * posibilidad de bajarse esté «en forma expresa y destacada». El aviso con el
 * link va en BONE y a 14px —el color de los titulares y los valores resaltados
 * del cuerpo—, no en el MUTED de 12px del pie común, que es lo que se ignora. Lo
 * chico son las transcripciones y el responsable.
 *
 * El aviso REEMPLAZA a «Recibís este mail porque tenés una cuenta»: dice lo
 * mismo con «promocional» adentro, y dos frases iguales seguidas serían ruido.
 *
 * Todo lo que entra a un atributo o a un nodo pasa por `esc()`, también la URL:
 * hoy sólo trae base64url, pero este helper no tiene por qué saberlo.
 */
function pieDeBaja(bajaUrl: string): string {
  return [
    "<div style=\"max-width:520px;padding:20px 8px 0 8px;font-size:14px;",
    `line-height:1.6;color:${BONE};font-family:${FONT};">`,
    esc(AVISO_PROMOCIONAL),
    `<a href="${esc(bajaUrl)}" style="color:${MINT};text-decoration:underline;">`,
    `${esc(TEXTO_DEL_LINK_DE_BAJA)}</a>.`,
    "</div>",
    "<div style=\"max-width:520px;padding:12px 8px 20px 8px;font-size:12px;",
    `line-height:1.6;color:${MUTED};font-family:${FONT};">`,
    `${esc(TRANSCRIPCION_LEY_25326)}<br><br>`,
    `${esc(TRANSCRIPCION_DECRETO_1558)}<br><br>`,
    `${esc(RESPONSABLE_DEL_BANCO)}<br>`,
    `<a href="${esc(LANDING_URL)}" style="color:${MUTED};">gettreino.com</a>`,
    "</div>",
  ].join("");
}

/**
 * El mismo pie, en texto plano. Hoy el text/plain NO tiene pie: sin esto, quien
 * lee en texto no tendría el mecanismo de baja, que es justo lo que la norma
 * pide en toda comunicación de publicidad. La URL va completa: un link que sólo
 * existe dentro de un `<a>` no existe para quien lee en texto.
 */
function pieDeBajaEnTexto(bajaUrl: string): string[] {
  return [
    "",
    "--",
    `${AVISO_PROMOCIONAL}${TEXTO_DEL_LINK_DE_BAJA}:`,
    bajaUrl,
    "",
    TRANSCRIPCION_LEY_25326,
    "",
    TRANSCRIPCION_DECRETO_1558,
    "",
    RESPONSABLE_DEL_BANCO,
  ];
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

/**
 * El código de verificación: un resaltado en grande. Cuando el mail del código
 * lleva los planes, el código va DESPUÉS de ellos (ver `email-code-*`), y ahí
 * tiene que encontrarse de un vistazo. En texto plano es un resaltado más.
 */
class CodigoGrande extends Highlight {}

/** Marca el código de verificación para dibujarlo en grande. */
function codigoGrande(value: string): Highlight {
  return new CodigoGrande(value);
}

/** Renderiza una línea a HTML. Todo se escapa, venga de donde venga. */
function lineToHtml(line: Line): string {
  return line
    .map((seg) =>
      seg instanceof CodigoGrande
        ? `<strong style="color:${BONE};font-size:30px;letter-spacing:6px;">${esc(seg.value)}</strong>`
        : seg instanceof Highlight
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
 * Un plan como card: el nombre chico arriba, lo que trae en grande y —si es
 * pago— el precio a la derecha. Al que chocó un tope lo que le decide la compra
 * es cuánto lugar trae cada plan, y por eso va en grande.
 *
 * La card es SÓLO cómo se ve en HTML. En text/plain el plan sigue siendo la
 * línea de siempre (`linea`), así que no hay un segundo copy que mantener: las
 * dos salen de los mismos datos de `tier-config.ts`.
 */
interface PlanCard {
  nombre: string;
  detalle: string;
  /** Color del `detalle` en el layout compacto; por defecto blanco. */
  colorDetalle?: string;
  /** Color del nombre en el layout compacto; por defecto mint. */
  colorNombre?: string;
  /**
   * Ficha al estilo de las cards de planes de la landing (/es/gym): el `detalle`
   * va como héroe en mint y debajo las filas. Solo la usa el mail del código;
   * los mails de tope siguen con el layout compacto de siempre.
   */
  ficha?: {
    sub?: string;
    filas: { label?: string; valor: string }[];
    destacado?: boolean;
    /** Color del nombre del plan. Por defecto, mint. */
    colorNombre?: string;
    /** Color del héroe. Por defecto, morado. */
    colorHero?: string;
  };
  precio?: { monto: string; periodo: string };
  linea: Line;
}

/** Varios planes seguidos, dibujados como cards apiladas. */
class Planes {
  constructor(readonly cards: PlanCard[]) {}
}

/** Lo que va en el cuerpo de un mail: un párrafo, o un grupo de planes. */
type Block = Line | Planes;

/**
 * Las cards, una debajo de la otra. Con hasta cuatro planes y ~456px de ancho
 * útil, dos columnas obligarían a media queries que Gmail no siempre respeta.
 * Tablas e inline styles por lo mismo que el resto del layout, y nada de
 * imágenes ni botones propios: cuanto más se parece a un folleto, más fácil cae
 * en Promociones (ver `free-limit-reached`). Todo pasa por `esc()`, aunque hoy
 * los valores salgan de constantes nuestras.
 */
function fichaToHtml(c: PlanCard & { ficha: NonNullable<PlanCard["ficha"]> }): string {
  const { ficha } = c;
  const borde = ficha.destacado ? `1.5px solid ${MINT}` : `1px solid ${PLAN_CARD_BORDE}`;
  const tilde = `<span style="color:${MINT};font-weight:700;">&#10003;</span>&nbsp; `;
  const filas = ficha.filas.map((f) => {
    const contenido = f.label ?
      `${esc(f.label)}: <strong style="color:${BONE};">${esc(f.valor)}</strong>` :
      esc(f.valor);
    return `<div style="padding-top:8px;font-size:14px;line-height:1.45;color:${MUTED};">${tilde}${contenido}</div>`;
  });
  return [
    "<tr><td style=\"padding:0 0 12px 0;\">",
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"",
    ` style="border-collapse:separate;background:${PLAN_CARD};border:${borde};`,
    `border-radius:16px;font-family:${FONT};"><tr>`,
    "<td valign=\"top\" style=\"padding:20px 22px;\">",
    "<div style=\"font-size:13px;font-weight:700;letter-spacing:2px;text-transform:uppercase;line-height:1.4;",
    `color:${ficha.colorNombre ?? MINT};">${esc(c.nombre)}</div>`,
    "<div style=\"padding-top:8px;font-size:28px;font-weight:800;line-height:1.15;",
    `color:${ficha.colorHero ?? MORADO};">${esc(comoTitulo(c.detalle))}</div>`,
    ficha.sub ?
      `<div style="padding-top:4px;font-size:13px;line-height:1.4;color:${MUTED};">${esc(ficha.sub)}</div>` :
      "",
    "<div style=\"padding-top:6px;\"></div>",
    ...filas,
    "</td></tr></table>",
    "</td></tr>",
  ].join("");
}

function planesToHtml(planes: Planes): string {
  const cards = planes.cards.map((c) => {
    if (c.ficha) return fichaToHtml({ ...c, ficha: c.ficha });
    const precio = c.precio
      ? [
        "<td align=\"right\" valign=\"middle\" style=\"padding:14px 16px 14px 8px;white-space:nowrap;\">",
        `<div style="font-size:18px;font-weight:700;line-height:1.3;color:${BONE};">`,
        `${esc(c.precio.monto)}</div>`,
        `<div style="font-size:12px;line-height:1.4;color:${MUTED};">${esc(c.precio.periodo)}</div>`,
        "</td>",
      ].join("")
      : "";
    return [
      "<tr><td style=\"padding:0 0 8px 0;\">",
      "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"",
      ` style="border-collapse:separate;background:${PLAN_CARD};border:1px solid ${PLAN_CARD_BORDE};`,
      `border-radius:12px;font-family:${FONT};"><tr>`,
      "<td valign=\"middle\" style=\"padding:14px 16px;\">",
      "<div style=\"font-size:12px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;",
      `line-height:1.4;color:${c.colorNombre ?? MINT};">${esc(c.nombre)}</div>`,
      `<div style="padding-top:2px;font-size:16px;font-weight:700;line-height:1.35;color:${c.colorDetalle ?? BONE};">`,
      `${esc(comoTitulo(c.detalle))}</div>`,
      "</td>",
      precio,
      "</tr></table>",
      "</td></tr>",
    ].join("");
  });
  return [
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"",
    " style=\"margin:4px 0 12px 0;\">",
    ...cards,
    "</table>",
  ].join("");
}

/**
 * «alumnos sin límite» → «Alumnos sin límite». Las etiquetas (`cupoLabel` y
 * sus hermanas) van en minúscula porque se escriben DENTRO de una frase; en la
 * card son un título y van en mayúscula. Sólo acá: el texto plano sigue igual.
 */
function comoTitulo(texto: string): string {
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}

/** Un bloque a HTML: el párrafo de siempre, o las cards. */
function blockToHtml(block: Block): string {
  return block instanceof Planes
    ? planesToHtml(block)
    : `<p style="margin:0 0 12px 0;">${lineToHtml(block)}</p>`;
}

/** Un bloque a text/plain: una línea por párrafo y una por plan, como siempre. */
function blockToText(block: Block): string[] {
  return block instanceof Planes
    ? block.cards.map((c) => lineToText(c.linea))
    : [lineToText(block)];
}

/**
 * Builds both MIME parts from a heading, body lines, and an optional CTA.
 *
 * When the CTA points somewhere other than the app, the raw URL is appended to
 * the text/plain part. A password-reset mail whose only link lives inside an
 * HTML anchor is unusable for anyone reading in plain text — and unusable is
 * the same as broken when it is the path back into a locked account.
 *
 * `bajaUrl` agrega el pie de baja de los correos promocionales a las DOS partes.
 * Lo pasa `renderMail`, no cada `case`: ver el `build` local de allá.
 */
function buildMail(
  subject: string,
  heading: string,
  lines: Block[],
  ctaLabel?: string,
  ctaHref?: string,
  bajaUrl?: string,
): RenderedMail {
  const bodyHtml = lines.map(blockToHtml).join("");

  const textLines = [heading, "", ...lines.flatMap(blockToText)];
  if (ctaHref) textLines.push("", ctaHref);
  if (bajaUrl) textLines.push(...pieDeBajaEnTexto(bajaUrl));

  // El preheader se DERIVA de la primera linea del cuerpo, no es un parametro
  // por template. Un campo mas que cada `case` tiene que acordarse de pasar es
  // un campo que el proximo MailKind va a olvidar, y el sintoma —una vista
  // previa con basura en la bandeja— no lo agarra ningun test que no lo busque
  // a proposito. Derivarlo lo hace imposible de olvidar, y la primera linea ES
  // el resumen del mail: si no lo fuera, el problema seria el copy.
  const preheader = (lines.length > 0 ? blockToText(lines[0])[0] : undefined) ?? heading;

  return {
    subject,
    html: layout(heading, bodyHtml, preheader, ctaLabel, ctaHref, bajaUrl),
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
 * Un plan del PF como card: el nombre, lo que trae (`detalle`) y, si es pago,
 * el precio por mes. En texto plano: «Plan 1 · 7 alumnos · $ 12.000 por mes».
 * El Free no lleva precio, ni en la card ni en la línea.
 */
function cardDePlanPf(tier: SubscriptionTier, detalle: string): PlanCard {
  const nombre = TIER_LABELS[tier];
  if (tier === "free") return { nombre, detalle, linea: [strong(nombre), ` · ${detalle}`] };
  const monto = formatArs(TIER_PRICES_ARS[tier].monthly);
  return {
    nombre,
    detalle,
    precio: { monto, periodo: "por mes" },
    linea: [strong(nombre), ` · ${detalle} · ${monto} por mes`],
  };
}

/**
 * Los planes del PF en el mail del código: una ficha por plan, SIN precio, con
 * el mismo lenguaje que las cards de la landing (/es/gym): el cupo de alumnos
 * como héroe y debajo ejercicios propios y plantillas. Plan 1 va destacado,
 * como la «recomendada» de la pantalla de planes.
 *
 * Todo sale de `tier-config.ts`, en el orden de `TIER_LABELS` (de Free a
 * Plan 3). El precio no va: se ve en el checkout al que lleva VER LOS PLANES, y
 * un monto escrito acá es un monto más que mantener de memoria.
 */
function planesDelPf(): Block[] {
  const tiers = Object.keys(TIER_LABELS) as SubscriptionTier[];
  return [
    new Planes(
      tiers.map((tier): PlanCard => {
        const nombre = TIER_LABELS[tier];
        const alumnos = TIER_WEIGHT_LIMITS[tier];
        const ejercicios = TIER_CUSTOM_EXERCISE_LIMITS[tier];
        const plantillas = TIER_TEMPLATE_LIMITS[tier];
        const sinTope = (n: number | null): string => (n === null ? "Sin tope" : String(n)); // i18n: email comercial
        const pausados = "Cada alumno pausado cuenta 0,5"; // i18n: email comercial
        const detalle =
          tier === "free" ? "Gratis" : alumnos === null ? "Alumnos sin tope" : `Hasta ${cupoLabel(alumnos)}`;
        const sub =
          tier === "free" && alumnos !== null ? `Hasta ${cupoLabel(alumnos)} activos · ${pausados.toLowerCase()}` :
            alumnos === null ? undefined : pausados;
        const filas = [
          { label: "Ejercicios propios", valor: sinTope(ejercicios) },
          { label: "Plantillas", valor: sinTope(plantillas) },
        ];
        const textoPlano = [
          detalle,
          ...(tier === "free" && sub ? [sub] : []),
          ...filas.map((f) => `${f.label}: ${f.valor}`),
        ];
        return {
          nombre,
          detalle,
          ficha: { sub, filas, destacado: tier === "plan1", colorNombre: MORADO, colorHero: MINT },
          // En el texto plano el cupo del Free no puede perderse: en el HTML es el
          // sub del héroe «Gratis», y acá no hay héroe.
          linea: [strong(nombre), ` · ${textoPlano.join(" · ")}`],
        };
      }),
    ),
  ];
}

/**
 * Los planes del alumno en el mail del código: el gratis y TREINO Pro (la
 * destacada) con lo que trae, SIN precio (se ve en el checkout). Los topes de
 * Pro salen de `athlete-plan-config.ts`, que `athlete-pro-limites.test.ts` ata
 * a los de la app. Sólo lo recibe quien hoy está en el gratis (ver
 * `muestraPlanes`), así que «el que tenés hoy» no miente.
 */
function planesDelAlumno(): Block[] {
  const detalle = "Sin los topes del plan gratis";
  const beneficios = [
    `Rutinas de hasta ${ATHLETE_PRO_MAX_ROUTINE_DAYS} días`,
    `Hasta ${ATHLETE_PRO_MAX_ROUTINE_WEEKS} semanas, con periodización`,
    "Todas las plantillas del catálogo, de principiante a avanzado",
    "Personalizar cualquier plantilla del catálogo",
    `Hasta ${ATHLETE_PRO_MAX_OWN_ROUTINES} rutinas propias`,
    "Gráficos de 3 meses y 1 año",
  ]; // i18n: email comercial
  return [
    new Planes([
      {
        nombre: "Gratis",
        detalle: "El que tenés hoy",
        colorDetalle: MINT,
        colorNombre: MORADO,
        linea: [strong("Gratis"), " · el que tenés hoy."],
      },
      {
        nombre: "TREINO Pro",
        detalle,
        ficha: {
          sub: "Todo lo que ya usás.",
          filas: beneficios.map((valor) => ({ valor })),
          destacado: true,
          colorNombre: MORADO,
          colorHero: MINT,
        },
        linea: [strong("TREINO Pro"), ` · ${detalle.toLowerCase()}: ${beneficios.join("; ").toLowerCase()}.`],
      },
    ]),
  ];
}

/**
 * Los planes pagos con MÁS lugar que el tope que el PF acaba de chocar, como
 * cards. En texto plano: «Plan 2 · 15 alumnos · $ 22.000 por mes».
 *
 * `limites` es el mapa de ESE tope (alumnos, ejercicios o plantillas, de
 * `tier-config.ts`) y `etiqueta` lo escribe: al que chocó ejercicios le sirve
 * saber cuántos ejercicios trae cada plan, no cuántos alumnos. Mostrar planes
 * que no le dan más lugar es mandarlo a elegir uno que no le resuelve nada.
 *
 * `actual` viene de `limitParam`, que distingue dos ausencias: `undefined` es
 * que el doc no trajo el dato, y ahí van todos los pagos; `null` es que su plan
 * ya no tiene tope, y ahí no va ninguno —ofrecerle «más lugar» sería mentir—.
 * Vacía, cada mail vuelve a su frase de siempre.
 */
function planesConMasLugar(
  limites: Record<SubscriptionTier, number | null>,
  etiqueta: (limite: number | null) => string,
  actual: number | null | undefined,
): PlanCard[] {
  if (actual === null) return [];
  const pagos = Object.keys(TIER_PRICES_ARS) as Exclude<SubscriptionTier, "free">[];
  return pagos
    .filter((tier) => {
      const limite = limites[tier];
      return actual === undefined || limite === null || limite > actual;
    })
    .map((tier) => cardDePlanPf(tier, etiqueta(limites[tier])));
}

/**
 * La venta de los mails de tope del PF: la frase que presenta los planes y sus
 * cards, o —si no hay ninguno con más lugar— la frase de siempre, sola.
 */
function ofertaDePlanes(conPlanes: string, sinPlanes: string, planes: PlanCard[]): Block[] {
  return planes.length > 0 ? [[conPlanes], new Planes(planes)] : [[sinPlanes]];
}

/** «TREINO Pro · $ 3.500 por mes o $ 35.000 por año.» El texto plano de su card. */
function lineaDeTreinoPro(): Line {
  return [
    strong("TREINO Pro"),
    ` · ${formatArs(ATHLETE_PRICES_ARS.monthly)} por mes o ` +
      `${formatArs(ATHLETE_PRICES_ARS.annual)} por año.`,
  ];
}

/**
 * TREINO Pro como card, con los dos precios en el detalle: el ciclo se elige en
 * el checkout. Lo comparten el mail del código y el del tope.
 */
function cardDeTreinoPro(): PlanCard {
  return {
    nombre: "TREINO Pro",
    detalle:
      `${formatArs(ATHLETE_PRICES_ARS.monthly)} por mes o ` +
      `${formatArs(ATHLETE_PRICES_ARS.annual)} por año`,
    linea: lineaDeTreinoPro(),
  };
}

/**
 * "60 ejercicios propios" · "1 ejercicio propio".
 *
 * Espejo de `cupoLabel`, mismo motivo: singular no cosmético (el tope Free es
 * 20 hoy, pero un tier de 1 haría que el mail dijera "1 ejercicios propios").
 *
 * `exercise-limit-reached` sólo se encola cuando `count >= limit`
 * (`decideTrainerLimitMail` en `trainer-limit-mail.ts`), así que `limit`
 * llega siempre como un número real — pero la firma pide `number` a secas y
 * no `number | null` porque, a diferencia de `cupoLabel`, esta función nunca
 * tiene que decidir "sin límite": ese caso ni siquiera genera el mail.
 */
function ejerciciosLabel(limit: number): string {
  return limit === 1 ? "1 ejercicio propio" : `${limit} ejercicios propios`; // i18n: email comercial
}

/**
 * "3 plantillas" · "1 plantilla".
 *
 * Espejo de `ejerciciosLabel`, mismo motivo y misma razón para el singular no
 * cosmético: el tope Free de plantillas es 3 hoy
 * (`limite-plantillas-pf.md` §1, P1), pero un tier de 1 haría que el mail
 * dijera "1 plantillas".
 *
 * `template-limit-reached` sólo se encola cuando `count >= limit`, igual que
 * `exercise-limit-reached` — ver `decideTrainerLimitMail` — así que `limit`
 * llega siempre como un número real.
 */
function plantillasLabel(limit: number): string {
  return limit === 1 ? "1 plantilla" : `${limit} plantillas`; // i18n: email comercial
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
 * Nombre visible del plan. La tabla vive en `tier-config.ts` (`TIER_LABELS`),
 * compartida con el nombre del plan que se manda a Mercado Pago.
 *
 * El productor manda el CODIGO (`plan2`), no la etiqueta: misma regla que
 * `reason`. Un tier que no reconocemos cae a vacio y la oracion sigue leyendose
 * ("No pudimos cobrar tu suscripción."), en vez de imprimir el codigo crudo.
 */
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
 * El ASUNTO de los kinds de `KINDS_DE_PUBLICIDAD` sale con «Publicidad: »
 * adelante (Disp. DNPDP 4/2009, art. 2; ver esa constante). Es lo único que
 * cambia: el cuerpo y el texto plano son los mismos.
 *
 * @param kind     - Selects the template.
 * @param params   - Template values, as persisted on the queue doc.
 * @param opciones - Lo que `sendQueuedMail` decide al enviar: el pie de baja de
 *                   los correos promocionales y si el mail lleva su bloque
 *                   comercial. Sin ellas, el mail sale como siempre.
 */
export function renderMail(
  kind: MailKind,
  params: MailParams,
  opciones: OpcionesDeMail = {},
): RenderedMail {
  const { bajaDePromocionales, comercial = true } = opciones;

  // Este `build` LOCAL tapa al de módulo (`buildMail`) a propósito: el pie de
  // baja es una decisión de ENVÍO, no de cada plantilla, y pasarlo a mano por
  // los 30 `case` es el campo que el próximo MailKind se va a olvidar de
  // pasar —y el síntoma sería un correo promocional sin el mecanismo de baja—.
  // Así NINGÚN `case` puede olvidarlo, porque no lo ve.
  //
  // Lo mismo vale para el «Publicidad: » del asunto: se decide acá, por `kind`,
  // y no en cada `case`. El próximo kind comercial no tiene que acordarse de
  // nada más que de entrar en `KINDS_DE_PUBLICIDAD`.
  const prefijoDelAsunto = KINDS_DE_PUBLICIDAD.includes(kind) ? PREFIJO_DE_PUBLICIDAD : "";
  const build = (
    subject: string,
    heading: string,
    lines: Block[],
    ctaLabel?: string,
    ctaHref?: string,
  ): RenderedMail =>
    buildMail(
      `${prefijoDelAsunto}${subject}`,
      heading,
      lines,
      ctaLabel,
      ctaHref,
      bajaDePromocionales,
    );

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

  // ── El código de 6 dígitos (`auth/codigo-de-verificacion.ts`) ──────────────
  //
  // Sin los planes, el código va en el ASUNTO y como titular: es lo único que
  // el usuario vino a buscar, y en la notificación del teléfono se lee sin
  // abrir el mail.
  //
  // CON los planes, el orden se invierte, y a propósito. Este mail es el ÚNICO
  // lugar donde se le puede decir que los planes y los pagos van por mail: la
  // app no puede, porque un llamado a pagar afuera impreso en el binario tumba
  // la exención 3.1.3(f) (ver `anti_steering_movil_test.dart`). Pero con el
  // código en el asunto nadie abre el mail: lo copia de la notificación, y el
  // resto no existe. Por eso, cuando lleva los planes:
  //   - el asunto NO lleva el código;
  //   - la primera línea es el aviso, y como el preheader se deriva de ella
  //     (ver `buildMail`), se lee en la bandeja y en la notificación;
  //   - los planes van antes que el código: para llegar a él, se pasa por lo
  //     que el mail vino a decir.
  //
  // Los planes salen de `tier-config.ts` y `athlete-plan-config.ts`: los mismos
  // números que cobra el checkout. Un precio escrito a mano acá se separa del
  // real el día que alguien lo mueva.
  //
  // El bloque de planes va con TRES llaves: `showPlans: "1"` (al encolar: le
  // sirve, ver `muestraPlanes`), `comercial` (al enviar: no se opuso, ver
  // `bloqueComercial`) y la URL de baja (el pie que `build` agrega con ella).
  // Sin cualquiera, el código y nada más. La tercera hace que el bloque NUNCA
  // salga sin pie: un doc sin `bloqueComercial` (encolado antes del deploy,
  // reencolado a mano) o un envío sin la clave de baja salen sin publicidad.
  case "email-code-athlete":
  case "email-code-trainer": {
    const codigo = params.codigo ? String(params.codigo) : "";
    const esPf = kind === "email-code-trainer";
    const conPlanes = params.showPlans === "1" && comercial && Boolean(bajaDePromocionales);
    const ignorar: Line = ["Si no creaste una cuenta en TREINO, ignorá este mail."];
    if (!conPlanes) {
      return build(
        codigo ? `${codigo} es tu código de TREINO` : "Tu código de TREINO", // i18n: email transaccional
        codigo || "Confirmá tu mail",
        [
          [
            "Es tu código para confirmar tu mail en TREINO. Ingresalo en la app: " +
              "vence en 15 minutos.",
          ],
          ignorar,
        ],
      );
    }
    return build(
      "Tu código para entrar a TREINO", // i18n: email transaccional
      "Todo lo de tu plan llega por acá",
      [
        [
          esPf ?
            "En TREINO, los planes y los pagos van por mail y por el Coach Hub " +
              "web: todo te llega por acá." :
            "En TREINO, los planes y los pagos van por mail: todo te llega por acá.",
        ],
        ...(esPf ? planesDelPf() : planesDelAlumno()),
        ["Tu código para entrar a TREINO (vence en 15 minutos):"],
        [codigoGrande(codigo)],
        ignorar,
      ],
      "VER LOS PLANES",
      esPf ? trainerWebCheckout() : `${LANDING_URL}/es/suscripcion/checkout`,
    );
  }

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

  // El correo NO lleva el contenido reportado, solo el id, el tipo de objetivo
  // y el motivo. Un mail con el texto adentro es una copia de datos personales
  // de terceros viajando a un buzon —y en el chat pueden ser datos de salud—.
  // El contenido se mira en la cola, autenticado.
  case "moderation-report-created":
    return build(
      "Reporte nuevo para revisar",
      "Moderación",
      [
        ["Entró un reporte y el reloj de las 24 horas ya arrancó."],
        [strong("Motivo: "), String(params.reason ?? "sin motivo")],
        [strong("Tipo: "), String(params.targetKind ?? "?")],
        [strong("Reporte: "), String(params.reportId ?? "?")],
        ["El contenido se mira en la cola, autenticado — no viaja en este mail."],
      ],
      // SIN boton, a proposito. La ruta de la cola todavia no existe —es el
      // slice 2 de este cambio— y `build` cae a `APP_ENTRY_ATHLETE` cuando no
      // le pasan `ctaUrl`. Un boton que dice "ABRIR LA COLA" y lleva a la app
      // del alumno es peor que ninguno: el moderador lo toca, aterriza en otro
      // lado, y la proxima vez ya no lo toca.
      //
      // Cuando la ruta exista, el CTA vuelve con SU url — no con el fallback.
    );

  // El correo NO lleva el contenido reportado, ni el motivo textual de quien
  // denuncio, ni nada que lo identifique — mismo criterio que
  // `moderation-report-created`, arriba, y el docstring de
  // `notify-report-created.ts:9-17`. Es un aviso sobrio: se revisó contenido
  // de la cuenta y se tomó una medida.
  case "moderation-user-warned":
    return build(
      "Revisamos contenido tuyo en TREINO", // i18n: email transaccional
      "Advertencia de moderación",
      [
        ["Un moderador de TREINO revisó contenido de tu cuenta."],
        ["Como resultado, tu cuenta recibió una advertencia."],
        [
          "Te pedimos que repases las ", strong("Normas de Comunidad"),
          " antes de tu próxima publicación.",
        ],
      ],
      "IR A TREINO",
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

  // ── El PF que nunca pago y choco el cupo del plan Free ──────────────────
  //
  // NINGUNA PALABRA DE DEUDA ACA, y no es estilo: es que seria FALSO. El
  // destinatario no tiene `subscription` en su documento, asi que no hay cobro
  // fallido, ni pausa, ni nada atrasado. «Regularizá» y «poné al día» son de
  // sus dos hermanos y no se copian; decirselo a alguien que no debe nada lo
  // manda a buscar un problema que no tiene.
  //
  // Y por el mismo motivo el CTA es «VER LOS PLANES» y no «AMPLIAR MI PLAN»:
  // todavia no hay un plan que ampliar.
  //
  // LA LINEA DE «tus alumnos no pierden nada» SE QUEDA, aunque el contexto sea
  // otro. El PR #758 la nombra como el peor error posible de todo este trabajo:
  // sugerir que el alumno perdio algo es falso —conserva rutinas, historial y
  // chat— y ademas le mueve la presion a quien no decide. Vale igual acá: el
  // alumno numero 3 no se entero de nada.
  //
  // El vocabulario («en solo lectura», «verlos pero no editarles rutinas ni
  // notas») esta copiado LITERAL de `blocked_students_screen.dart`, igual que
  // en el downgrade. Son el mismo hecho contado por dos canales: si divergen,
  // el PF cree que son dos problemas distintos.
  //
  // CON `comercial: false` SE VA EL BLOQUE DE VENTA y nada más: la lista de
  // planes con más lugar (o, si no hay ninguno, la línea «hay planes más
  // grandes») y el botón VER LOS PLANES (también su URL en el texto plano).
  // Lo operativo —el tope, quiénes quedaron en solo lectura, que no pierden
  // nada— le llega igual a quien se opuso a lo comercial: tiene que enterarse
  // de que sus alumnos quedaron bloqueados. Ver `bloqueComercial`.
  case "limit-reached": {
    const blocked = countParam(params.blockedCount);
    const limit = limitParam(params.limit);

    const lines: Block[] = [
      limit === undefined || limit === null
        ? ["Llegaste al tope de alumnos de tu cuenta."]
        : ["Llegaste al tope de tu cuenta: ", strong(cupoLabel(limit)), "."],
    ];

    // `blocked` puede ser 0 legitimamente si el estado cambia entre que se
    // encola el mail y que se renderiza —el outbox re-renderiza al ENVIAR—,
    // por ejemplo si el PF saca un alumno en el medio. La frase de abajo tiene
    // que seguir siendo cierta en ese caso, y por eso no nombra un numero.
    lines.push(
      blocked === 1
        ? ["1 alumno quedó en solo lectura: lo podés ver, pero no editarle " +
          "rutinas ni notas."]
        : blocked > 1
          ? [`${blocked} alumnos quedaron en solo lectura: los podés ver, ` +
            "pero no editarles rutinas ni notas."]
          : ["Los alumnos que pasen ese tope quedan en solo lectura: los podés " +
            "ver, pero no editarles rutinas ni notas."],
      ["Tus alumnos no pierden nada: conservan sus rutinas, su historial y el chat."],
    );
    if (comercial) {
      lines.push(
        ...ofertaDePlanes(
          "Si querés seguir sumando, estos planes tienen más lugar:",
          "Si querés seguir sumando, hay planes más grandes.",
          planesConMasLugar(TIER_WEIGHT_LIMITS, cupoLabel, limit),
        ),
      );
    }

    return build(
      "Llegaste al tope de alumnos de tu cuenta", // i18n: email transaccional
      "Llegaste al tope",
      lines,
      // Sin etiqueta Y sin destino: `buildMail` agrega la URL al texto plano
      // apenas hay `ctaHref`, y un botón que no existe no puede dejar su link.
      comercial ? "VER LOS PLANES" : undefined,
      comercial ? ctaUrl : undefined,
    );
  }

  // ── El ALUMNO que se quedo sin cobertura ────────────────────────────────
  //
  // NO NOMBRA AL ENTRENADOR, y es la decision central del copy. El disparador
  // es `athletePaywallEnforced` pasando a `true`, y eso tiene DOS causas: que
  // el profe termino el vinculo, o que la suscripcion propia del alumno
  // vencio. «Tu profe te dio de baja» es FALSO en el segundo caso, y en el
  // primero es una acusacion que TREINO no tiene por que hacer entre dos
  // personas que se siguen conociendo.
  //
  // NO ENUMERA LOS TOPES, y tampoco es pereza. Los numeros del plan free viven
  // en `athlete_entitlement.dart` (`kFreeMaxOwnRoutines`, `kFreeMaxRoutineDays`,
  // `kFreeMaxRoutineWeeks`) y ya se desincronizaron una vez entre la constante,
  // `firestore.rules` y el texto del `.arb` — y el que le habla al usuario fue
  // el ultimo en enterarse. Un cuarto lugar con los mismos numeros es un cuarto
  // lugar que se puede pudrir. El mail dice QUE cambia; la app, que lee las
  // constantes, dice CUANTO.
  //
  // LO PRIMERO QUE DICE ES QUE NO SE PIERDE NADA. Quien recibe esto acaba de
  // perder acceso sin haber hecho nada, y el miedo razonable es que se le hayan
  // borrado los entrenamientos. Contestar eso ANTES de ofrecer nada es la
  // diferencia entre un aviso y un aprieto.
  // ── El alumno que choco un tope del plan free ───────────────────────────
  //
  // NO NOMBRA EL TOPE CONCRETO, aunque `params.tope` lo trae. El parametro
  // viaja igual porque sirve para medir cual muerde mas, pero el cuerpo habla
  // en general: nombrarlo obligaria a un case por cada valor del enum
  // `FreePlanLimit` de Dart —ocho hoy— y esa lista se desincroniza el dia que
  // alguien agregue el noveno. Es el mismo pozo que los numeros del plan free,
  // que ya se separaron una vez entre la constante, firestore.rules y el .arb.
  //
  // EL ASUNTO RECONOCE EL INTENTO. Quien recibe esto quiso hacer algo y no
  // pudo, y lo primero que lee —en la bandeja— nombra eso. El cuerpo no lo
  // repite: el preheader sale de la primera linea y sigue la frase del asunto.
  //
  // NO PROMETE "SIN LIMITES": Pro tambien tiene techo (`kMaxRoutineDays`,
  // `kMaxRoutineWeeks`).
  //
  // INVITA A MIRAR, NO EMPUJA A PAGAR. La version anterior era titulo y un
  // boton gigante de «CONTINUAR AL PAGO»: le hablaba a alguien que ya decidio
  // pagar, y el que choco un tope recien se entera de que Pro existe. Ahora es
  // una linea, la card de TREINO Pro con su precio (de `athlete-plan-config.ts`,
  // el mismo que cobra el checkout) y «VER LOS PLANES» con el boton normal. Una
  // sola card, sin imagen ni boton propio: sigue sin parrafos. La
  // primera version explicaba en cuatro que el historial no se pierde, y eso le
  // habla a alguien con miedo; el que choco un tope no perdio nada, quiere
  // seguir. El boton a todo el ancho con borde animado es, ademas, de lo que se
  // asocia a Promociones, donde Gmail no notifica. `ctaUrl` es el checkout, que
  // muestra los planes: «VER LOS PLANES» no miente.
  case "free-limit-reached":
    return build(
      "Lo que querías hacer está en TREINO Pro", // i18n: email comercial
      "Estás a un paso.",
      [
        ["Mirá qué incluye y elegí si te sirve."],
        new Planes([cardDeTreinoPro()]),
      ],
      "VER LOS PLANES →",
      ctaUrl,
    );

  // ── El PF que chocó el tope de ejercicios propios de su plan ────────────
  //
  // limite-ejercicios-pf.md §3 PR4. Hermano de `limit-reached` (alumnos), con
  // la MISMA regla de fondo: dice el ESTADO —tope, cuántos tiene, qué puede
  // seguir haciendo— y nunca inventa una causa que el dato no confirma.
  //
  // NINGUNA PALABRA DE PERDIDA. E3 del plan es expresamente que bajar de plan
  // NUNCA borra ni bloquea lo que ya existe: editar, usar, asignar y borrar
  // siguen permitidos siempre, incluso por encima del tope. Insinuar lo
  // contrario —aunque sea de pasada— sería la misma mentira cara que evita el
  // resto de esta capa (`athlete-coverage-lost`, `subscription-downgraded`).
  //
  // CON `prefKey`: comunicación comercial, ver `trainer-limit-mail.ts`.
  case "exercise-limit-reached": {
    const limit = limitParam(params.limit);
    const label = typeof limit === "number" ? ejerciciosLabel(limit) : undefined;

    return build(
      "Llegaste al tope de ejercicios propios de tu plan", // i18n: email comercial
      "Llegaste al tope",
      [
        label
          ? ["Llegaste al tope de tu plan: ", strong(label), "."]
          : ["Llegaste al tope de ejercicios propios de tu plan."],
        [
          "Conservás todos los que ya tenés: podés seguir usándolos, " +
            "editarlos, asignarlos y borrarlos.",
        ],
        ["Lo único que se frena es crear ejercicios nuevos por encima del límite."],
        ...ofertaDePlanes(
          "Si necesitás más lugar, estos planes tienen más:",
          "Si necesitás más lugar, hay planes más grandes.",
          planesConMasLugar(
            TIER_CUSTOM_EXERCISE_LIMITS,
            (l) => (l === null ? "ejercicios propios sin límite" : ejerciciosLabel(l)), // i18n: email comercial
            limit,
          ),
        ),
      ],
      "VER LOS PLANES",
      ctaUrl,
    );
  }

  // ── El PF que chocó el tope de plantillas de su plan ────────────────────
  //
  // limite-plantillas-pf.md §3 PR4. Hermano de `exercise-limit-reached`, con
  // la MISMA regla de fondo y la misma razón: E3/P5 de ese plan es que bajar
  // de plan NUNCA borra ni bloquea una plantilla ya creada — se puede seguir
  // usando, editando, asignando, publicando y archivando por encima del
  // límite. Lo único que se frena es crear una nueva o restaurar una
  // archivada.
  //
  // CON `prefKey`: comunicación comercial, ver `trainer-limit-mail.ts`.
  case "template-limit-reached": {
    const limit = limitParam(params.limit);
    const label = typeof limit === "number" ? plantillasLabel(limit) : undefined;

    return build(
      "Llegaste al tope de plantillas de tu plan", // i18n: email comercial
      "Llegaste al tope",
      [
        label
          ? ["Llegaste al tope de tu plan: ", strong(label), "."]
          : ["Llegaste al tope de plantillas de tu plan."],
        [
          "Conservás todas las que ya tenés: podés seguir usándolas, " +
            "editándolas, asignándolas, publicándolas y archivándolas.",
        ],
        [
          "Lo único que se frena es crear plantillas nuevas o restaurar una " +
            "archivada por encima del límite.",
        ],
        ...ofertaDePlanes(
          "Si necesitás más lugar, estos planes tienen más:",
          "Si necesitás más lugar, hay planes más grandes.",
          planesConMasLugar(
            TIER_TEMPLATE_LIMITS,
            (l) => (l === null ? "plantillas sin límite" : plantillasLabel(l)), // i18n: email comercial
            limit,
          ),
        ),
      ],
      "VER LOS PLANES",
      ctaUrl,
    );
  }

  // ── El PF que chocó el tope de alumnos de su plan ───────────────────────
  //
  // Hermano de `exercise-limit-reached`/`template-limit-reached`, con la
  // MISMA regla de fondo, pero con un matiz propio: acá el rechazo pasa
  // ANTES de que el vínculo se promueva (`syncTrainerLoad` en
  // `promote-link.ts` frena el `accept`/`resume` en la transacción), así que
  // no hay "los que ya tenía quedan en solo lectura" como en `limit-reached`
  // — ese vínculo nunca se activó. Lo único que cambió es que ESE alumno en
  // particular no pudo sumarse; los que ya estaban activos no pierden nada,
  // ni siquiera de forma indirecta.
  //
  // NO PROMETE que el vínculo se resuelve solo. El PF tiene que volver a
  // intentar `accept`/`resume` después de subir de plan — el mail no lo hace
  // por él.
  //
  // CON `prefKey`: comunicación comercial, ver `trainer-limit-mail.ts`.
  case "student-limit-reached": {
    const limit = limitParam(params.limit);
    const label = typeof limit === "number" ? cupoLabel(limit) : undefined;

    return build(
      "Llegaste al tope de alumnos de tu plan", // i18n: email comercial
      "Llegaste al tope",
      [
        label
          ? ["Llegaste al tope de tu plan: ", strong(label), "."]
          : ["Llegaste al tope de alumnos de tu plan."],
        [
          // «Activar ese vínculo», no «sumar un alumno nuevo»: el mismo mail
          // sale cuando se rechaza ACEPTAR una solicitud y cuando se rechaza
          // REANUDAR un vínculo pausado, y en el segundo caso el alumno no es
          // nuevo.
          "No se pudo activar ese vínculo: tus alumnos actuales no " +
            "pierden nada, conservan sus rutinas, su historial y el chat.",
        ],
        ...ofertaDePlanes(
          "Si querés seguir sumando, estos planes tienen más lugar:",
          "Si querés seguir sumando, hay planes más grandes.",
          planesConMasLugar(TIER_WEIGHT_LIMITS, cupoLabel, limit),
        ),
      ],
      "VER LOS PLANES",
      ctaUrl,
    );
  }

  case "athlete-coverage-lost":
    return build(
      "Tu lugar en TREINO ya no está cubierto", // i18n: email comercial
      "Tus entrenamientos siguen donde están",
      [
        ["Tu cuenta de TREINO pasó al plan gratis."],
        [
          strong("No perdés nada de lo que ya hiciste"),
          ": tus rutinas, tu historial y tus medidas siguen exactamente donde " +
            "estaban, y los vas a seguir viendo.",
        ],
        [
          "Lo que cambia es lo que podés armar de acá en adelante: el plan " +
            "gratis tiene topes más chicos para las rutinas que te armás vos.",
        ],
        // Sin esta línea, «tus rutinas siguen exactamente donde estaban» le
        // mentía a quien venía entrenando una plantilla paga: queda con candado
        // (la regla de `athlete_entitlement.dart`, sin excepción para quien ya
        // la seguía). «Si te pasás», no «si volvés»: también lo recibe quien
        // estaba cubierto por su PF y nunca pagó.
        [
          "Las plantillas del plan pago quedan con candado: las seguís viendo " +
            "y, si te pasás a Pro, seguís donde estabas.",
        ],
        ["Si querés seguir sin esos topes, podés suscribirte por tu cuenta."],
      ],
      "VER EL PLAN",
      ctaUrl,
    );

  // ── Aviso de baja por inactividad ───────────────────────────────────────
  //
  // ESTE MAIL NO ENUMERA LO QUE SE BORRA, y es la decision del copy.
  //
  // La tentacion es la lista completa —"rutinas, sesiones, mediciones,
  // chats"— y la lista es FALSA en su ultimo item: los hilos de chat se
  // RETIENEN a proposito para el otro participante (`cascade/athlete-data.ts`,
  // y §2.2.1 de `docs/security.md`), igual que los pagos y las resenas.
  // Prometer que se borra algo que no se borra, en el mail que existe
  // justamente para no prometer de mas, seria el mismo error del otro lado
  // (AGENTS.md §11.1). Los tres que se nombran —perfil, rutinas, historial—
  // los borra la cascada entera y sin asteriscos.
  //
  // La FECHA es un parametro y no la frase "dentro de doce meses". Para una
  // cuenta que cruza los 24 meses con el barrido encendido las dos coinciden;
  // para el backlog de la primera corrida, no. `proyeccionDeBaja` en
  // `sweep-inactive-accounts.ts` calcula la que de verdad se va a cumplir.
  //
  // "A partir del" y no "el": el barrido es diario y puede correr un dia
  // tarde. Un plazo que se corre no miente a nadie; una fecha exacta, si.
  case "inactive-account-notice":
    return build(
      "Vamos a dar de baja tu cuenta de TREINO", // i18n: email transaccional
      "Cuenta inactiva",
      [
        ["Hace más de dos años que no usás TREINO."],
        [
          "Si seguís sin entrar, a partir del ",
          strong(params.deleteOnLabel),
          " damos de baja tu cuenta y borramos tu perfil, tus rutinas y tu " +
          "historial de entrenamiento.",
        ],
        ["Para cancelarlo alcanza con abrir la app una vez: el plazo vuelve a empezar."],
      ],
      "ABRIR TREINO",
      ctaUrl,
    );

  // ── Botón de Baja de Servicio: el link de confirmación ──────────────────
  //
  // `actionLink` es el link de un solo uso a la página de confirmación de la
  // landing, con el token en el FRAGMENTO. `sendQueuedMail` lo borra del
  // documento al enviar; sin él no se dibuja botón (ver `layout`).
  //
  // EL COPY NO NOMBRA A LA PERSONA NI AL PLAN. Llega sólo al dueño del buzón,
  // pero lo pudo haber pedido cualquiera tipeando el correo en la landing: el
  // mail tiene que servirle al dueño sin contarle nada a nadie más.
  //
  // «Si no lo pediste, ignorá este mail» es la línea que hace segura la
  // verificación: sin tocar el botón no pasa nada, y eso tiene que estar
  // escrito, porque quien no pidió nada y recibe «confirmá tu baja» se asusta.
  //
  // El botón lleva a una PÁGINA con otro botón, no da la baja directo: los
  // escáneres de correo pre-abren los links. Por eso el copy dice «tocá el
  // botón» y no «abrí el link».
  case "service-cancel-confirm": {
    const code = params.code ? String(params.code) : "";
    return build(
      code
        ? `Confirmá la baja de tu suscripción — código ${code}` // i18n: email transaccional
        : "Confirmá la baja de tu suscripción",
      "Confirmá tu baja",
      [
        ["Recibimos un pedido para dar de baja tu suscripción a TREINO."],
        ...(code ? [["Código de tu trámite: ", strong(code), "."] as Line] : []),
        ["Para hacerla efectiva, tocá el botón y confirmá en la página que se abre."],
        ["El link vence en 72 horas y se puede usar una sola vez."],
        [
          "Si no lo pediste vos, ignorá este mail: no se cancela nada " +
            "hasta que alguien confirme.",
        ],
      ],
      "CONFIRMAR BAJA",
      String(params.actionLink ?? ""),
    );
  }

  // ── Botón de Baja de Servicio: la baja quedó hecha ──────────────────────
  //
  // Espejo de `docs/legal/terminos-suscripcion.md` §7, en el mismo orden de
  // importancia para quien lo lee: que no le cobran más, hasta cuándo sigue
  // usando, que no hay reembolso, y que no se borra nada. Si §7 cambia, cambia
  // esto.
  //
  // La fecha se formatea ACÁ, en hora de Argentina, a partir del ISO que guarda
  // el productor: la cola guarda QUÉ pasó, no prosa. Si no se pudo determinar
  // —un plan recién creado cuyo `auto_recurring` MP no completó— la frase de la
  // fecha no se dibuja y el resto sigue siendo cierto. Una fecha inventada no.
  //
  // Sin botón: no hay nada que hacer después de una baja, y un «ABRIR TREINO»
  // acá le habla a un alumno y a un PF con el mismo destino, que no existe.
  case "service-cancel-done": {
    const code = params.code ? String(params.code) : "";
    const iso = params.accesoHastaIso ? String(params.accesoHastaIso) : "";
    const ms = iso ? Date.parse(iso) : Number.NaN;
    const hasta = Number.isFinite(ms) ? formatShortDateAR(ms) : "";

    return build(
      code
        ? `Tu baja quedó hecha — código ${code}` // i18n: email transaccional
        : "Tu baja quedó hecha",
      "Tu baja quedó hecha",
      [
        ["Dimos de baja tu suscripción a TREINO: no se te vuelve a cobrar."],
        ...(code ? [["Código de tu trámite: ", strong(code), "."] as Line] : []),
        ...(hasta
          ? [["Conservás el acceso hasta el ", strong(hasta),
            ", el final del período que ya pagaste."] as Line]
          : []),
        ["No se reembolsa el período en curso."],
        [
          "No se borra nada: tus rutinas, tu historial y tus datos siguen " +
            "donde están. Si volvés, está todo.",
        ],
        [
          "La baja es definitiva para esta suscripción: si querés volver, " +
            "se contrata de nuevo.",
        ],
      ],
    );
  }

  // ── Cambio de plan del alumno cancelado para evitar cobro doble ─────────
  //
  // Sin boton: el plan actual sigue funcionando y la persona puede volver a
  // cambiarlo cuando quiera. Si ambos planes ya cobraron, no se promete un
  // reintegro automatico: el caso queda para revision manual del equipo.
  case "plan-change-cancelled": {
    const cobroDuplicado = String(params.cobroDuplicado ?? "") === "1";
    return build(
      "Tu cambio de plan no se aplicó",
      "Tu cambio de plan no se aplicó",
      [
        [
          "Tu cambio de plan no se aplicó porque tu plan actual ya se había renovado.",
        ],
        ["Seguís con tu plan actual; podés volver a cambiarlo cuando quieras."],
        ...(cobroDuplicado
          ? [[
            "Mercado Pago ya te había cobrado el plan nuevo: el equipo de " +
              "TREINO lo revisa y te escribe para devolvértelo.",
          ] as Line]
          : []),
      ],
    );
  }

  // ── Botón de Arrepentimiento ────────────────────────────────────────────
  //
  // NO ES LA BAJA, y los textos lo tienen que dejar clarísimo: la baja conserva
  // el acceso hasta el fin del período y NO devuelve plata; el arrepentimiento
  // devuelve todo lo pagado, y sólo dentro de los 10 días corridos
  // (`docs/legal/terminos-suscripcion.md` §6). Ningún texto de acá promete un
  // plazo de devolución: los términos dicen «a continuación te devolvemos el
  // dinero por el mismo medio de pago», y eso es lo único que se puede decir.

  // El link de verificación. Mismo criterio que `service-cancel-confirm`: el copy
  // dice «tocá el botón» y no «abrí el link», porque los escáneres de correo
  // pre-abren los links y la confirmación es un click en la página.
  case "withdrawal-confirm": {
    const code = params.code ? String(params.code) : "";
    return build(
      code
        ? `Confirmá tu arrepentimiento — código ${code}` // i18n: email transaccional
        : "Confirmá tu arrepentimiento",
      "Confirmá tu arrepentimiento",
      [
        ["Recibimos un pedido de arrepentimiento de tu suscripción a TREINO."],
        ...(code ? [["Código de tu trámite: ", strong(code), "."] as Line] : []),
        [
          "Para seguir, tocá el botón y confirmá en la página que se abre. " +
            "Ahí verificamos que estés dentro del plazo de 10 días.",
        ],
        ["El link vence en 72 horas y se puede usar una sola vez."],
        [
          "Si no lo pediste vos, ignorá este mail: no pasa nada hasta que " +
            "alguien confirme.",
        ],
      ],
      "CONFIRMAR ARREPENTIMIENTO",
      String(params.actionLink ?? ""),
    );
  }

  // Al usuario, con el pedido verificado. Dos caras del mismo mail:
  //
  //   - dentro de plazo: se cortó la suscripción y se le va a devolver la plata.
  //   - `revision: "1"`: el pedido cayó en la franja del último día donde un
  //     feriado pudo haber corrido el plazo. NO se canceló nada, y el texto no
  //     puede decir lo contrario. Ver `plazo-arrepentimiento.ts`.
  //
  // Sin botón: no hay nada que la persona tenga que hacer.
  case "withdrawal-received": {
    const code = params.code ? String(params.code) : "";
    const enRevision = String(params.revision ?? "") === "1";

    if (enRevision) {
      return build(
        code
          ? `Estamos revisando tu arrepentimiento — código ${code}` // i18n: email transaccional
          : "Estamos revisando tu arrepentimiento",
        "Estamos revisando tu pedido",
        [
          ["Recibimos tu pedido de arrepentimiento."],
          ...(code ? [["Código de tu trámite: ", strong(code), "."] as Line] : []),
          [
            "Tu contratación está en el límite del plazo de 10 días, que se " +
              "corre cuando el último día es inhábil. Por eso lo revisamos " +
              "a mano antes de darte una respuesta.",
          ],
          ["Todavía no cancelamos nada: tu suscripción sigue como estaba."],
          ["Te respondemos por este medio."],
        ],
      );
    }

    return build(
      code
        ? `Recibimos tu arrepentimiento — código ${code}` // i18n: email transaccional
        : "Recibimos tu arrepentimiento",
      "Recibimos tu arrepentimiento",
      [
        ["Recibimos tu arrepentimiento: estás dentro del plazo de 10 días."],
        ...(code ? [["Código de tu trámite: ", strong(code), "."] as Line] : []),
        ["Tu suscripción queda dada de baja: no se te vuelve a cobrar."],
        [
          "Los beneficios del plan pago terminan ahora, porque te devolvemos " +
            "todo lo pagado.",
        ],
        ["Te devolvemos lo pagado por el mismo medio de pago."],
        [
          "No se borra nada: tus rutinas, tu historial y tus datos siguen " +
            "donde están.",
        ],
      ],
    );
  }

  // Al usuario, cuando el plazo venció. Es la respuesta a «no lo debería dejar
  // y debería avisar que se venció»: dice que no se devuelve, cuándo venció, y
  // le muestra lo que SÍ puede hacer, que es la baja — espejo de §7.
  //
  // La fecha llega como ISO y se formatea ACÁ, en hora de Argentina: la cola
  // guarda QUÉ pasó, no prosa. Sin fecha, la frase no se dibuja.
  case "withdrawal-expired": {
    const code = params.code ? String(params.code) : "";
    const iso = params.ultimoDiaIso ? String(params.ultimoDiaIso) : "";
    const ms = iso ? Date.parse(iso) : Number.NaN;
    const venciO = Number.isFinite(ms) ? formatShortDateAR(ms) : "";

    return build(
      code
        ? `Venció el plazo de arrepentimiento — código ${code}` // i18n: email transaccional
        : "Venció el plazo de arrepentimiento",
      "Venció el plazo de arrepentimiento",
      [
        venciO
          ? [
            "Recibimos tu pedido, pero el plazo de 10 días corridos desde la " +
              "contratación venció el ", strong(venciO), ".",
          ]
          : [
            "Recibimos tu pedido, pero el plazo de 10 días corridos desde la " +
              "contratación ya venció.",
          ],
        ...(code ? [["Código de tu trámite: ", strong(code), "."] as Line] : []),
        ["Por eso no podemos devolver lo pagado."],
        [
          "Lo que sí podés hacer es dar de baja tu suscripción: conservás el " +
            "acceso hasta el final del período que ya pagaste y no se te " +
            "vuelve a cobrar.",
        ],
      ],
      "PEDIR LA BAJA",
      `${LANDING_URL}/es/baja-de-servicio`,
    );
  }

  // Al BUZÓN DEL EQUIPO (`toAddress`), no a un usuario. Es lo que convierte un
  // pedido verificado en una devolución que alguien tiene que hacer a mano, así
  // que trae todo lo necesario para hacerla sin abrir nada más: quién, cuándo
  // contrató según Mercado Pago, cuánto y qué suscripción buscar.
  //
  // Sin botón, a propósito: no hay ninguna pantalla nuestra a la que mandar a
  // quien lo lee, y `build` no dibuja botón si no le pasan uno.
  case "withdrawal-team-notice": {
    const enRevision = String(params.estado ?? "") === "a-revisar";
    const code = params.code ? String(params.code) : "";
    const fecha = (iso: unknown) => {
      const ms = typeof iso === "string" && iso ? Date.parse(iso) : Number.NaN;
      return Number.isFinite(ms) ? formatShortDateAR(ms) : "sin dato";
    };
    const dato = (etiqueta: string, valor: string | number | undefined): Line => [
      `${etiqueta}: `,
      strong(valor === undefined || valor === "" ? "sin dato" : valor),
    ];
    const monto = typeof params.monto === "number" ? formatArs(params.monto) : "";

    return build(
      enRevision
        ? `REVISAR arrepentimiento${code ? ` ${code}` : ""} — en el límite del plazo` // i18n: aviso interno
        : `Devolver pago: arrepentimiento${code ? ` ${code}` : ""} dentro de plazo`,
      enRevision ? "Arrepentimiento para revisar" : "Arrepentimiento para devolver",
      [
        enRevision
          ? [
            "Entró un pedido verificado por mail, en el límite del plazo. ",
            strong("No se canceló nada."),
            " Decidí a mano: si el último día era feriado, el plazo se corrió (términos §6).",
          ]
          : [
            "Entró un pedido verificado por mail, dentro del plazo. La " +
              "suscripción ya se canceló y el acceso al plan pago se cortó en el " +
              "acto. ",
            strong("Falta devolver el pago."),
          ],
        dato("Código", code),
        dato("Cuenta", String(params.email ?? "")),
        dato("uid", String(params.uid ?? "")),
        dato("Contratación (según Mercado Pago)", fecha(params.contratoIso)),
        dato("Días corridos desde la contratación", params.diasTranscurridos),
        dato("Último día del plazo", fecha(params.ultimoDiaIso)),
        dato("Monto de la suscripción", monto),
        dato("Cobros registrados", params.cobros),
        dato("Suscripciones en Mercado Pago", String(params.suscripciones ?? "")),
        dato("Canceladas ahora", params.canceladas),
        ...(params.pisoTier
          ? [[
            "Ojo: conserva el resto prepago de un plan anterior (",
            strong(String(params.pisoTier)),
            " hasta el ",
            strong(fecha(params.pisoHastaIso)),
            "). No se cortó: es plata ya pagada que este pedido no devuelve. " +
              "Si devolvés también ese pago, quitalo a mano.",
          ] as Line]
          : []),
        enRevision
          ? ["Acceso al plan pago: sigue igual, no se canceló nada."]
          : ["Acceso al plan pago: cortado en el acto."],
        [
          "Para devolver: en Mercado Pago, buscá la operación entre los cobros " +
            "aprobados y usá «Devolver dinero» por el monto total.",
        ],
      ],
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
