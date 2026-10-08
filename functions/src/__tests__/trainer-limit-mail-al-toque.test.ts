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

/**
 * Mismo fake que `trainer-limit-mail.test.ts` — ver el comentario ahí. Acá
 * hace falta porque `alTocarElTope` ya no decide sobre `despues`: sólo lo usa
 * para `esToqueNuevo` y el chequeo de `role`. La decisión de verdad la hace
 * `enqueueTrainerLimitMail` releyendo `users/{uid}` FRESCO — así que cada
 * test tiene que sembrar `usersStore[uid]` con lo que "ya está" en Firestore
 * (normalmente, el mismo `despues` que dispara el trigger).
 */
let usersStore: Record<string, Record<string, unknown> | undefined> = {};
const colaExiste = true;
const colaGetMock = jest.fn(async () => ({ exists: colaExiste }));
const DELETE_SENTINEL = Symbol("FieldValue.delete()");

interface FakeRef {
  uid: string;
}
interface FakeTx {
  get: (ref: FakeRef) => Promise<{ data: () => Record<string, unknown> | undefined }>;
  set: (ref: FakeRef, patch: Record<string, unknown>) => void;
  update: (ref: FakeRef, patch: Record<string, unknown>) => void;
}

let mutex: Promise<unknown> = Promise.resolve();
const runTransactionMock = jest.fn((fn: (tx: FakeTx) => Promise<unknown>) => {
  const tx: FakeTx = {
    get: async (ref) => ({ data: () => usersStore[ref.uid] }),
    set: (ref, patch) => {
      usersStore[ref.uid] = { ...(usersStore[ref.uid] ?? {}), ...patch };
    },
    update: (ref, patch) => {
      const next = { ...(usersStore[ref.uid] ?? {}) };
      for (const [k, v] of Object.entries(patch)) {
        if (v === DELETE_SENTINEL) delete next[k];
        else next[k] = v;
      }
      usersStore[ref.uid] = next;
    },
  };
  const run = mutex.then(() => fn(tx));
  mutex = run.catch(() => undefined);
  return run;
});

