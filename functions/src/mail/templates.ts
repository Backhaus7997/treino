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

/** Fallback CTA target for mails that just send the reader back into the app. */
const APP_URL = "https://treino.app/coach";

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
  ctaLabel?: string,
  ctaHref: string = APP_URL,
): string {
  const cta = ctaLabel
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
    "<title>TREINO</title></head>",
    `<body style="margin:0;padding:0;background:${INK};">`,
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"",
    ` style="background:${INK};padding:32px 16px;"><tr><td align="center">`,
    "<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"",
    ` style="max-width:520px;background:${INK_CARD};border-radius:16px;">`,
    "<tr><td style=\"padding:32px 32px 0 32px;\">",
    `<div style="font-size:13px;letter-spacing:2px;color:${MINT};`,
    `font-weight:700;font-family:${FONT};">TREINO</div></td></tr>`,
    "<tr><td style=\"padding:20px 32px 0 32px;\">",
    `<h1 style="margin:0;font-size:24px;line-height:1.25;color:${BONE};`,
    `font-family:${FONT};">${heading}</h1></td></tr>`,
    "<tr><td style=\"padding:16px 32px 24px 32px;font-size:15px;",
    `line-height:1.6;color:${MUTED};font-family:${FONT};">${bodyHtml}</td></tr>`,
    cta,
    "</table>",
    "<div style=\"max-width:520px;padding:20px 8px;font-size:12px;",
    `color:${MUTED};font-family:${FONT};">`,
    "Recibís este mail porque tenés una cuenta en TREINO.</div>",
    "</td></tr></table></body></html>",
  ].join("");
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
  lines: string[],
  ctaLabel?: string,
  ctaHref?: string,
): RenderedMail {
  const bodyHtml = lines
    .map((l) => `<p style="margin:0 0 12px 0;">${l}</p>`)
    .join("");

  // Strip the inline markup the HTML lines carry to get the text/plain part.
  const textLines = [heading, "", ...lines.map((l) => l.replace(/<[^>]+>/g, ""))];
  if (ctaHref) textLines.push("", ctaHref);

  return {
    subject,
    html: layout(heading, bodyHtml, ctaLabel, ctaHref),
    text: textLines.join("\n"),
  };
}

/** Wraps a value in the light highlight used for names, dates and amounts. */
function strong(value: string | number | undefined): string {
  return `<strong style="color:${BONE};">${esc(value)}</strong>`;
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
        "Recibimos un pedido para cambiar la contraseña de tu cuenta.",
        "El link vence en una hora y se puede usar una sola vez.",
        "Si no lo pediste vos, ignorá este mail: tu contraseña no cambia " +
            "hasta que alguien complete el formulario.",
      ],
      "CAMBIAR MI CONTRASEÑA",
      String(params.actionLink ?? ""),
    );

  case "email-verification":
    return build(
      "Confirmá tu email en TREINO",
      "Confirmá tu email",
      [
        "Tocá el botón para confirmar que esta dirección es tuya.",
        "Es el último paso para tener la cuenta activa.",
      ],
      "CONFIRMAR MI EMAIL",
      String(params.actionLink ?? ""),
    );

  case "appointment-confirmed":
    return build(
      "Tu sesión quedó confirmada", // i18n: email transaccional
      "Sesión confirmada",
      [
        `${strong(params.trainerName)} confirmó tu sesión.`,
        `${strong(params.dateLabel)} a las ${strong(params.timeLabel)}.`,
        "Si no podés ir, cancelá con más de 24 horas de anticipación.",
      ],
      "VER MI AGENDA",
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
        `${strong(params.trainerName)} te agendó una serie de sesiones ` +
            "recurrentes.",
        "Las tenés todas cargadas en tu agenda, con día y horario.",
      ],
      "VER MI AGENDA",
    );

  case "appointment-cancelled":
    return build(
      "Se canceló una sesión",
      "Sesión cancelada",
      [
        `${strong(params.otherName)} canceló la sesión del ` +
            `${strong(params.dateLabel)} a las ${strong(params.timeLabel)}.`,
        "El horario vuelve a estar disponible en la agenda.",
      ],
      "VER MI AGENDA",
    );

    // Same partial-batch reasoning as `appointment-series-created`.
  case "appointment-series-cancelled":
    return build(
      "Se cancelaron sesiones de tu serie",
      "Sesiones canceladas",
      [
        `${strong(params.otherName)} canceló sesiones de una serie ` +
            "recurrente.",
        "Revisá tu agenda para ver cómo quedó.",
      ],
      "VER MI AGENDA",
    );

  case "link-requested":
    return build(
      "Tenés una solicitud de vinculación",
      "Nueva solicitud",
      [
        `${strong(params.athleteName)} quiere entrenar con vos.`,
        "Aceptá la solicitud para empezar a armarle la rutina.",
      ],
      "VER SOLICITUD",
    );

  case "link-accepted":
    return build(
      "¡Ya estás vinculado!",
      "Vinculación aceptada",
      [
        `${strong(params.trainerName)} aceptó tu solicitud.`,
        "Ya podés ver las rutinas que te asigne y hablar por el chat.",
      ],
      "IR A MI ENTRENADOR",
    );

  case "payment-overdue":
    return build(
      "Tenés un pago pendiente",
      "Pago vencido",
      [
        `Tenés un pago pendiente con ${strong(params.trainerName)}.`,
        `${strong(params.amountLabel)} — vencía el ` +
            `${strong(params.dueLabel)}.`,
        "Coordiná el pago con tu entrenador para seguir entrenando.",
      ],
      "VER MIS PAGOS",
    );

  default: {
    // Exhaustiveness guard: adding a MailKind without a template fails to
    // compile here rather than shipping a blank email.
    const never: never = kind;
    throw new Error(`renderMail: unhandled kind ${String(never)}`);
  }
  }
}
