/**
 * Unit tests for the transactional email templates and formatters.
 *
 * Pure — no emulator, no network. Run with plain `npx jest mail-templates`.
 *
 * Covers:
 *   - HTML escaping of user-controlled display names (the injection surface)
 *   - both MIME parts present and non-empty for every MailKind
 *   - ART rendering of dates, times and amounts
 */

import { renderMail } from "../mail/templates";
import { MailKind } from "../mail/types";
import {
  artDateKey,
  formatArs,
  formatDateAR,
  formatShortDateAR,
  formatTimeAR,
  toDate,
} from "../mail/format";

const ALL_KINDS: MailKind[] = [
  "password-reset",
  "federated-signin-hint",
  "email-verification",
  "appointment-confirmed",
  "appointment-series-created",
  "appointment-cancelled",
  "appointment-series-cancelled",
  "link-requested",
  "link-accepted",
  "payment-overdue",
];

// ---------------------------------------------------------------------------
// Escaping — display names are user-controlled free text
// ---------------------------------------------------------------------------
describe("renderMail: escapes user-controlled values", () => {
  const NASTY = "<script>alert('x')</script>";

  it("never emits a raw script tag from a display name", () => {
    const out = renderMail("link-requested", { athleteName: NASTY });

    expect(out.html).not.toContain("<script>");
    expect(out.html).toContain("&lt;script&gt;");
  });

  it("escapes quotes so a name cannot break out of an attribute", () => {
    const out = renderMail("link-accepted", {
      trainerName: "\" onmouseover=\"evil()",
    });

    expect(out.html).not.toContain("onmouseover=\"evil()\"");
    expect(out.html).toContain("&quot;");
  });

  it("escapes ampersands without double-escaping the entities it creates", () => {
    const out = renderMail("link-accepted", { trainerName: "Ruiz & Co" });

    expect(out.html).toContain("Ruiz &amp; Co");
    expect(out.html).not.toContain("&amp;amp;");
  });

  // La parte de texto se construye desde los MISMOS segmentos que el HTML, no
  // quitándole los tags al HTML ya escapado (CodeQL:
  // js/incomplete-multi-character-sanitization). Efecto lateral bueno: en
  // text/plain las entidades no tienen sentido, y ahora no aparecen.
  it("la parte de texto plano no lleva entidades HTML", () => {
    const out = renderMail("link-accepted", { trainerName: "Ruiz & Co" });

    expect(out.text).toContain("Ruiz & Co");
    expect(out.text).not.toContain("&amp;");
  });

  // El regex de stripping podía CREAR un tag: `<<a>script>` -> `<script>`.
  // Con segmentos no hay stripping, así que un nombre hostil sale escapado en
  // el HTML y literal en el texto, sin pasar por ninguna pasada destructiva.
  it("un nombre que construye un tag al quitar tags ya no puede hacerlo", () => {
    const out = renderMail("link-accepted", { trainerName: "<<a>script>" });

    expect(out.html).not.toContain("<script>");
    expect(out.html).toContain("&lt;&lt;a&gt;script&gt;");
    expect(out.text).toContain("<<a>script>");
  });
});

// ---------------------------------------------------------------------------
// Every kind renders both MIME parts
// ---------------------------------------------------------------------------
describe("renderMail: every MailKind produces a complete message", () => {
  it.each(ALL_KINDS)("%s has subject, html and text", (kind) => {
    const out = renderMail(kind, {
      trainerName: "Jose",
      athleteName: "Marta",
      otherName: "Jose",
      dateLabel: "martes 26 de agosto",
      timeLabel: "19:00",
      amountLabel: "$ 25.000",
      dueLabel: "26/08/2026",
    });

    expect(out.subject.length).toBeGreaterThan(0);
    expect(out.text.length).toBeGreaterThan(0);
    expect(out.html).toContain("<!doctype html>");
    // A missing text/plain alternative is itself a spam signal.
    expect(out.text).not.toContain("<");
  });

  it("degrades to empty strings instead of throwing on missing params", () => {
    expect(() => renderMail("appointment-confirmed", {})).not.toThrow();
  });

  it("carries the brand accent so the mail is recognisably TREINO", () => {
    const out = renderMail("appointment-confirmed", { trainerName: "Jose" });
    expect(out.html).toContain("#2CE5A2");
  });
});

// ---------------------------------------------------------------------------
// A dónde apunta el CTA
//
// Tres de los cuatro mails no-auth van a ATLETAS, que usan la app móvil. El
// Coach Hub es el dashboard del ENTRENADOR: mandar ahí a un atleta lo deja
// mirando una herramienta que no es suya. Por eso el default es la landing y el
// Coach Hub se pide explícitamente.
// ---------------------------------------------------------------------------
describe("destino del CTA", () => {
  it("por defecto va a la landing, no al Coach Hub", () => {
    const out = renderMail("appointment-confirmed", { trainerName: "Jose" });

    expect(out.html).toContain("https://gettreino.com");
    expect(out.html).not.toContain("app.gettreino.com");
  });

  it("respeta el ctaUrl que pasa el productor", () => {
    const out = renderMail("link-requested", {
      athleteName: "Marta",
      ctaUrl: "https://app.gettreino.com",
    });

    expect(out.html).toContain("https://app.gettreino.com");
  });

  // Un CTA que solo vive dentro de un <a> no existe para quien lee en texto.
  it("la URL del CTA también entra en la parte de texto plano", () => {
    const out = renderMail("payment-overdue", { trainerName: "Jose" });

    expect(out.text).toContain("https://gettreino.com");
  });

  it("ningún template apunta a un dominio que no es nuestro", () => {
    for (const kind of ALL_KINDS) {
      const out = renderMail(kind, { actionLink: "https://x.test/?oobCode=1" });
      expect(out.html).not.toContain("treino.app");
    }
  });
});