jest.mock("firebase-admin/firestore", () => ({
  ...jest.requireActual("firebase-admin/firestore"),
  FieldValue: { delete: () => DELETE_SENTINEL },
  getFirestore: () => ({
    collection: (name: string) =>
      name === "users"
        ? { doc: (uid: string) => ({ uid }) }
        : { doc: () => ({ get: colaGetMock }) },
    runTransaction: runTransactionMock,
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
  colaGetMock.mockClear();
  runTransactionMock.mockClear();
  usersStore = {};
  mutex = Promise.resolve();
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
    usersStore["t1"] = CON_TOPE;
    const r = await alTocarElTope(APP, "t1", PERFIL, CON_TOPE, AHORA);
    expect(r).toBe("encolado");
    expect(enqueueMock).toHaveBeenCalledTimes(1);
    expect(enqueueMock.mock.calls[0][1]).toMatchObject({
      toUid: "t1",
      kind: "exercise-limit-reached",
    });
    expect(usersStore["t1"]?.[CAMPO_MAIL_AT]).toBeDefined();
  });

  it("⚠️ el segundo despertar —el de su propia escritura— no encola nada", async () => {
    const conMail = { ...CON_TOPE, [CAMPO_MAIL_AT]: ts(AHORA) };
    usersStore["t1"] = conMail;
    const r = await alTocarElTope(APP, "t1", CON_TOPE, conMail, AHORA);
    expect(r).toBe("sin-tope-nuevo");
    expect(enqueueMock).not.toHaveBeenCalled();
  });

  it("⚠️ un alumno con trainerLimitHitAt anotado (dato corrupto o forjado) no recibe el mail del PF", async () => {
    const alumnoConTope = { ...CON_TOPE, role: "athlete" };
    usersStore["a1"] = alumnoConTope;
    const r = await alTocarElTope(
      APP,
      "a1",
      { ...PERFIL, role: "athlete" },
      alumnoConTope,
      AHORA,
    );
    expect(r).toBe("no-trainer");
    expect(enqueueMock).not.toHaveBeenCalled();
    expect(runTransactionMock).not.toHaveBeenCalled();
  });

  it("⚠️ el enfriamiento corta también al toque", async () => {
    // Choca el tope de nuevo tres días después del último mail.
    const antes = { ...CON_TOPE, [CAMPO_MAIL_AT]: ts(AHORA - 3 * 86_400_000) };
    const despues = { ...antes, [CAMPO_TOPE_AT]: ts(AHORA) };
    usersStore["t1"] = despues;
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
    usersStore["t1"] = despues;
    expect(await alTocarElTope(APP, "t1", antes, despues, AHORA)).toBe(
      "encolado",
    );
  });

  it("⚠️ quien ya no está en el tope (subió de plan) no recibe el mail", async () => {
    const sinTope = { ...CON_TOPE, planLimits: { customExercises: null } };
    usersStore["t1"] = sinTope;
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
    usersStore["t1"] = conTopeDePlantillas;
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

  // #1264 (P2 de Codex, primera vuelta): el mismo PF choca los dos topes casi
  // al mismo tiempo — dos escrituras de `users/{uid}` con `kind` distinto,
  // cada una disparando su propio `alTocarElTope`. Antes de la reserva
  // transaccional, las dos decidían sobre su propio snapshot y las dos
  // encolaban (kinds distintos, la dedupe de la cola no las veía).
  //
  // #1267 (P2 de Codex, segunda vuelta — el fix de arriba se pasó de
  // frenada): la reserva transaccional relee `users/{uid}` FRESCO para
  // decidir, y ANTES de este test —tal como estaba escrito— eso incluía
  // adivinar el KIND del documento fresco. Con dos toques de kinds distintos
  // casi juntos, el trigger del PRIMERO terminaba viendo el kind que el
  // SEGUNDO ya había escrito, y el mail del primero se perdía: exactamente
  // lo que esta aserción medía como "correcto" (UN solo mail) hasta ahora.
  // Con `EventoTope` fijando el kind al snapshot que disparó cada trigger
  // (ver el encabezado del módulo, "EL KIND... VIAJAN CON EL EVENTO"), cada
  // uno decide sobre SU PROPIO tope: dos kinds distintos, dos mails.
  it("⚠️ chocar DOS TOPES DISTINTOS casi al mismo tiempo dispara DOS mails, uno por kind", async () => {
    const base = {
      ...PERFIL,
      [CAMPO_TOPE_AT]: ts(AHORA),
      planLimits: { customExercises: 20, templates: 3 },
      customExerciseUsage: { count: 20 },
      templateUsage: { count: 3 },
    };
    // Lo que queda en Firestore es el ÚLTIMO de los dos toques en escribirse
    // — acá "templates", sin que importe cuál: cada `alTocarElTope` fija su
    // propio kind desde `despues`, así que lo que haya de fresco en el
    // documento no decide MÁS que la cláusula 3 y el enfriamiento de ESE
    // kind puntual.
    usersStore["t1"] = { ...base, [CAMPO_TOPE_KIND]: "templates" };
    const despuesEjercicios = { ...base, [CAMPO_TOPE_KIND]: "customExercises" };
    const despuesPlantillas = usersStore["t1"];

    const [a, b] = await Promise.all([
      alTocarElTope(APP, "t1", PERFIL, despuesEjercicios, AHORA),
      alTocarElTope(APP, "t1", PERFIL, despuesPlantillas, AHORA),
    ]);

    expect([a, b].filter((r) => r === "encolado")).toHaveLength(2);
    expect(enqueueMock).toHaveBeenCalledTimes(2);
    const kindsEnviados = enqueueMock.mock.calls.map((c) => c[1].kind).sort();
    expect(kindsEnviados).toEqual(["exercise-limit-reached", "template-limit-reached"]);
    const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as Record<string, unknown>;
    expect(mailAt.customExercises).toBeDefined();
    expect(mailAt.templates).toBeDefined();
  });

  it("⚠️ chocar el MISMO tope dos veces casi al mismo tiempo dispara UN solo mail", async () => {
    // Control: dos triggers del MISMO kind, casi juntos (ej. un reintento del
    // cliente). Acá SÍ tiene que ganar la reserva transaccional — la carrera
    // que cierra la cláusula 4 (enfriamiento) dentro del MISMO kind, que
    // "la carrera dentro del MISMO kind" ya cubre para `enqueueTrainerLimitMail`
    // directo; esto lo confirma también pasando por `alTocarElTope`.
    const despues = {
      ...PERFIL,
      [CAMPO_TOPE_AT]: ts(AHORA),
      [CAMPO_TOPE_KIND]: "customExercises",
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 20 },
    };
    usersStore["t1"] = despues;

    const [a, b] = await Promise.all([
      alTocarElTope(APP, "t1", PERFIL, despues, AHORA),
      alTocarElTope(APP, "t1", PERFIL, despues, AHORA),
    ]);

    expect([a, b].filter((r) => r === "encolado")).toHaveLength(1);
    expect(enqueueMock).toHaveBeenCalledTimes(1);
  });
});
