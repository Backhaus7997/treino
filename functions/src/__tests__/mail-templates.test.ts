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

import { renderMail, trainerEntry, trainerWebCheckout } from "../mail/templates";
import { MailKind, MailParams } from "../mail/types";
import {
  artDateKey,
  formatArs,
  formatDateAR,
  formatShortDateAR,
  formatTimeAR,
  toDate,
} from "../mail/format";

/**
 * Todos los `MailKind`, y el COMPILADOR se asegura de que sean todos.
 *
 * Antes era un `MailKind[]` escrito a mano, y se quedó en 13 mientras la unión
 * crecía a 19. Los seis nuevos —los dos comerciales entre ellos— tienen tests
 * en su propio módulo, pero nunca pasaron por los chequeos que este archivo le
 * aplica a todos los kinds. Así salió a una casilla real el de
 * `free-limit-reached` sin una sola tilde.
 *
 * Un `Record<MailKind, true>` no compila si falta una clave, así que el kind
 * número 20 entra acá el mismo día que entra a la unión.
 */
const KINDS: Record<MailKind, true> = {
  "password-reset": true,
  "federated-signin-hint": true,
  "email-verification": true,
  "email-code-athlete": true,
  "email-code-trainer": true,
  "appointment-confirmed": true,
  "appointment-series-created": true,
  "appointment-cancelled": true,
  "appointment-series-cancelled": true,
  "link-requested": true,
  "link-accepted": true,
  "payment-overdue": true,
  "discomfort-reported": true,
  "moderation-report-created": true,
  "moderation-user-warned": true,
  "subscription-grace": true,
  "subscription-downgraded": true,
  "limit-reached": true,
  "athlete-coverage-lost": true,
  "free-limit-reached": true,
  "exercise-limit-reached": true,
  "template-limit-reached": true,
  "student-limit-reached": true,
  "inactive-account-notice": true,
  "service-cancel-confirm": true,
  "service-cancel-done": true,
  "withdrawal-confirm": true,
  "withdrawal-received": true,
  "withdrawal-expired": true,
  "withdrawal-team-notice": true,
};
const ALL_KINDS = Object.keys(KINDS) as MailKind[];

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
  //
  // `moderation-report-created` tambien queda afuera, y tambien a proposito: no
  // dibuja boton hasta que exista la ruta de la cola (ver su `case`). El test
  // de abajo verifica que siga sin boton, asi la excepcion no esconde nada.
  //
  // `service-cancel-confirm` lleva su link de un solo uso en `actionLink`, igual
  // que los de auth, y `service-cancel-done` no tiene botón: después de una
  // baja no hay nada que hacer (ver sus `case`).
  //
  // Los cuatro del arrepentimiento: `withdrawal-confirm` lleva su link de un solo
  // uso en `actionLink`; `withdrawal-received` no tiene botón (no hay nada que
  // hacer) y `withdrawal-team-notice` va al equipo, sin pantalla nuestra a la
  // que mandarlo; `withdrawal-expired` manda a la BAJA, en la landing, que es
  // lo único que la persona puede hacer después de que venció el plazo.
  //
  // Los dos del código de verificación (`email-code-*`) mandan a donde se
  // paga, que no es la app: el del alumno al checkout de la landing y el del
  // entrenador al Coach Hub web (`trainerWebCheckout`). Sus destinos se
  // verifican uno por uno en «código de verificación del mail».
  it("todo CTA que no sea un action link vive bajo /abrir", () => {
    const conActionLink = [
      "password-reset", "email-verification", "service-cancel-confirm",
      "withdrawal-confirm",
    ];
    const sinBoton = [
      "moderation-report-created", "service-cancel-done",
      "withdrawal-received", "withdrawal-team-notice",
    ];
    const aLaLanding = ["withdrawal-expired"];
    const alCobroWeb = ["email-code-athlete", "email-code-trainer"];
    const resto = ALL_KINDS.filter(
      (k) =>
        !conActionLink.includes(k) && !sinBoton.includes(k) &&
        !aLaLanding.includes(k) && !alCobroWeb.includes(k),
    );

    expect(resto).toHaveLength(19);
    for (const kind of resto) {
      const href = ctaHref(renderMail(kind, {}).html);

      expect(href).toMatch(/^https:\/\/app\.gettreino\.com\/abrir\/(alumno|profe)$/);
    }
  });

  it("el aviso de moderación sigue sin botón mientras no exista la cola", () => {
    expect(ctaHref(renderMail("moderation-report-created", {}).html)).toBe("");
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
// trainerWebCheckout — los mails de plata del PF NO van por el App Link
//
// `/abrir/profe` abre la app en un teléfono, y la app no vende. Estos mails
// tienen que ir directo al Coach Hub web.
// ---------------------------------------------------------------------------
describe("plantilla student-limit-reached", () => {
  // El mismo mail sale cuando se rechaza ACEPTAR una solicitud y cuando se
  // rechaza REANUDAR un vínculo pausado: en el segundo caso el alumno no es
  // nuevo, así que el texto no puede decir que lo es (hallazgo de Codex sobre
  // #1267).
  it("habla de activar el vínculo, no de un alumno nuevo", () => {
    const out = renderMail("student-limit-reached", { limit: 2, ctaUrl: "https://app.gettreino.com/?to=facturacion" });

    expect(out.html).toContain("activar ese vínculo");
    expect(out.html).not.toMatch(/alumno nuevo/i);
    expect(out.text).not.toMatch(/alumno nuevo/i);
  });
});

describe("trainerWebCheckout", () => {
  it("es exactamente la URL del Coach Hub con el destino de facturación", () => {
    expect(trainerWebCheckout()).toBe("https://app.gettreino.com/?to=facturacion");
  });

  it("no pasa por el App Link", () => {
    expect(trainerWebCheckout()).not.toContain("/abrir/");
  });

  // Guard de compilación: si alguien saca el `Exclude` de `trainerEntry` y
  // vuelve a habilitar `{ to: "facturacion" }` ahí, ts-jest deja de compilar
  // este archivo (TS2578, directiva sin usar). Lo protege jest, no el `tsc`
  // del build: `tsconfig.json` excluye `src/__tests__`.
  it("trainerEntry ya no acepta el destino de facturación", () => {
    // @ts-expect-error — "facturacion" está excluido: ese destino va por trainerWebCheckout().
    expect(() => trainerEntry({ to: "facturacion" })).not.toThrow();
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
// Molestia reportada — el único mail del set con consecuencia física
// ---------------------------------------------------------------------------
describe("plantilla discomfort-reported", () => {
  it("nombra al alumno y manda a abrir la app", () => {
    const out = renderMail("discomfort-reported", {
      athleteName: "Ana Atleta",
      ctaUrl: "https://app.gettreino.com/abrir/profe",
    });

    expect(out.text).toContain("Ana Atleta");
    expect(out.text.toLowerCase()).toContain("molestia");
    expect(ctaHref(out.html)).toBe("https://app.gettreino.com/abrir/profe");
  });

  // EL invariante de este mail. El push ya excluye `text` y `photoUrl` porque
  // son dato de salud; por mail pesa MÁS —queda en la bandeja para siempre y
  // pasa por Resend, que es un tercero—, así que la plantilla no los renderiza
  // ni aunque un productor se los pase. Si mañana alguien "enriquece" el cuerpo
  // con el detalle del reporte, esto se pone rojo, y el rojo tiene razón:
  // primero hay que cerrar QA-CMP-008.
  it("no renderiza el texto ni la foto del reporte aunque se los pasen", () => {
    const secretText = "Me tiró la rodilla derecha en la última serie";
    const secretPhoto = "https://firebasestorage.googleapis.com/x?token=abc123";

    const out = renderMail("discomfort-reported", {
      athleteName: "Ana Atleta",
      text: secretText,
      photoUrl: secretPhoto,
    });

    for (const part of [out.html, out.text, out.subject]) {
      expect(part).not.toContain(secretText);
      expect(part).not.toContain(secretPhoto);
      expect(part).not.toContain("token=abc123");
    }
  });

  // Deliberado, y por una razón distinta a la privacidad: el mail está
  // deduplicado POR SESIÓN, así que lo produce el PRIMER reporte en dispararse.
  // Nombrar "Sentadilla" cuando el alumno reportó molestia en tres ejercicios
  // le arma al PF un modelo mental falso del alcance — el mismo problema de
  // lote parcial que `appointment-series-created` documenta.
  it("no nombra un ejercicio: el mail cubre la sesión entera", () => {
    const out = renderMail("discomfort-reported", {
      athleteName: "Ana Atleta",
      exerciseName: "Sentadilla",
    });

    expect(out.html).not.toContain("Sentadilla");
    expect(out.text).not.toContain("Sentadilla");
  });

  it("escapa el nombre del alumno, que es texto libre del usuario", () => {
    const out = renderMail("discomfort-reported", {
      athleteName: "<script>alert(1)</script>",
    });

    expect(out.html).not.toContain("<script>");
    expect(out.html).toContain("&lt;script&gt;");
  });
});

// ---------------------------------------------------------------------------
// Marca: el header y su degradacion
// ---------------------------------------------------------------------------
describe("header de marca", () => {
  const out = () => renderMail("appointment-confirmed", { trainerName: "Jose" });

  it("trae el wordmark como imagen", () => {
    expect(out().html).toContain("https://app.gettreino.com/email/wordmark.png");
  });

  // Outlook y Gmail-sin-imagenes no cargan el <img>. Si el header fuera solo
  // logo, para esa gente el mail empieza en blanco. Estas dos aserciones son la
  // red: el alt dice la marca, y la palabra TREINO esta escrita aparte.
  // Outlook y Gmail-sin-imagenes no cargan el <img>, y ahora el header es SOLO
  // la imagen: sin alt, para esa gente el mail empieza en blanco.
  //
  // El alt estuvo VACIO mientras el header era marca TR + la palabra escrita
  // al lado. Ahi era correcto: la palabra ya era el fallback, el alt la habria
  // dicho dos veces en un lector de pantalla, y ademas se recortaba a "TRE"
  // dentro de la caja de 28px del <img>. Sacada esa palabra, las dos razones
  // desaparecen — y en los 110px del wordmark el texto entra entero.
  it("lleva alt, que ahora es la unica red si se bloquean imagenes", () => {
    expect(out().html).toContain("alt=\"TREINO\"");
  });

  it("el alt hereda el color de marca, para que se lea al bloquearse", () => {
    // Sin `color` en el style del <img>, el alt de una imagen rota sale en el
    // color de texto por defecto del cliente.
    expect(out().html).toMatch(/<img[^>]+alt="TREINO"[^>]+color:#2CE5A2/);
  });

  it("la palabra ya no se escribe aparte: la imagen ES la palabra", () => {
    expect(out().html).not.toContain(">TREINO</div>");
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

// ---------------------------------------------------------------------------
// Los dos mails del paywall del PF
//
// Acá el copy ES el entregable. Son mails sobre plata y sobre un servicio que
// puede cortarse, y el PR #758 dejó pineadas dos frases que no se pueden
// romper. Estos tests existen para que no se rompan en silencio.
// ---------------------------------------------------------------------------
describe("mails del paywall del PF", () => {
  // La invariante mas importante de todo el slice, segun el propio PR #758:
  // "si alguna frase te da a entender que el alumno perdió acceso, es un bug —
  // y es el peor error posible". El alumno conserva rutinas, historial y chat;
  // lo que se frena es que el PF trabaje sobre el.
  it("nunca sugiere que el alumno perdio algo", () => {
    for (const kind of ["subscription-grace", "subscription-downgraded"] as const) {
      const out = renderMail(kind, {
        tier: "plan2", limit: 2, blockedCount: 4, reason: "paused",
      });

      expect(out.text).toContain("no pierden nada");
      expect(out.text).not.toMatch(/perd[ií](ó|eron|o)\s+(el\s+)?acceso/i);
      expect(out.text).not.toMatch(/se (le|les) (quit|sac)/i);
    }
  });

  it("el mail de grace dice que TODAVIA no cambio nada, y que pasa si no entra", () => {
    const out = renderMail("subscription-grace", { tier: "plan2", limit: 15 });

    expect(out.text).toContain("Por ahora no cambia nada");
    expect(out.text).toContain("15 alumnos");
    expect(out.text).toContain("plan Free (2 alumnos)");
    expect(out.text).toContain("Revisá tu medio de pago");
  });

  // NO LLEVA FECHA DE CORTE. El unico instante del documento es
  // `currentPeriodEnd`, que es el pagado-hasta, no el corte: el corte lo decide
  // MP. Escribir una fecha ahi seria dar por cierto algo que no controlamos, en
  // el mail donde el PF decide cuando mover la plata (regla 11.1 de AGENTS.md).
  it("el mail de grace no promete una fecha de corte", () => {
    const out = renderMail("subscription-grace", {
      tier: "plan2", limit: 15, currentPeriodEnd: "2027-02-01",
    });

    expect(out.text).not.toMatch(/\d{1,2}\/\d{1,2}\/\d{2,4}/);
    expect(out.text).not.toMatch(/antes del/i);
  });

  it("el downgrade nombra la causa, el limite nuevo y cuantos quedan en solo lectura", () => {
    const out = renderMail("subscription-downgraded", {
      tier: "plan1", limit: 2, blockedCount: 5, reason: "paused",
    });

    expect(out.text).toContain("Pausaste tu suscripción.");
    expect(out.text).toContain("límite de 2 alumnos");
    expect(out.text).toContain("5 alumnos quedaron en solo lectura");
    // Vocabulario copiado literal de blocked_students_screen.dart: es el mismo
    // hecho contado por dos canales, y si divergen el PF cree que son dos.
    expect(out.text).toContain("no editarles rutinas ni notas");
  });

  it("cada causa tiene su frase, y una desconocida no inventa ninguna", () => {
    const frase = (reason: string) =>
      renderMail("subscription-downgraded", { limit: 2, reason }).text;

    expect(frase("cancelled-expired")).toContain("Se terminó el período que tenías pagado.");
    expect(frase("pending")).toContain("Tu suscripción todavía no está confirmada.");
    expect(frase("tier-change")).toContain("Cambiaste de plan.");
    expect(frase("loquesea")).toContain("Cambió tu suscripción.");
  });

  // Los tres salieron de LEER el mail renderizado, no el codigo. Ninguno
  // rompia un test ni el compilador.
  it("plan3 no dice 'seguís con alumnos sin límite'", () => {
    const out = renderMail("subscription-grace", { tier: "plan3", limit: "sin-tope" });

    expect(out.text).not.toContain("seguís con alumnos sin límite");
    expect(out.text).toContain("seguís sin límite de alumnos");
  });

  // "Ampliá tu plan" sobre una pausa manda a comprar mas de algo que el PF ya
  // pago: el problema ahi no es el tamaño del plan, es que no esta al dia.
  it("solo pide ampliar el plan cuando la causa ES el plan", () => {
    const pausa = renderMail("subscription-downgraded", {
      limit: 2, blockedCount: 3, reason: "paused",
    });
    const bajada = renderMail("subscription-downgraded", {
      limit: 7, blockedCount: 3, reason: "tier-change",
    });

    expect(pausa.text).toContain("poné tu suscripción al día");
    expect(pausa.text).not.toContain("ampliá tu plan");
    expect(pausa.html).toContain("REGULARIZAR MI SUSCRIPCIÓN");

    expect(bajada.text).toContain("ampliá tu plan");
    expect(bajada.html).toContain("AMPLIAR MI PLAN");
  });

  it("una causa desconocida pide regularizar, no ampliar", () => {
    const out = renderMail("subscription-downgraded", {
      limit: 2, blockedCount: 1, reason: "loquesea",
    });

    expect(out.html).toContain("REGULARIZAR MI SUSCRIPCIÓN");
  });

  // Le decia "para volver a trabajar con todos, ampliá tu plan" a alguien que
  // YA esta trabajando con todos: un pedido de plata sobre un problema que no
  // existe. Y "tus alumnos no pierden nada" inventaba una preocupacion.
  it("sin bloqueados no pide plata ni inventa una preocupacion", () => {
    const out = renderMail("subscription-downgraded", {
      tier: "plan1", limit: 7, blockedCount: 0, reason: "tier-change",
    });

    expect(out.text).toContain("Ninguno de tus alumnos quedó fuera de tu cupo.");
    expect(out.text).not.toContain("ampliá tu plan");
    expect(out.text).not.toContain("no pierden nada");
  });

  it("con 0 bloqueados no dibuja la linea de solo lectura", () => {
    const out = renderMail("subscription-downgraded", {
      tier: "plan1", limit: 7, blockedCount: 0, reason: "tier-change",
    });

    expect(out.text).not.toContain("solo lectura");
    expect(out.subject).not.toContain("solo lectura");
  });

  it("un solo alumno se dice en singular", () => {
    const out = renderMail("subscription-downgraded", {
      limit: 2, blockedCount: 1, reason: "paused",
    });

    expect(out.text).toContain("1 alumno quedó en solo lectura");
  });

  // El render mas caro posible: decirle al PF que NO tiene tope justo cuando no
  // pudimos leer su limite. Un limite que no sabemos no es un limite infinito.
  it("un limite ilegible no se anuncia como 'sin límite'", () => {
    // El `undefined` va con cast a proposito: el tipo lo prohibe, pero un
    // param que el productor se olvida de mandar llega exactamente asi, y ese
    // es el caso que este test cubre.
    for (const limit of [undefined as unknown as string, "", "ochenta"]) {
      const out = renderMail("subscription-downgraded", { limit, reason: "paused" });

      expect(out.text).not.toContain("sin límite");
      expect(out.text).not.toContain("NaN");
      expect(out.text).toContain("un límite más bajo");
    }
  });

  // El centinela se distingue de un limite ilegible: uno dice "sin límite", el
  // otro "más bajo". Lo que se prueba acá es que se RECONOCE, no la redaccion
  // exacta — de eso se ocupa el test de la frase de arriba.
  it("el centinela de plan3 se reconoce como sin tope", () => {
    const out = renderMail("subscription-grace", { tier: "plan3", limit: "sin-tope" });

    expect(out.text).toContain("sin límite");
    expect(out.text).not.toContain("sin-tope");
    expect(out.text).not.toContain("NaN");
  });

  it("un conteo roto no imprime NaN", () => {
    const out = renderMail("subscription-downgraded", {
      limit: 2, blockedCount: "muchos", reason: "paused",
    });

    expect(out.text).not.toContain("NaN");
    expect(out.text).not.toContain("solo lectura");
  });

  it("los dos van al destino del ENTRENADOR cuando el productor lo pasa", () => {
    for (const kind of ["subscription-grace", "subscription-downgraded"] as const) {
      const html = renderMail(kind, { ctaUrl: "https://app.gettreino.com/abrir/profe" }).html;

      expect(ctaHref(html)).toBe("https://app.gettreino.com/abrir/profe");
    }
  });
});

// ---------------------------------------------------------------------------
// Botón de Baja de Servicio — los dos mails de `baja-por-mail.ts`
// ---------------------------------------------------------------------------
describe("mails de la baja por mail", () => {
  const LINK =
    "https://gettreino.com/es/baja-de-servicio/confirmar#t=" + "A".repeat(43);
  const CODE = "BAJA-2026-0A1B2C";

  describe("service-cancel-confirm", () => {
    it("pone el código en el asunto y en el cuerpo", () => {
      const out = renderMail("service-cancel-confirm", { actionLink: LINK, code: CODE });

      expect(out.subject).toBe(`Confirmá la baja de tu suscripción — código ${CODE}`);
      expect(out.text).toContain(CODE);
    });

    it("sin código el asunto no queda colgando", () => {
      const out = renderMail("service-cancel-confirm", { actionLink: LINK });

      expect(out.subject).toBe("Confirmá la baja de tu suscripción");
      expect(out.subject).not.toContain("código");
      expect(out.text).not.toContain("Código");
    });

    it("el botón CONFIRMAR BAJA lleva al link, con el token en el fragmento", () => {
      const out = renderMail("service-cancel-confirm", { actionLink: LINK, code: CODE });

      expect(out.html).toContain("CONFIRMAR BAJA");
      expect(ctaHref(out.html)).toBe(LINK);
      // Quien lee en texto plano también tiene que poder confirmar.
      expect(out.text).toContain(LINK);
    });

    // `sendQueuedMail` borra `actionLink` al enviar. Re-renderizado sin él, el
    // mail no puede ofrecer un botón muerto.
    it("sin link no dibuja botón", () => {
      const out = renderMail("service-cancel-confirm", { code: CODE });

      expect(ctaHref(out.html)).toBe("");
      expect(out.html).not.toContain("CONFIRMAR BAJA");
    });

    it("dice que vence en 72 horas y que si no lo pediste no se cancela nada", () => {
      const out = renderMail("service-cancel-confirm", { actionLink: LINK });

      expect(out.text).toContain("72 horas");
      expect(out.text).toContain("Si no lo pediste vos, ignorá este mail");
      expect(out.text).toContain("no se cancela nada");
    });

    // Lo pudo pedir cualquiera tipeando el correo: el mail no le cuenta nada a
    // quien no sea el dueño, y tampoco repite la dirección.
    it("no nombra a la persona ni repite el correo", () => {
      const out = renderMail("service-cancel-confirm", { actionLink: LINK, code: CODE });

      expect(out.text.replace(LINK, "")).not.toContain("@");
    });
  });

  describe("service-cancel-done", () => {
    // 2026-10-10T02:00Z es todavía el 9 de octubre en Buenos Aires.
    const ISO = "2026-10-10T02:00:00.000Z";

    it("pone el código en el asunto", () => {
      const out = renderMail("service-cancel-done", { code: CODE, accesoHastaIso: ISO });

      expect(out.subject).toBe(`Tu baja quedó hecha — código ${CODE}`);
    });

    it("sin código el asunto no queda colgando", () => {
      expect(renderMail("service-cancel-done", {}).subject).toBe("Tu baja quedó hecha");
    });

    it("la fecha de acceso sale en hora de Argentina", () => {
      const out = renderMail("service-cancel-done", { code: CODE, accesoHastaIso: ISO });

      expect(out.text).toContain("Conservás el acceso hasta el 09/10/2026");
      expect(out.text).not.toContain("10/10/2026");
    });

    // Una fecha inventada es peor que ninguna (AGENTS.md §11.1).
    it("sin fecha, o con una ilegible, omite la frase entera", () => {
      for (const params of [{}, { accesoHastaIso: "mañana" }] as MailParams[]) {
        const out = renderMail("service-cancel-done", params);

        expect(out.text).not.toContain("Conservás el acceso");
        expect(out.text).not.toContain("NaN");
        expect(out.text).not.toContain("Invalid");
      }
    });

    // Espejo de terminos-suscripcion.md §7.
    it("dice lo que promete el §7 de los términos", () => {
      const out = renderMail("service-cancel-done", { accesoHastaIso: ISO });

      expect(out.text).toContain("no se te vuelve a cobrar");
      expect(out.text).toContain("No se reembolsa el período en curso");
      expect(out.text).toContain("No se borra nada");
    });

    it("no tiene botón", () => {
      expect(ctaHref(renderMail("service-cancel-done", { accesoHastaIso: ISO }).html))
        .toBe("");
    });
  });
});

// ---------------------------------------------------------------------------
// Tildes — el copy es castellano rioplatense, con voseo
// ---------------------------------------------------------------------------
describe("tildes", () => {
  /**
   * Palabras que en el copy de la casa —castellano rioplatense, con voseo—
   * están mal escritas sin tilde.
   *
   * Los comentarios de este repo se escriben sin tildes por costumbre, y ese
   * hábito se filtró una vez al texto que lee el usuario: el mail de
   * `free-limit-reached` salió con "podes", "aca", "limite" y "cuantas". Es el
   * mail que le pide que pague.
   *
   * Dos tienen un homógrafo correcto, raro en un mail: "limite" (que el plan
   * te limite) y "ultima" (del verbo ultimar). Si alguna vez hace falta uno,
   * reformulá la frase o sacá la palabra de acá con el motivo al lado. Quedan
   * afuera a propósito "que" y "cuantas": sin tilde son correctas todo el
   * tiempo, en su otra función.
   */
  const SIN_TILDE = [
    "podes", "tenes", "queres", "sabes", "aca", "alla", "ahi",
    "limite", "limites", "sesion", "suscripcion", "contrasena",
    "ultimo", "ultima", "proximo", "proxima", "dias", "tambien", "despues",
  ];

  it.each(ALL_KINDS)("%s no tiene palabras sin su tilde", (kind) => {
    const { subject, text } = renderMail(kind, {
      trainerName: "Jose",
      athleteName: "Marta",
      otherName: "Jose",
      dateLabel: "martes 26 de agosto",
      timeLabel: "19:00",
      amountLabel: "$ 25.000",
      dueLabel: "26/08/2026",
    });
    // Las URLs quedan afuera: `/suscripcion/checkout` es una ruta, no copy.
    const copy = `${subject}\n${text}`.replace(/https?:\/\/\S+/g, "");
    const palabras = copy.toLowerCase().match(/[a-zñáéíóúü]+/g) ?? [];

    expect(palabras.filter((p) => SIN_TILDE.includes(p))).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Botón de Arrepentimiento
//
// NO es la baja: la baja conserva el acceso y no devuelve plata; el
// arrepentimiento devuelve todo, y sólo dentro de los 10 días. Los textos lo
// tienen que dejar clarísimo, y ninguno puede prometer un plazo de devolución
// que los términos (§6) no prometen.
// ---------------------------------------------------------------------------
describe("Botón de Arrepentimiento", () => {
  const LINK = "https://gettreino.com/es/arrepentimiento/confirmar#t=abc";
  const CODE = "ARR-2026-0A1B2C";
  // 00:00 del 24/09/2026 en Argentina.
  const ULTIMO_DIA = "2026-09-24T03:00:00.000Z";

  describe("withdrawal-confirm", () => {
    it("lleva el código en el asunto y el link en el botón", () => {
      const out = renderMail("withdrawal-confirm", { actionLink: LINK, code: CODE });

      expect(out.subject).toBe(`Confirmá tu arrepentimiento — código ${CODE}`);
      expect(ctaHref(out.html)).toBe(LINK);
      expect(out.html).toContain("CONFIRMAR ARREPENTIMIENTO");
    });

    it("sin link no dibuja un botón muerto", () => {
      const out = renderMail("withdrawal-confirm", { code: CODE });

      expect(out.html).not.toContain("CONFIRMAR ARREPENTIMIENTO");
      expect(out.html).not.toContain("href=\"\"");
    });

    it("dice que la confirmación es un click y que el link vence", () => {
      // Los escáneres de correo pre-abren los links: el copy dice «tocá el botón».
      const { text } = renderMail("withdrawal-confirm", { actionLink: LINK });

      expect(text).toContain("tocá el botón");
      expect(text).toContain("72 horas");
      expect(text).toContain("una sola vez");
    });

    it("no se confunde con la baja", () => {
      const { text } = renderMail("withdrawal-confirm", { actionLink: LINK, code: CODE });

      expect(text).not.toMatch(/dar de baja|tu baja/i);
    });
  });

  describe("withdrawal-received", () => {
    it("dentro de plazo: se devuelve lo pagado y no se cobra más", () => {
      const { text, subject } = renderMail("withdrawal-received", { code: CODE });

      expect(subject).toBe(`Recibimos tu arrepentimiento — código ${CODE}`);
      expect(text).toContain("dentro del plazo de 10 días");
      expect(text).toContain("no se te vuelve a cobrar");
      expect(text).toContain("Te devolvemos lo pagado por el mismo medio de pago");
      // Se devuelve TODO, así que no queda acceso gratis hasta fin de período.
      expect(text).toContain("Los beneficios del plan pago terminan ahora");
    });

    it("⚠️ no promete un plazo de devolución que los términos no prometen", () => {
      // §6 dice «a continuación te devolvemos el dinero». Un «en 48 horas»
      // escrito acá sería una promesa nueva, y la cumple una persona a mano.
      const { text } = renderMail("withdrawal-received", { code: CODE });
      const sin10Dias = text.replace("10 días", "");

      expect(sin10Dias).not.toMatch(/\b\d+\s*(horas?|hs|d[ií]as?)\b/i);
    });

    it("⚠️ en revisión NO dice que se canceló ni que se devuelve", () => {
      // Es la franja donde un feriado pudo correr el plazo: no se tocó nada, y
      // el texto no puede decir lo contrario.
      const { text, subject } = renderMail("withdrawal-received", {
        code: CODE, revision: "1",
      });

      expect(subject).toBe(`Estamos revisando tu arrepentimiento — código ${CODE}`);
      expect(text).toContain("Todavía no cancelamos nada");
      expect(text).not.toMatch(/devolvemos|dada de baja|no se te vuelve a cobrar/i);
    });

    it("no tiene botón: no hay nada que la persona tenga que hacer", () => {
      expect(ctaHref(renderMail("withdrawal-received", { code: CODE }).html)).toBe("");
    });
  });

  describe("withdrawal-expired", () => {
    it("dice cuándo venció, en hora de Argentina", () => {
      const { text } = renderMail("withdrawal-expired", {
        code: CODE, ultimoDiaIso: ULTIMO_DIA,
      });

      expect(text).toContain("venció el 24/09/2026");
    });

    it("sin fecha no inventa una", () => {
      const { text } = renderMail("withdrawal-expired", { code: CODE });

      expect(text).toContain("ya venció");
      expect(text).not.toMatch(/venció el/);
    });

    it("dice que no se devuelve y le muestra lo que SÍ puede hacer: la baja", () => {
      // Espejo de terminos-suscripcion.md §7.
      const out = renderMail("withdrawal-expired", { code: CODE, ultimoDiaIso: ULTIMO_DIA });

      expect(out.text).toContain("no podemos devolver lo pagado");
      expect(out.text).toContain("conservás el acceso hasta el final del período que ya pagaste");
      expect(ctaHref(out.html)).toBe("https://gettreino.com/es/baja-de-servicio");
    });
  });

  describe("withdrawal-team-notice", () => {
    const DATOS = {
      estado: "dentro",
      code: CODE,
      email: "ana@example.com",
      uid: "u1",
      contratoIso: "2026-09-20T15:00:00.000Z",
      diasTranscurridos: 4,
      ultimoDiaIso: ULTIMO_DIA,
      monto: 3500,
      cobros: 1,
      suscripciones: "sub1, sub2",
      canceladas: 1,
    };

    it("dentro de plazo: dice que hay que DEVOLVER y trae todo para hacerlo", () => {
      const { subject, text } = renderMail("withdrawal-team-notice", DATOS);

      expect(subject).toBe(`Devolver pago: arrepentimiento ${CODE} dentro de plazo`);
      expect(text).toContain("Falta devolver el pago");
      expect(text).toContain("ana@example.com");
      expect(text).toContain("sub1, sub2");
      expect(text).toContain("3.500");
      expect(text).toContain("20/09/2026");
    });

    it("en el límite: dice REVISAR y que NO se canceló nada", () => {
      const { subject, text } = renderMail("withdrawal-team-notice", {
        ...DATOS, estado: "a-revisar", canceladas: 0,
      });

      expect(subject).toMatch(/^REVISAR arrepentimiento/);
      expect(text).toContain("No se canceló nada");
      expect(text).not.toContain("Falta devolver el pago");
    });

    it("dentro de plazo dice que el acceso se cortó; en el límite, que sigue igual", () => {
      expect(renderMail("withdrawal-team-notice", DATOS).text)
        .toContain("Acceso al plan pago: cortado en el acto");
      expect(renderMail("withdrawal-team-notice", { ...DATOS, estado: "a-revisar" }).text)
        .toContain("Acceso al plan pago: sigue igual");
    });

    it("advierte el resto prepago de un plan anterior, y sólo cuando existe", () => {
      const con = renderMail("withdrawal-team-notice", {
        ...DATOS, pisoTier: "plan3", pisoHastaIso: "2026-10-20T15:00:00.000Z",
      }).text;
      expect(con).toContain("conserva el resto prepago de un plan anterior (plan3 hasta el 20/10/2026)");
      expect(con).toContain("quitalo a mano");

      expect(renderMail("withdrawal-team-notice", DATOS).text).not.toContain("resto prepago");
    });

    it("un dato que falta se dice, no se inventa ni se deja en blanco", () => {
      const { text } = renderMail("withdrawal-team-notice", { estado: "dentro" });

      expect(text).toContain("Contratación (según Mercado Pago): sin dato");
    });

    it("escapa el mail de la cuenta: es texto libre de un tercero", () => {
      const { html } = renderMail("withdrawal-team-notice", {
        ...DATOS, email: "<img src=x onerror=alert(1)>@x.com",
      });

      expect(html).not.toContain("<img src=x");
      expect(html).toContain("&lt;img");
    });

    it("no tiene botón", () => {
      expect(ctaHref(renderMail("withdrawal-team-notice", DATOS).html)).toBe("");
    });
  });
});

// ---------------------------------------------------------------------------
// Código de verificación del mail (`auth/codigo-de-verificacion.ts`)
//
// Es el mail que tiene que abrir TODO el que entra a la app, y el único lugar
// donde se le puede decir que los pagos van por mail: la app no puede.
// ---------------------------------------------------------------------------
describe("código de verificación del mail", () => {
  const CODIGO = "048213";
  const AMBOS = ["email-code-athlete", "email-code-trainer"] as const;

  it.each(AMBOS)("%s lleva el código en el asunto y como titular", (kind) => {
    const out = renderMail(kind, { codigo: CODIGO });

    expect(out.subject).toContain(CODIGO);
    // El titular es la primera línea del texto plano.
    expect(out.text.split("\n")[0]).toBe(CODIGO);
    expect(out.text).toContain("vence en 15 minutos");
  });

  it.each(AMBOS)("%s dice que los pagos y sus confirmaciones van por mail", (kind) => {
    const out = renderMail(kind, { codigo: CODIGO });

    expect(out.text).toMatch(/pagos .* se hacen por mail/);
    // La etiqueta del botón vive en el HTML; el texto plano lleva la URL.
    expect(out.html).toContain("VER LOS PLANES");
  });

  it("el del alumno manda al checkout de gettreino.com", () => {
    const out = renderMail("email-code-athlete", { codigo: CODIGO });

    expect(out.text).toContain("https://gettreino.com/es/suscripcion/checkout");
  });

  it("el del entrenador manda a los planes del Coach Hub web, no a la app", () => {
    // La app no vende: un PF que toca el botón en el teléfono tiene que caer en
    // la web, donde se contrata. Ver `trainerWebCheckout`.
    const out = renderMail("email-code-trainer", { codigo: CODIGO });

    expect(out.text).toContain("https://app.gettreino.com/?to=facturacion");
    expect(out.text).not.toContain("/suscripcion/checkout");
  });

  it.each(AMBOS)("%s sin código no rompe ni dice «undefined»", (kind) => {
    const out = renderMail(kind, {});

    expect(out.subject).not.toContain("undefined");
    expect(out.text).not.toContain("undefined");
    expect(out.text.split("\n")[0]).toBe("Confirmá tu mail");
  });
});

// ---------------------------------------------------------------------------
// Pie de baja de los correos promocionales
//
// Decreto 1558/01, Anexo I, art. 27, párrafo 3: en toda comunicación con fines
// de publicidad hay que indicar «en forma expresa y destacada» cómo pedir el
// retiro. `sendQueuedMail` decide al enviar y le pasa la URL a `renderMail`;
// estos tests miran qué hace la plantilla con ella.
// ---------------------------------------------------------------------------
describe("pie de baja de los correos promocionales", () => {
  const BAJA = "https://gettreino.com/es/correos-promocionales/baja#t=v1.abc.def.ghi";
  const MUTED_GRIS = "#9BA8A1";
  const BONE_BLANCO = "#FFFFFF";

  /**
   * Transcripciones EXACTAS de `design.md` §2. Se copian acá a propósito, y no
   * se importan de `templates.ts`: un test que lee la constante que prueba
   * pasaría igual con la transcripción retocada.
   */
  const LEY_25326 =
    "Ley 25.326, art. 27, inc. 3: \"El titular podrá en cualquier momento " +
    "solicitar el retiro o bloqueo de su nombre de los bancos de datos a los que " +
    "se refiere el presente artículo.\"";
  const DECRETO_1558 =
    "Decreto 1558/01, Anexo I, art. 27, párrafo 3: \"En toda comunicación con " +
    "fines de publicidad que se realice por correo, teléfono, correo electrónico, " +
    "Internet u otro medio a distancia a conocer, se deberá indicar, en forma " +
    "expresa y destacada, la posibilidad del titular del dato de solicitar el " +
    "retiro o bloqueo, total o parcial, de su nombre de la base de datos. A pedido " +
    "del interesado, se deberá informar el nombre del responsable o usuario del " +
    "banco de datos que proveyó la información.\"";
  const RESPONSABLE = "Responsable: BACKHAUSTIN S.A.S. — CUIT 30-71929587-4";
  const AVISO =
    "Recibís este correo promocional porque tenés una cuenta en TREINO. " +
    "Si no querés recibir más, ";
  const LINK_TEXTO = "dejá de recibir correos promocionales";

  /** `esc()` escribe `&quot;`; el lector ve la comilla. Se compara lo que se VE. */
  const visible = (html: string) => html.replace(/&quot;/g, "\"");

  const PARAMS: MailParams = {
    trainerName: "Jose",
    athleteName: "Marta",
    otherName: "Jose",
    dateLabel: "martes 26 de agosto",
    timeLabel: "19:00",
    amountLabel: "$ 25.000",
    dueLabel: "26/08/2026",
    limit: 2,
    blockedCount: 3,
  };

  describe("sin la opción, el mail sale como siempre", () => {
    it.each(ALL_KINDS)("%s: pasar `{}` o `{comercial: true}` no cambia nada", (kind) => {
      const base = renderMail(kind, PARAMS);

      expect(renderMail(kind, PARAMS, {})).toEqual(base);
      expect(renderMail(kind, PARAMS, { comercial: true })).toEqual(base);
    });

    it.each(ALL_KINDS)("%s: el pie es el de hoy y el texto plano no tiene pie", (kind) => {
      const { html, text } = renderMail(kind, PARAMS);

      expect(html).toContain(
        "Recibís este mail porque tenés una cuenta en TREINO.<br>" +
          "<a href=\"https://gettreino.com\" style=\"color:" + MUTED_GRIS + ";\">" +
          "gettreino.com</a></div>",
      );
      for (const huella of ["promocional", "Ley 25.326", "Decreto 1558", "BACKHAUSTIN"]) {
        expect(html).not.toContain(huella);
        expect(text).not.toContain(huella);
      }
    });
  });

  describe("con la opción", () => {
    it.each(ALL_KINDS)("%s: lleva el link en el HTML y la URL completa en el texto", (kind) => {
      const { html, text } = renderMail(kind, PARAMS, { bajaDePromocionales: BAJA });

      expect(html).toContain(`<a href="${BAJA}"`);
      expect(html).toContain(`>${LINK_TEXTO}</a>`);
      expect(text).toContain(BAJA);
    });

    it.each(ALL_KINDS)("%s: transcribe los dos textos y nombra al responsable", (kind) => {
      const { html, text } = renderMail(kind, PARAMS, { bajaDePromocionales: BAJA });

      for (const literal of [LEY_25326, DECRETO_1558, RESPONSABLE]) {
        expect(text).toContain(literal);
        expect(visible(html)).toContain(literal);
      }
    });

    it("el aviso dice «promocional» y reemplaza al «Recibís este mail» del pie común", () => {
      const { html, text } = renderMail("link-requested", PARAMS, {
        bajaDePromocionales: BAJA,
      });

      expect(visible(html)).toContain(AVISO);
      expect(text).toContain(`${AVISO}${LINK_TEXTO}:\n${BAJA}`);
      // Dos frases casi iguales una abajo de la otra serían ruido.
      expect(html).not.toContain("Recibís este mail porque");
    });

    it("conserva el link de marca a la landing", () => {
      const { html } = renderMail("link-requested", PARAMS, { bajaDePromocionales: BAJA });

      expect(html).toContain(">gettreino.com</a>");
    });

    it("el texto plano lleva el pie DESPUÉS del botón y el cuerpo", () => {
      // Hoy el text/plain no tiene pie: sin esto, quien lee en texto no tendría
      // el mecanismo, que la norma pide en toda comunicación de publicidad.
      const { text } = renderMail("limit-reached", { ...PARAMS, ctaUrl: "https://app.gettreino.com/x" }, {
        bajaDePromocionales: BAJA,
      });

      const ordenados = [
        text.indexOf("Llegaste al tope"),
        text.indexOf("https://app.gettreino.com/x"),
        text.indexOf(BAJA),
        text.indexOf("Ley 25.326"),
        text.indexOf("Decreto 1558"),
        text.indexOf("Responsable:"),
      ];
      expect(ordenados.every((i) => i >= 0)).toBe(true);
      expect([...ordenados].sort((a, b) => a - b)).toEqual(ordenados);
    });

    it("el aviso está DESTACADO: color del cuerpo y letra más grande que el pie chico", () => {
      const { html } = renderMail("link-requested", PARAMS, { bajaDePromocionales: BAJA });

      // El <div> que contiene el link de baja.
      const divDelAviso = html.match(/<div style="([^"]*)">Recibís este correo promocional/);
      expect(divDelAviso).not.toBeNull();
      const estilo = divDelAviso![1];
      expect(estilo).toContain(`color:${BONE_BLANCO}`);
      expect(estilo).not.toContain(MUTED_GRIS);
      expect(estilo).toContain("font-size:14px");

      // Y las transcripciones van en el gris chico del pie.
      const divDeLasNormas = html.match(/<div style="([^"]*)">Ley 25\.326/);
      expect(divDeLasNormas).not.toBeNull();
      expect(divDeLasNormas![1]).toContain(`color:${MUTED_GRIS}`);
      expect(divDeLasNormas![1]).toContain("font-size:12px");
    });

    it("escapa la URL: no puede romper el atributo ni abrir un tag", () => {
      const hostil = "https://x.test/?a=1&b=\"><script>alert(1)</script>";
      const { html, text } = renderMail("link-requested", PARAMS, {
        bajaDePromocionales: hostil,
      });

      expect(html).not.toContain("<script>");
      expect(html).toContain("&lt;script&gt;");
      expect(html).toContain("a=1&amp;b=&quot;&gt;");
      // En text/plain no hay nada que escapar: va tal cual.
      expect(text).toContain(hostil);
    });

    it("no filtra «undefined» ni «null»", () => {
      const { html, text } = renderMail("link-requested", {}, { bajaDePromocionales: BAJA });

      expect(`${html} ${text}`).not.toMatch(/undefined|null|NaN/);
    });

    it("la opción agrega el pie y no toca el cuerpo ni el asunto", () => {
      const sin = renderMail("appointment-confirmed", PARAMS);
      const con = renderMail("appointment-confirmed", PARAMS, { bajaDePromocionales: BAJA });

      expect(con.subject).toBe(sin.subject);
      expect(con.text.startsWith(sin.text)).toBe(true);
    });
  });

  describe("limit-reached con `comercial: false`", () => {
    const CTA = "https://app.gettreino.com/?to=facturacion";
    const render = (opciones?: Parameters<typeof renderMail>[2]) =>
      renderMail("limit-reached", { limit: 2, blockedCount: 3, ctaUrl: CTA }, opciones);

    it("omite la línea de venta", () => {
      const { html, text } = render({ comercial: false });

      expect(text).not.toContain("planes más grandes");
      expect(text).not.toContain("Si querés seguir sumando");
      expect(html).not.toContain("planes más grandes");
    });

    it("omite el botón VER LOS PLANES, y su URL en el texto plano", () => {
      const { html, text } = render({ comercial: false });

      expect(html).not.toContain("VER LOS PLANES");
      expect(ctaHref(html)).toBe("");
      // Con el botón fuera, la URL del CTA tampoco puede quedar en el texto.
      expect(text).not.toContain(CTA);
      expect(html).not.toContain(CTA);
    });

    it("CONSERVA lo operativo: el tope, los bloqueados y que no pierden nada", () => {
      const { text } = render({ comercial: false });

      expect(text).toContain("2 alumnos");
      expect(text).toContain("3 alumnos quedaron en solo lectura");
      expect(text).toContain("Tus alumnos no pierden nada");
    });

    it("sin opciones (o con `comercial: true`) sigue llevando el bloque entero", () => {
      for (const { html, text } of [render(), render({ comercial: true })]) {
        expect(text).toContain("Si querés seguir sumando, hay planes más grandes.");
        expect(html).toContain("VER LOS PLANES");
        expect(ctaHref(html)).toBe(CTA);
        expect(text).toContain(CTA);
      }
    });

    it("es independiente del pie de baja", () => {
      // Sin bloque comercial y con pie: combinación que `sendQueuedMail` no
      // produce hoy, pero la plantilla no tiene por qué asumir que no existe.
      const { html, text } = render({ comercial: false, bajaDePromocionales: BAJA });

      expect(text).not.toContain("planes más grandes");
      expect(text).toContain(BAJA);
      expect(html).toContain(`<a href="${BAJA}"`);
    });

    it.each(ALL_KINDS.filter((k) => k !== "limit-reached"))(
      "%s: ignora `comercial: false` (no tiene bloque que omitir)",
      (kind) => {
        expect(renderMail(kind, PARAMS, { comercial: false })).toEqual(
          renderMail(kind, PARAMS),
        );
      },
    );
  });
});
