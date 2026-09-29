/**
 * El mail del tope del PF, AL TOQUE: el trigger sobre `users/{uid}`.
 *
 * ── QUE CUIDA ESTE ARCHIVO ────────────────────────────────────────────────
 *
 * Las cuatro cláusulas del silencio ya las cuida `trainer-limit-mail.test.ts`
 * sobre `decideTrainerLimitMail`, que el trigger reusa. Acá se prueba lo que
 * es PROPIO del camino al toque:
 *
 *   1. **Que no haga loop.** El trigger escribe `trainerLimitMailAt` en el
 *      mismo documento que lo dispara. Esa escritura lo vuelve a despertar y
 *      tiene que salir sin encolar nada.
 *   2. **Que ignore el resto del perfil.** Casi toda escritura de
 *      `users/{uid}` es un cambio de nombre, foto o preferencias.
 *   3. **Que un alumno nunca dispare el mail del PF**, aunque de alguna forma
 *      tuviera `trainerLimitHitAt` anotado.
 *   4. **Que respete el enfriamiento**, igual que el barrido.
 *   5. **Los dos `kind`**, ejercicios propios y plantillas — mismo criterio
 *      `describe.each` que `trainer-limit-mail.test.ts`.
 */

import {
  alTocarElTope,
  esToqueNuevo,
  CAMPO_TOPE_AT,
  CAMPO_TOPE_KIND,
  CAMPO_MAIL_AT,
  ENFRIAMIENTO_MS,
} from "../subscriptions/trainer-limit-mail";
import { enqueueMail } from "../mail/enqueue-mail";
import type { App } from "firebase-admin/app";

jest.mock("../mail/enqueue-mail", () => ({
  ...jest.requireActual("../mail/enqueue-mail"),
  enqueueMail: jest.fn(async () => "queued-id"),
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
const APP = {} as App;
const AHORA = Date.UTC(2026, 8, 25, 13, 0, 0);

/** Un `Timestamp` de Firestore, sólo con lo que el módulo le pide. */
const ts = (ms: number) => ({ toMillis: () => ms });

const PERFIL = { displayName: "Martín", role: "trainer" };
/** El mismo perfil, un segundo después de que el cliente anotó el tope. */
const CON_TOPE = {
  ...PERFIL,
  [CAMPO_TOPE_AT]: ts(AHORA - 1000),
  [CAMPO_TOPE_KIND]: "customExercises",
  planLimits: { customExercises: 20 },
  customExerciseUsage: { count: 20 },
};

beforeEach(() => {
  enqueueMock.mockClear();
  setMock.mockClear();
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
    // El trigger se escribe a sí mismo `trainerLimitMailAt`. Si esto diera
    // `true`, cada mail dispararía el siguiente.
    const conMail = { ...CON_TOPE, [CAMPO_MAIL_AT]: ts(AHORA) };
    expect(esToqueNuevo(CON_TOPE, conMail)).toBe(false);
  });

  it("⚠️ un cambio de perfil con un tope viejo adentro NO es un tope nuevo", () => {
    const otroNombre = { ...CON_TOPE, displayName: "Marti" };
    expect(esToqueNuevo(CON_TOPE, otroNombre)).toBe(false);
  });

  it("un perfil sin tope no es nada", () => {
    expect(esToqueNuevo(PERFIL, { ...PERFIL, displayName: "Marti" })).toBe(
      false,
    );
  });
});

describe("alTocarElTope", () => {
  it("el tope nuevo encola el mail y anota el enfriamiento", async () => {
    const r = await alTocarElTope(APP, "t1", PERFIL, CON_TOPE, AHORA);
    expect(r).toBe("encolado");
    expect(enqueueMock).toHaveBeenCalledTimes(1);
    expect(enqueueMock.mock.calls[0][1]).toMatchObject({
      toUid: "t1",
      kind: "exercise-limit-reached",
    });
    expect(setMock).toHaveBeenCalledTimes(1);
  });

  it("⚠️ el segundo despertar —el de su propia escritura— no encola nada", async () => {
    const conMail = { ...CON_TOPE, [CAMPO_MAIL_AT]: ts(AHORA) };
    const r = await alTocarElTope(APP, "t1", CON_TOPE, conMail, AHORA);
    expect(r).toBe("sin-tope-nuevo");
    expect(enqueueMock).not.toHaveBeenCalled();
  });

  it("⚠️ un alumno con trainerLimitHitAt anotado (dato corrupto o forjado) no recibe el mail del PF", async () => {
    const alumnoConTope = { ...CON_TOPE, role: "athlete" };
    const r = await alTocarElTope(
      APP,
      "a1",
      { ...PERFIL, role: "athlete" },
      alumnoConTope,
      AHORA,
    );
    expect(r).toBe("no-trainer");
    expect(enqueueMock).not.toHaveBeenCalled();
    expect(setMock).not.toHaveBeenCalled();
  });

  it("⚠️ el enfriamiento corta también al toque", async () => {
    // Choca el tope de nuevo tres días después del último mail.
    const antes = { ...CON_TOPE, [CAMPO_MAIL_AT]: ts(AHORA - 3 * 86_400_000) };
    const despues = { ...antes, [CAMPO_TOPE_AT]: ts(AHORA) };
    const r = await alTocarElTope(APP, "t1", antes, despues, AHORA);
    expect(r).toBe("silencio");
    expect(enqueueMock).not.toHaveBeenCalled();
  });

  it("pasado el enfriamiento, el tope nuevo vuelve a escribir", async () => {
    const antes = {
      ...CON_TOPE,
      [CAMPO_MAIL_AT]: ts(AHORA - ENFRIAMIENTO_MS - 1),
    };
    const despues = { ...antes, [CAMPO_TOPE_AT]: ts(AHORA) };
    expect(await alTocarElTope(APP, "t1", antes, despues, AHORA)).toBe(
      "encolado",
    );
  });

  it("⚠️ quien ya no está en el tope (subió de plan) no recibe el mail", async () => {
    const sinTope = { ...CON_TOPE, planLimits: { customExercises: null } };
    expect(await alTocarElTope(APP, "t1", PERFIL, sinTope, AHORA)).toBe(
      "silencio",
    );
    expect(enqueueMock).not.toHaveBeenCalled();
  });

  it("el tope de plantillas también encola al toque", async () => {
    const conTopeDePlantillas = {
      ...PERFIL,
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "templates",
      planLimits: { templates: 3 },
      templateUsage: { count: 3 },
    };
    const r = await alTocarElTope(
      APP,
      "t1",
      PERFIL,
      conTopeDePlantillas,
      AHORA,
    );
    expect(r).toBe("encolado");
    expect(enqueueMock.mock.calls[0][1]).toMatchObject({
      kind: "template-limit-reached",
    });
  });
});
