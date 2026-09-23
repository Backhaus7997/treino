/**
 * El mail al ALUMNO que se quedó sin cobertura.
 *
 * ── QUE CUIDA ESTE ARCHIVO ────────────────────────────────────────────────
 *
 * Cuatro cláusulas, y cada una es la diferencia entre un mail y un incidente:
 *
 *   1. **`"barrido"` → silencio.** ESTA es la grande, y es la que el mail del
 *      PF no tuvo que pensar. `sweepAthletePaywall` llama al mismo
 *      `syncAthletePaywallEnforced`, así que la primera corrida después de
 *      encender `ATHLETE_PAYWALL_ENFORCEMENT_ENABLED` voltea a TODOS los
 *      alumnos sin cobertura que ya existen, cada uno con su `changed: true`
 *      perfectamente legítimo. Sin esta cláusula, encender el flag le manda el
 *      mail a la base entera en una corrida.
 *
 *   2. `degraded` → silencio. No le escribimos a nadie sobre plata en base a un
 *      documento que sabemos que leímos mal.
 *
 *   3. `!changed` → silencio. El DELTA: «está sin cobertura» describe a media
 *      base, «se quedó sin cobertura recién» describe a una persona.
 *
 *   4. `!value` → silencio. `changed` también es `true` cuando el campo pasa de
 *      `true` a `false`, que es la noticia CONTRARIA — un profe lo tomó y
 *      recuperó cobertura. Ese no lleva mail ninguno, y mandárselo sería el
 *      peor de los cuatro errores: venderle a alguien que acaba de recibir algo
 *      gratis.
 *
 * Cada una tiene su test, y cada test se verificó POR MUTACIÓN: sacando la
 * cláusula, ESE test —y no otro— se pone rojo. Un test que pasa igual sin la
 * cláusula no prueba nada.
 */

import {
  decideAthleteProspectMail,
  enqueueAthleteProspectMail,
  avisarAlAlumnoSinCobertura,
  ATHLETE_PROSPECT_PREF_KEY,
} from "../subscriptions/athlete-prospect-mail";
import { enqueueMail } from "../mail/enqueue-mail";
import { renderMail, LANDING_URL } from "../mail/templates";
import type { App } from "firebase-admin/app";
import { readFileSync } from "fs";
import { join } from "path";

jest.mock("../mail/enqueue-mail", () => ({
  enqueueMail: jest.fn(async () => "queued-id"),
}));

const enqueueMock = enqueueMail as jest.MockedFunction<typeof enqueueMail>;
const APP = {} as App;
const AHORA = Date.UTC(2026, 8, 23, 15, 0, 0);

/** El caso que SÍ manda: el campo acaba de pasar a `true`, por un evento. */
const SE_QUEDO_SIN_COBERTURA = { uid: "a1", value: true, changed: true };

beforeEach(() => enqueueMock.mockClear());

describe("⚠️ las cláusulas del silencio", () => {
  it("el BARRIDO no manda, aunque el delta sea real", () => {
    // La primera corrida tras encender el enforcement voltea a toda la base.
    // Cada uno de esos cambios es legítimo y ninguno merece un mail.
    expect(
      decideAthleteProspectMail(SE_QUEDO_SIN_COBERTURA, false, "barrido", AHORA),
    ).toBeNull();
  });

  it("⚠️ el ALTA no manda: nacer sin algo no es perderlo", () => {
    // `athletePaywallInputChanged` trata el CREATE como cambio, a propósito.
    // Un alumno que se registra sin entrenador resuelve a `enforced: true` en
    // su primer milisegundo, con un `changed: true` impecable — y recibiría
    // «tu lugar ya no está cubierto» junto con el mail de bienvenida.
    expect(
      decideAthleteProspectMail(SE_QUEDO_SIN_COBERTURA, false, "alta", AHORA),
    ).toBeNull();
  });

  it("un documento degradado no manda", () => {
    expect(
      decideAthleteProspectMail(SE_QUEDO_SIN_COBERTURA, true, "evento", AHORA),
    ).toBeNull();
  });

  it("sin DELTA no manda, aunque esté sin cobertura", () => {
    // `changed: false` es el alumno que ya estaba sin cobertura desde antes.
    expect(
      decideAthleteProspectMail(
        { uid: "a1", value: true, changed: false },
        false,
        "evento",
        AHORA,
      ),
    ).toBeNull();
  });

  it("⚠️ recuperar cobertura tampoco manda", () => {
    // `changed: true` + `value: false` = un profe lo tomó. Es la noticia
    // contraria. Venderle acá sería cobrarle a quien acaba de recibir algo
    // gratis.
    expect(
      decideAthleteProspectMail(
        { uid: "a1", value: false, changed: true },
        false,
        "evento",
        AHORA,
      ),
    ).toBeNull();
  });
});

