/**
 * El mail del tope, AL TOQUE: el trigger sobre `users/{uid}`.
 *
 * ── QUE CUIDA ESTE ARCHIVO ────────────────────────────────────────────────
 *
 * Las cuatro cláusulas del silencio ya las cuida `free-limit-mail.test.ts`
 * sobre `decideFreeLimitMail`, que el trigger reusa. Acá se prueba lo que es
 * PROPIO del camino al toque:
 *
 *   1. **Que no haga loop.** El trigger escribe `freePlanLimitMailAt` en el
 *      mismo documento que lo dispara. Esa escritura lo vuelve a despertar y
 *      tiene que salir sin encolar nada.
 *   2. **Que ignore el resto del perfil.** Casi toda escritura de
 *      `users/{uid}` es un cambio de nombre, foto o preferencias.
 *   3. **Que respete lo mismo que el barrido**: el vinculado no recibe la
 *      oferta, y el enfriamiento corta.
 */

import {
  alTocarElTope,
  esToqueNuevo,
  CAMPO_TOPE_AT,
  CAMPO_TOPE_KIND,
  CAMPO_MAIL_AT,
  ENFRIAMIENTO_MS,
} from "../subscriptions/free-limit-mail";
import { enqueueMail } from "../mail/enqueue-mail";
import { hasActiveTrainerLink } from "../subscriptions/athlete-paywall-enforced";
import type { App } from "firebase-admin/app";

jest.mock("../mail/enqueue-mail", () => ({
  ...jest.requireActual("../mail/enqueue-mail"),
  enqueueMail: jest.fn(async () => "queued-id"),
}));

jest.mock("../subscriptions/athlete-paywall-enforced", () => ({
  ...jest.requireActual("../subscriptions/athlete-paywall-enforced"),
  hasActiveTrainerLink: jest.fn(async () => false),
}));

const setMock = jest.fn(async () => undefined);
jest.mock("firebase-admin/firestore", () => ({
  ...jest.requireActual("firebase-admin/firestore"),
  getFirestore: () => ({
    collection: () => ({
      doc: () => ({ set: setMock, get: async () => ({ exists: true }) }),
    }),
  }),
}));

const enqueueMock = enqueueMail as jest.MockedFunction<typeof enqueueMail>;
const vinculoMock = hasActiveTrainerLink as jest.MockedFunction<
  typeof hasActiveTrainerLink
>;
const APP = {} as App;
const AHORA = Date.UTC(2026, 8, 25, 13, 0, 0);

/** Un `Timestamp` de Firestore, sólo con lo que el módulo le pide. */
const ts = (ms: number) => ({ toMillis: () => ms });

const PERFIL = { displayName: "Valentina", role: "athlete" };
/** El mismo perfil, un segundo después de que la hoja anotó el tope. */
const CON_TOPE = {
  ...PERFIL,
  [CAMPO_TOPE_AT]: ts(AHORA - 1000),
  [CAMPO_TOPE_KIND]: "days",
};

beforeEach(() => {
  enqueueMock.mockClear();
  setMock.mockClear();
  vinculoMock.mockReset();
  vinculoMock.mockResolvedValue(false);
});

describe("esToqueNuevo", () => {
  it("el primer tope es nuevo", () => {
    expect(esToqueNuevo(PERFIL, CON_TOPE)).toBe(true);
  });

  it("volver a chocar el tope (la anotación se pisa) es nuevo", () => {
    const otraVez = { ...CON_TOPE, [CAMPO_TOPE_AT]: ts(AHORA) };
    expect(esToqueNuevo(CON_TOPE, otraVez)).toBe(true);
  });

  it("⚠️ la escritura del enfriamiento NO es un tope nuevo", () => {
    // El trigger se escribe a sí mismo `freePlanLimitMailAt`. Si esto diera
    // `true`, cada mail dispararía el siguiente.
    const conMail = { ...CON_TOPE, [CAMPO_MAIL_AT]: ts(AHORA) };
    expect(esToqueNuevo(CON_TOPE, conMail)).toBe(false);
  });

  it("⚠️ un cambio de perfil con un tope viejo adentro NO es un tope nuevo", () => {
    const otroNombre = { ...CON_TOPE, displayName: "Vale" };
    expect(esToqueNuevo(CON_TOPE, otroNombre)).toBe(false);
  });

  it("un perfil sin tope no es nada", () => {
    expect(esToqueNuevo(PERFIL, { ...PERFIL, displayName: "Vale" })).toBe(false);
  });
});

describe("alTocarElTope", () => {
  it("el tope nuevo encola el mail y anota el enfriamiento", async () => {
    const r = await alTocarElTope(APP, "a1", PERFIL, CON_TOPE, AHORA);
    expect(r).toBe("encolado");
    expect(enqueueMock).toHaveBeenCalledTimes(1);
    expect(enqueueMock.mock.calls[0][1]).toMatchObject({
      toUid: "a1",
      kind: "free-limit-reached",
    });
    expect(setMock).toHaveBeenCalledTimes(1);
  });

  it("⚠️ el segundo despertar —el de su propia escritura— no encola nada", async () => {
    const conMail = { ...CON_TOPE, [CAMPO_MAIL_AT]: ts(AHORA) };
    const r = await alTocarElTope(APP, "a1", CON_TOPE, conMail, AHORA);
    expect(r).toBe("sin-tope-nuevo");
    expect(enqueueMock).not.toHaveBeenCalled();
    // Ni siquiera gasta la query del vínculo.
    expect(vinculoMock).not.toHaveBeenCalled();
  });

  it("⚠️ el vinculado no recibe la oferta: su profe ya paga por él", async () => {
    vinculoMock.mockResolvedValue(true);
    const r = await alTocarElTope(APP, "a1", PERFIL, CON_TOPE, AHORA);
    expect(r).toBe("vinculado");
    expect(enqueueMock).not.toHaveBeenCalled();
  });

  it("⚠️ el enfriamiento corta también al toque", async () => {
    // Choca el tope de nuevo tres días después del último mail.
    const antes = { ...CON_TOPE, [CAMPO_MAIL_AT]: ts(AHORA - 3 * 86_400_000) };
    const despues = { ...antes, [CAMPO_TOPE_AT]: ts(AHORA) };
    const r = await alTocarElTope(APP, "a1", antes, despues, AHORA);
    expect(r).toBe("silencio");
    expect(enqueueMock).not.toHaveBeenCalled();
  });

  it("pasado el enfriamiento, el tope nuevo vuelve a escribir", async () => {
    const antes = {
      ...CON_TOPE,
      [CAMPO_MAIL_AT]: ts(AHORA - ENFRIAMIENTO_MS - 1),
    };
    const despues = { ...antes, [CAMPO_TOPE_AT]: ts(AHORA) };
    expect(await alTocarElTope(APP, "a1", antes, despues, AHORA)).toBe(
      "encolado",
    );
  });

  it("⚠️ quien ya paga no recibe la oferta", async () => {
    const pagando = {
      ...CON_TOPE,
      athleteSubscription: { status: "active" },
    };
    expect(await alTocarElTope(APP, "a1", PERFIL, pagando, AHORA)).toBe(
      "silencio",
    );
    expect(enqueueMock).not.toHaveBeenCalled();
  });
});
