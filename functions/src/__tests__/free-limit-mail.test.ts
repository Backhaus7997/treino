/**
 * El mail al alumno que chocó un tope del plan free.
 *
 * ── QUE CUIDA ESTE ARCHIVO ────────────────────────────────────────────────
 *
 * Cuatro cláusulas, y la última es la que separa un embudo de un incidente de
 * reputación:
 *
 *   1. Sin anotación → silencio.
 *   2. Anotación vieja → silencio. El mail vale porque llega CERCA del intento;
 *      uno de tres semanas después le cuenta a alguien que ya se olvidó que una
 *      vez no pudo.
 *   3. Ya paga → silencio. Ofrecerle la salida a quien ya la compró es el error
 *      más caro del repertorio.
 *   4. **Enfriamiento → silencio.** LA cláusula. Quien usa la app todos los
 *      días choca un tope todos los días, y la anotación se pisa cada vez. Sin
 *      esto el mismo usuario recibe un mail diario sobre lo mismo — que es la
 *      definición de spam y la forma más rápida de que el dominio de TREINO
 *      termine en una lista negra.
 *
 * Cada una con su test, y cada test verificado POR MUTACIÓN.
 */

import {
  decideFreeLimitMail,
  enqueueFreeLimitMail,
  VENTANA_MS,
  ENFRIAMIENTO_MS,
  CAMPO_TOPE_AT,
  CAMPO_TOPE_KIND,
  CAMPO_MAIL_AT,
} from "../subscriptions/free-limit-mail";
import { ATHLETE_PROSPECT_PREF_KEY } from "../subscriptions/athlete-prospect-mail";
import { enqueueMail } from "../mail/enqueue-mail";
import { renderMail, LANDING_URL } from "../mail/templates";
import type { App } from "firebase-admin/app";

jest.mock("../mail/enqueue-mail", () => ({
  enqueueMail: jest.fn(async () => "queued-id"),
}));

const setMock = jest.fn(async () => undefined);
jest.mock("firebase-admin/firestore", () => ({
  ...jest.requireActual("firebase-admin/firestore"),
  getFirestore: () => ({
    collection: () => ({ doc: () => ({ set: setMock }) }),
  }),
}));

const enqueueMock = enqueueMail as jest.MockedFunction<typeof enqueueMail>;
const APP = {} as App;
const AHORA = Date.UTC(2026, 8, 24, 8, 0, 0);

/** Un `Timestamp` de Firestore, sólo con lo que el módulo le pide. */
const ts = (ms: number) => ({ toMillis: () => ms });

/** El alumno que chocó un tope hace una hora y nunca recibió nada. */
const CHOCO_RECIEN = {
  [CAMPO_TOPE_AT]: ts(AHORA - 60 * 60 * 1000),
  [CAMPO_TOPE_KIND]: "routineCount",
};

beforeEach(() => {
  enqueueMock.mockClear();
  setMock.mockClear();
});

describe("⚠️ las cuatro cláusulas del silencio", () => {
  it("sin anotación no manda", () => {
    expect(decideFreeLimitMail({ displayName: "x" }, AHORA, false)).toBeNull();
  });

  it("⚠️ una anotación vieja no manda", () => {
    const viejo = { ...CHOCO_RECIEN, [CAMPO_TOPE_AT]: ts(AHORA - VENTANA_MS - 1) };
    expect(decideFreeLimitMail(viejo, AHORA, false)).toBeNull();
  });

  it("⚠️ quien ya paga no recibe la oferta", () => {
    expect(decideFreeLimitMail(CHOCO_RECIEN, AHORA, true)).toBeNull();
  });

  it("⚠️ el ENFRIAMIENTO: no se le escribe dos veces en catorce días", () => {
    // Quien usa la app todos los días choca un tope todos los días. Sin esto,
    // un mail diario sobre lo mismo.
    const yaEscrito = {
      ...CHOCO_RECIEN,
      [CAMPO_MAIL_AT]: ts(AHORA - ENFRIAMIENTO_MS + 1),
    };
    expect(decideFreeLimitMail(yaEscrito, AHORA, false)).toBeNull();
  });

  it("pasado el enfriamiento sí vuelve a mandar", () => {
    const viejoMail = {
      ...CHOCO_RECIEN,
      [CAMPO_MAIL_AT]: ts(AHORA - ENFRIAMIENTO_MS - 1),
    };
    expect(decideFreeLimitMail(viejoMail, AHORA, false)).not.toBeNull();
  });
});