describe("cuando sí manda", () => {
  it("devuelve el plan con su scope del día", () => {
    const plan = decideAthleteProspectMail(
      SE_QUEDO_SIN_COBERTURA,
      false,
      "evento",
      AHORA,
    );
    expect(plan).not.toBeNull();
    expect(plan?.kind).toBe("athlete-coverage-lost");
    // El scope lleva la fecha ART: un alumno que su profe da de baja y vuelve a
    // tomar el mismo día produce dos flips, y el segundo cae en el mismo doc de
    // cola en vez de salir dos veces.
    expect(plan?.scope).toMatch(/^sin_cobertura_/);
  });

  it("⚠️ va con prefKey — es comunicación comercial, no transaccional", async () => {
    // Los otros tres mails del paywall van sin `prefKey` porque son
    // transaccionales. Éste le OFRECE un producto a quien no lo compró, y
    // `politica-de-privacidad.md` promete que para las comunicaciones
    // comerciales «la oposición es ABSOLUTA». Sin interruptor eso es mentira.
    const plan = decideAthleteProspectMail(
      SE_QUEDO_SIN_COBERTURA,
      false,
      "evento",
      AHORA,
    )!;
    await enqueueAthleteProspectMail(APP, "a1", plan);

    expect(enqueueMock).toHaveBeenCalledTimes(1);
    expect(enqueueMock.mock.calls[0][1].prefKey).toBe(ATHLETE_PROSPECT_PREF_KEY);
  });

  it("⚠️ el CTA va a la LANDING, no a la app", async () => {
    // Es el único mail del repo cuyo destino es el checkout web, y tiene que
    // serlo: la app no puede decir dónde se paga (Guideline 3.1.3(f)), así que
    // mandarlo a `app.gettreino.com` lo dejaría en un lugar sin salida.
    const plan = decideAthleteProspectMail(
      SE_QUEDO_SIN_COBERTURA,
      false,
      "evento",
      AHORA,
    )!;
    await enqueueAthleteProspectMail(APP, "a1", plan);

    const url = String(enqueueMock.mock.calls[0][1].params.ctaUrl);
    expect(url.startsWith(LANDING_URL)).toBe(true);
    expect(url).toContain("/suscripcion/checkout");
  });
});

describe("el texto", () => {
  const render = () =>
    renderMail("athlete-coverage-lost", {
      ctaUrl: `${LANDING_URL}/es/suscripcion/checkout`,
    });

  it("⚠️ dice PRIMERO que no se pierde nada", () => {
    // Quien recibe esto acaba de perder acceso sin haber hecho nada. El miedo
    // razonable es que se le hayan borrado los entrenamientos: contestar eso
    // antes de ofrecer nada es la diferencia entre un aviso y un aprieto.
    const { html } = render();
    const tranquiliza = html.indexOf("No perdés nada");
    const ofrece = html.indexOf("suscribirte");
    expect(tranquiliza).toBeGreaterThan(-1);
    expect(ofrece).toBeGreaterThan(-1);
    expect(tranquiliza).toBeLessThan(ofrece);
  });

  it("⚠️ no le echa la culpa al entrenador", () => {
    // El disparador tiene DOS causas —el profe terminó el vínculo, o venció la
    // suscripción propia—, así que nombrar al profe es falso en la mitad de los
    // casos y una acusación en la otra.
    const { html, subject } = render();
    const texto = `${subject} ${html}`.toLowerCase();
    for (const palabra of ["entrenador", "profe", "te dio de baja"]) {
      expect(texto).not.toContain(palabra);
    }
  });

  it("⚠️ no enumera los topes del plan free", () => {
    // Los números viven en `athlete_entitlement.dart` y ya se desincronizaron
    // una vez entre la constante, firestore.rules y el .arb. Un cuarto lugar es
    // un cuarto lugar que se puede pudrir.
    const { html } = render();
    const cuerpo = html.replace(/<[^>]+>/g, " ");
    expect(cuerpo).not.toMatch(/\b\d+\s*(rutinas|días|dias|semanas)\b/i);
  });

  it("el CTA sale con la URL que se le pasa", () => {
    const { html } = render();
    expect(html).toContain(`${LANDING_URL}/es/suscripcion/checkout`);
  });
});

