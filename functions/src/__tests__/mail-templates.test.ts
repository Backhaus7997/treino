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

/**
 * El href del BOTON del CTA.
 *
 * El documento tiene mas de un `<a>` —el boton y el link del footer— y desde
 * que el header trae el logo, tambien aparece `app.gettreino.com` como origen
 * de una imagen. Un `expect(html).not.toContain("app.gettreino.com")` mezcla
 * las tres cosas: prohibe un string en todo el documento cuando lo que importa
 * es a donde APUNTA el boton. Se identifica por `display:inline-block`, que es
 * lo que lo hace boton.
 */
function ctaHref(html: string): string {
  const m = html.match(/<a href="([^"]+)"[^>]*display:inline-block/);
  return m ? m[1] : "";
}

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
  // El default es la pagina puente, NO `gettreino.com`. Esa landing es de otro
  // producto —gimnasios, en ingles, "No custom app"— asi que un atleta que
  // tocaba el boton caia en una pagina sin login ni descarga que ademas le
  // negaba la app que tiene instalada.
  it("por defecto manda al destino del ATLETA, no a la landing", () => {
    const out = renderMail("appointment-confirmed", { trainerName: "Jose" });

    expect(ctaHref(out.html)).toBe("https://app.gettreino.com/abrir/alumno");
  });

  it("ningun CTA cae en la landing de gimnasios", () => {
    for (const kind of ALL_KINDS) {
      const href = ctaHref(renderMail(kind, {}).html);

      expect(href).not.toBe("https://gettreino.com");
    }
  });

  // Los de auth reciben su destino en `actionLink`, y `sendQueuedMail` lo BORRA
  // del documento al enviar. Si ese doc se volviera a renderizar, el boton
  // quedaria sin destino: antes salia `href=""`, que no lleva a ningun lado.
  it("sin destino no se dibuja boton, en vez de uno muerto", () => {
    const html = renderMail("password-reset", {}).html;

    expect(html).not.toContain("href=\"\"");
    expect(html).not.toContain("CAMBIAR MI CONTRASEÑA");
  });

  it("con destino, el boton sí aparece", () => {
    const html = renderMail("password-reset", {
      actionLink: "https://auth.gettreino.com/__/auth/action?oobCode=X",
    }).html;

    expect(html).toContain("CAMBIAR MI CONTRASEÑA");
  });

  // El footer SI sigue apuntando a la landing: es el link de marca del pie, no
  // una accion. Distinguirlos es el punto de todo esto.
  it("el link de marca del footer sigue siendo la landing", () => {
    const out = renderMail("appointment-confirmed", { trainerName: "Jose" });

    expect(out.html).toContain(">gettreino.com</a>");
  });

  it("respeta el ctaUrl que pasa el productor", () => {
    const out = renderMail("link-requested", {
      athleteName: "Marta",
      ctaUrl: "https://app.gettreino.com/abrir/profe",
    });

    expect(ctaHref(out.html)).toBe("https://app.gettreino.com/abrir/profe");
  });

  // Los destinos son App Links bajo /abrir: si alguno se escribiera distinto,
  // el sistema operativo no lo reconoceria y abriria el navegador — sin error,
  // sin log, igual que si no existiera nada de esto.
  //
  // `password-reset` y `email-verification` quedan afuera A PROPOSITO: su CTA
  // no es un destino nuestro, es el `actionLink` de un solo uso que minta el
  // Admin SDK y que apunta al action handler de Firebase.
  it("todo CTA que no sea un action link vive bajo /abrir", () => {
    const conActionLink = ["password-reset", "email-verification"];
    const resto = ALL_KINDS.filter((k) => !conActionLink.includes(k));

    expect(resto).toHaveLength(8);
    for (const kind of resto) {
      const href = ctaHref(renderMail(kind, {}).html);

      expect(href).toMatch(/^https:\/\/app\.gettreino\.com\/abrir\/(alumno|profe)$/);
    }
  });

  // Un CTA que solo vive dentro de un <a> no existe para quien lee en texto.
  it("la URL del CTA también entra en la parte de texto plano", () => {
    const out = renderMail("payment-overdue", { trainerName: "Jose" });

    expect(out.text).toContain("https://app.gettreino.com/abrir/alumno");
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
// Marca: el header y su degradacion
// ---------------------------------------------------------------------------
describe("header de marca", () => {
  const out = () => renderMail("appointment-confirmed", { trainerName: "Jose" });

  it("trae la marca TR como imagen", () => {
    expect(out().html).toContain("https://app.gettreino.com/email/logo.png");
  });

  // Outlook y Gmail-sin-imagenes no cargan el <img>. Si el header fuera solo
  // logo, para esa gente el mail empieza en blanco. Estas dos aserciones son la
  // red: el alt dice la marca, y la palabra TREINO esta escrita aparte.
  // Outlook y Gmail-sin-imagenes no cargan el <img>. El wordmark de al lado no
  // es decorativo: ES el fallback, y por eso el logo va con `alt=""`.
  //
  // Medido sobre el render real con la imagen rota: con `alt="TREINO"` el
  // texto se dibuja dentro de la caja de 28px del <img> y sale "TRE TREINO".
  it("degrada al wordmark cuando el cliente bloquea imagenes", () => {
    const html = out().html;

    expect(html).toContain(">TREINO</div>");
    expect(html).toContain("alt=\"\"");
  });

  it("el logo no repite la marca en el alt: la diria dos veces", () => {
    // Un lector de pantalla que encuentre alt="TREINO" y el wordmark leeria
    // "TREINO TREINO". La imagen es decorativa PORQUE la palabra esta al lado.
    expect(out().html).not.toContain("alt=\"TREINO\"");
  });

  it("no usa SVG, que ningun cliente de mail renderiza", () => {
    expect(out().html).not.toContain(".svg");
  });
});

// ---------------------------------------------------------------------------
// Preheader — la linea gris de la bandeja de entrada
// ---------------------------------------------------------------------------
describe("preheader", () => {
  it("cada kind produce uno, sin excepcion", () => {
    for (const kind of ALL_KINDS) {
      const html = renderMail(kind, { trainerName: "Jose" }).html;
      const m = html.match(/opacity:0;">([^&<]*)/);

      expect(m).not.toBeNull();
      expect((m?.[1] ?? "").trim().length).toBeGreaterThan(0);
    }
  });

  // Se deriva de la primera linea del cuerpo (ver `build`), asi que decir algo
  // util en la bandeja y decirlo en el mail son el MISMO trabajo.
  it("dice lo mismo que la primera linea del cuerpo", () => {
    const out = renderMail("appointment-confirmed", { trainerName: "Jose" });

    expect(out.html).toMatch(/opacity:0;">Jose confirmó tu sesión\./);
  });

  it("va oculto: no se ve dentro del mail abierto", () => {
    const out = renderMail("password-reset", { actionLink: "https://x.test" });

    expect(out.html).toContain("display:none;max-height:0;overflow:hidden;opacity:0;");
  });

  // Sin relleno el cliente sigue leyendo el cuerpo y lo pega atras del
  // preheader en la vista previa.
  it("lleva relleno invisible para que no se cuele el cuerpo", () => {
    expect(renderMail("link-accepted", {}).html).toContain("&#8199;&#65279;&zwnj;");
  });

  // El preheader es HTML oculto, no texto plano: si un nombre hostil entrara
  // crudo ahi, seria una inyeccion con la misma superficie que el cuerpo.
  it("escapa lo que viene del usuario", () => {
    const out = renderMail("link-requested", {
      athleteName: "<script>alert(1)</script>",
    });

    expect(out.html).not.toContain("<script>");
  });

  it("no ensucia la parte de texto plano", () => {
    const out = renderMail("appointment-confirmed", { trainerName: "Jose" });

    expect(out.text).not.toContain("&#8199;");
    expect(out.text).not.toContain("zwnj");
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