// ---------------------------------------------------------------------------
// Mails de auth — el link es la razón de ser del mail
// ---------------------------------------------------------------------------
describe("plantillas de auth: el action link llega entero", () => {
  const LINK =
    "https://treino-dev.firebaseapp.com/__/auth/action" +
    "?mode=resetPassword&oobCode=ABC123&apiKey=XYZ";

  it.each(["password-reset", "email-verification"] as MailKind[])(
    "%s pone el link en el href del CTA",
    (kind) => {
      const out = renderMail(kind, { actionLink: LINK });
      expect(out.html).toContain("oobCode=ABC123");
      expect(out.html).not.toContain("treino.app/coach");
    },
  );

  // Un mail de recuperación cuyo único link vive dentro de un <a> es inútil
  // para quien lee en texto plano — y en el camino de vuelta a una cuenta
  // bloqueada, inútil es lo mismo que roto.
  it.each(["password-reset", "email-verification"] as MailKind[])(
    "%s repite la URL cruda en la parte de texto plano",
    (kind) => {
      const out = renderMail(kind, { actionLink: LINK });
      expect(out.text).toContain(LINK);
    },
  );

  // REQ-AUTH-011 alcanza también al copy: si el mail de una cuenta existente
  // dijera algo distinto, el texto sería el oráculo que el endpoint evita ser.
  it("el copy de reseteo no nombra al usuario ni afirma que la cuenta existe", () => {
    const out = renderMail("password-reset", { actionLink: LINK });
    const plano = out.text.toLowerCase();

    expect(plano).not.toContain("@");
    expect(plano).toContain("si no lo pediste");
  });

  it("no explota cuando falta el actionLink", () => {
    expect(() => renderMail("password-reset", {})).not.toThrow();
  });

  it("escapa el link en vez de inyectarlo crudo en el atributo", () => {
    const out = renderMail("password-reset", {
      actionLink: "https://x.test/?a=\"><script>alert(1)</script>",
    });
    expect(out.html).not.toContain("<script>");
  });
});

// ---------------------------------------------------------------------------
// El hint para cuentas sin contraseña
// ---------------------------------------------------------------------------
describe("plantilla federated-signin-hint", () => {
  const out = () => renderMail("federated-signin-hint", {});

  // No hay contraseña que restablecer: un link acá sería mentira.
  it("no lleva ningún link de action", () => {
    expect(out().html).not.toContain("oobCode");
    expect(out().html).not.toContain("__/auth/action");
  });

  it("dice cómo entrar, sin nombrar al usuario", () => {
    const plano = out().text.toLowerCase();

    expect(plano).toContain("google");
    // Nunca una dirección: el mail llega al buzón, no hace falta repetirla.
    expect(plano).not.toContain("@");
  });

  // Aunque el usuario no pidió esto, reconoce el pedido que sí hizo. Un mail
  // que ignora lo que la persona acaba de hacer se lee como no relacionado.
  it("reconoce el pedido de reseteo que lo originó", () => {
    expect(out().text.toLowerCase()).toContain("contraseña");
  });

  it("manda a la landing, que sirve para cualquier rol", () => {
    expect(out().html).toContain("https://gettreino.com");
  });
});

// ---------------------------------------------------------------------------
// Formatters — ART, not UTC
// ---------------------------------------------------------------------------
describe("format: renders in America/Argentina/Buenos_Aires", () => {
  // 2026-08-26T22:00:00Z is 19:00 on the 26th in ART (UTC-3).
  const EVENING = new Date("2026-08-26T22:00:00Z");

  it("formats the time in ART, not UTC", () => {
    expect(formatTimeAR(EVENING)).toBe("19:00");
  });

  it("formats the date in es-AR", () => {
    const out = formatDateAR(EVENING);
    expect(out).toContain("26");
    expect(out.toLowerCase()).toContain("agosto");
  });

  it("keeps the ART calendar day when UTC has already rolled over", () => {
    // 02:00Z on the 27th is still 23:00 on the 26th in Buenos Aires.
    const afterMidnightUtc = new Date("2026-08-27T02:00:00Z");
    expect(artDateKey(afterMidnightUtc)).toBe("2026-08-26");
    expect(formatShortDateAR(afterMidnightUtc)).toBe("26/08/2026");
  });

  it("returns an empty string for an unusable date rather than throwing", () => {
    expect(formatTimeAR(undefined)).toBe("");
    expect(formatDateAR(undefined)).toBe("");
    expect(toDate(undefined)).toBeNull();
  });

  it("accepts the plain _seconds shape a Timestamp takes after JSON", () => {
    const seconds = Math.floor(EVENING.getTime() / 1000);
    expect(formatTimeAR({ _seconds: seconds })).toBe("19:00");
  });
});

describe("formatArs", () => {
  it("renders whole pesos without centavos", () => {
    const out = formatArs(25000);
    expect(out).toContain("25.000");
    expect(out).not.toContain(",00");
  });

  it("returns an empty string for a missing amount", () => {
    expect(formatArs(undefined)).toBe("");
    expect(formatArs(Number.NaN)).toBe("");
  });
});