describe("el cable", () => {
  it("un evento con delta encola", async () => {
    await avisarAlAlumnoSinCobertura(
      APP,
      SE_QUEDO_SIN_COBERTURA,
      "evento",
      AHORA,
      { info: () => {}, error: () => {} },
    );
    expect(enqueueMock).toHaveBeenCalledTimes(1);
  });

  it("⚠️ el barrido NO encola", async () => {
    await avisarAlAlumnoSinCobertura(
      APP,
      SE_QUEDO_SIN_COBERTURA,
      "barrido",
      AHORA,
      { info: () => {}, error: () => {} },
    );
    expect(enqueueMock).not.toHaveBeenCalled();
  });

  it("⚠️ si el encolado falla, NO tira", async () => {
    // Un fallo mandando un mail COMERCIAL no puede tumbar la reconciliación del
    // entitlement, que es lo que decide si el alumno puede entrenar. El mail es
    // lo prescindible de los dos.
    enqueueMock.mockRejectedValueOnce(new Error("resend caido"));
    const errores: string[] = [];

    await expect(
      avisarAlAlumnoSinCobertura(
        APP,
        SE_QUEDO_SIN_COBERTURA,
        "evento",
        AHORA,
        { info: () => {}, error: (m) => errores.push(m) },
      ),
    ).resolves.toBeUndefined();

    expect(errores).toHaveLength(1);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// El trigger, escaneando el fuente.
//
// ── Por qué un scan y no un test de comportamiento ──
//
// Porque EL BUG VIVIÓ ACÁ, no en `decideAthleteProspectMail`. La primera
// versión pasaba `"evento"` literal desde `syncAthletePaywallOnUser`, y ese
// trigger es el único que ve un create. La función de decisión estaba perfecta
// y sus cuatro tests pasaban: el alumno nuevo recibía el mail igual.
//
// Un test unitario sobre `decide("alta")` no lo habría atrapado nunca — habría
// dado verde sobre una rama que ningún llamador alcanzaba. Es exactamente el
// patrón que este repo ya documenta en `frontera.test.js` y en los guards de
// anti-steering: cuando lo que hay que proteger es una regla ESTRUCTURAL sobre
// quién llama a qué, el escaneo del fuente es lo único que cierra el agujero.
//
// Montar `firebase-functions-test` para emitir un `onDocumentWritten` sintético
// sería más fiel y mucho más caro; y lo que se quiere prohibir —un literal en
// una posición— se lee del texto sin ambigüedad.
// ─────────────────────────────────────────────────────────────────────────────

describe("⚠️ el cableado del trigger, que es donde estuvo el bug", () => {
  const fuente = readFileSync(
    join(__dirname, "..", "subscriptions", "athlete-paywall-enforced.ts"),
    "utf8",
  );

  /** El cuerpo de `syncAthletePaywallOnUser`, que es el único que ve el create. */
  const triggerDelUsuario = () => {
    const desde = fuente.indexOf("export const syncAthletePaywallOnUser");
    const hasta = fuente.indexOf("export const syncAthletePaywallOnTrainerLink");
    expect(desde).toBeGreaterThan(-1);
    expect(hasta).toBeGreaterThan(desde);
    return fuente.slice(desde, hasta);
  };

  it("el escaneo encuentra el trigger (si no, estaría pasando en vacío)", () => {
    expect(triggerDelUsuario()).toContain("avisarAlAlumnoSinCobertura");
  });

  it("⚠️ NO pasa un origen literal — lo deriva del create", () => {
    // Éste es el test que la primera versión no tenía. Con
    // `avisarAlAlumnoSinCobertura(app, r, "evento", …)` escrito a mano, el
    // alumno recién registrado recibía «tu lugar ya no está cubierto» en el
    // mismo segundo del alta.
    const cuerpo = triggerDelUsuario();
    expect(cuerpo).not.toMatch(/avisarAlAlumnoSinCobertura\(\s*app,\s*r,\s*["']/);
    expect(cuerpo).toContain("before === undefined ? \"alta\"");
  });

  it("el trigger del VINCULO sí manda evento: un link no crea un usuario", () => {
    const desde = fuente.indexOf("export const syncAthletePaywallOnTrainerLink");
    const cuerpo = fuente.slice(desde, desde + 2000);
    expect(cuerpo).toMatch(/avisarAlAlumnoSinCobertura\(\s*app,\s*r,\s*"evento"/);
  });

  it("⚠️ el BARRIDO sigue mandando barrido", () => {
    // Su guarda es la que impide que encender el flag le escriba a toda la
    // base. Que siga siendo `"barrido"` no es cosmético.
    const desde = fuente.indexOf("sweepAthletePaywall");
    expect(fuente.slice(desde)).toMatch(
      /avisarAlAlumnoSinCobertura\(\s*app,\s*r,\s*"barrido"/,
    );
  });
});