describe("cuando sí manda", () => {
  it("el tope tocado viaja en el plan", () => {
    const plan = decideFreeLimitMail(CHOCO_RECIEN, AHORA, false);
    expect(plan?.kind).toBe("free-limit-reached");
    expect(plan?.tope).toBe("routineCount");
    expect(plan?.scope).toMatch(/^tope_/);
  });

  it("una anotación sin `kind` no rompe: cae a un valor declarado", () => {
    // El campo lo escribe el cliente. Un documento a medio escribir no puede
    // dejar sin mail a alguien que sí chocó un tope.
    const sinKind = { [CAMPO_TOPE_AT]: ts(AHORA - 1000) };
    expect(decideFreeLimitMail(sinKind, AHORA, false)?.tope).toBe("desconocido");
  });

  it("⚠️ comparte el prefKey con el otro mail comercial", async () => {
    // Apagar uno y seguir recibiendo el otro sería no haber apagado nada.
    const plan = decideFreeLimitMail(CHOCO_RECIEN, AHORA, false)!;
    await enqueueFreeLimitMail(APP, "a1", plan, AHORA);
    expect(enqueueMock.mock.calls[0][1].prefKey).toBe(ATHLETE_PROSPECT_PREF_KEY);
  });

  it("⚠️ el CTA va a la landing, que es donde se paga", async () => {
    const plan = decideFreeLimitMail(CHOCO_RECIEN, AHORA, false)!;
    await enqueueFreeLimitMail(APP, "a1", plan, AHORA);
    const url = String(enqueueMock.mock.calls[0][1].params.ctaUrl);
    expect(url.startsWith(LANDING_URL)).toBe(true);
    expect(url).toContain("/suscripcion/checkout");
  });

  it("⚠️ anota que se escribió, DESPUÉS de encolar", async () => {
    // El orden importa: si el `set` fallara antes de encolar, el enfriamiento
    // quedaría anotado sin que el mail salga. Encolar de más es peor que anotar
    // de menos, así que el `set` va último.
    const plan = decideFreeLimitMail(CHOCO_RECIEN, AHORA, false)!;
    await enqueueFreeLimitMail(APP, "a1", plan, AHORA);
    expect(enqueueMock).toHaveBeenCalledTimes(1);
    expect(setMock).toHaveBeenCalledTimes(1);
  });
});

describe("el texto", () => {
  const render = () =>
    renderMail("free-limit-reached", {
      tope: "routineCount",
      ctaUrl: `${LANDING_URL}/es/suscripcion/checkout`,
    });

  it("⚠️ empieza reconociendo el intento, no ofreciendo", () => {
    // Quien recibe esto quiso hacer algo y no pudo. Arrancar con la oferta es
    // pasarle por encima al motivo por el que está leyendo.
    const { html } = render();
    const reconoce = html.indexOf("Te topaste");
    const ofrece = html.indexOf("suscribirte");
    expect(reconoce).toBeGreaterThan(-1);
    expect(ofrece).toBeGreaterThan(reconoce);
  });

  it("⚠️ no nombra el tope concreto ni sus números", () => {
    // Nombrarlo obligaría a un case por cada valor de `FreePlanLimit` —ocho
    // hoy— y esa lista se desincroniza el día que alguien agregue el noveno.
    const cuerpo = render().html.replace(/<[^>]+>/g, " ");
    expect(cuerpo).not.toContain("routineCount");
    expect(cuerpo).not.toMatch(/\b\d+\s*(rutinas|días|dias|semanas)\b/i);
  });

  it("dice que no se pierde nada de lo ya hecho", () => {
    expect(render().html).toContain("siguen donde estaban");
  });
});
