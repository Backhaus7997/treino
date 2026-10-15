/** Unit tests for the daily-reminders scheduler. No emulator or real FCM. */

jest.mock("firebase-admin", () => {
  class Timestamp {
    constructor(readonly date: Date) {}
    static fromDate(date: Date): Timestamp {
      return new Timestamp(date);
    }
    toDate(): Date {
      return this.date;
    }
  }
  const DELETE = Symbol("FieldValue.delete");
  const SERVER_TIMESTAMP = Symbol("FieldValue.serverTimestamp");
  const firestore = jest.fn();
  Object.assign(firestore, {
    Timestamp,
    FieldValue: {
      delete: () => DELETE,
      serverTimestamp: () => SERVER_TIMESTAMP,
      __DELETE: DELETE,
    },
  });
  return {
    firestore,
    app: jest.fn(),
    initializeApp: jest.fn(),
  };
});

jest.mock("firebase-admin/messaging", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).messaging());

jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());

// La puerta modular tiene que dar EL MISMO doble que la namespaced de arriba:
// producción importa Timestamp/FieldValue de `firebase-admin/firestore`, y sin
// esto le llega el REAL, que el Firestore de mentira de este archivo no
// reconoce. Lo fija `firebase-admin-mock-surface.test.ts`.
jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

jest.mock("../notifications/send-fcm", () => ({
  sendFcm: jest.fn(async () => ({ successCount: 1, failureCount: 0 })),
}));

import { App } from "firebase-admin/app";
import { Messaging } from "firebase-admin/messaging";
import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { SendFcmInput, sendFcm } from "../notifications/send-fcm";
import { dobleNamespaced } from "./helpers/modular-from-namespaced";
import {
  COMEBACK_COOLDOWN_DAYS,
  DAILY_REMINDERS_PREF_KEY,
  comebackCooldownElapsed,
  comebackCopy,
  daysBetweenDateKeys,
  notifyDailyRemindersHandler,
  streakAtRiskCopy,
} from "../notifications/notify-daily-reminders";

// ─── Un Firestore de mentira con subcolecciones, queries y transacciones ──────
//
// Lo mínimo para que el handler corra de punta a punta: documentos por ruta
// completa, `collection`/`collectionGroup` con where/orderBy/limit/startAfter, y
// `runTransaction` SERIALIZADA (dos transacciones no se pisan, como en el
// servidor real). Las queries respetan la semántica de Firestore que importa acá:
// un documento SIN el campo que se filtra o se ordena no entra al resultado.

type Doc = Record<string, unknown>;

interface QueryLogEntry {
  scope: string;
  fields: string[];
}

interface FakeSnap {
  id: string;
  exists: boolean;
  ref: FakeDocRef;
  data: () => Doc | undefined;
}

interface FakeDocRef {
  id: string;
  path: string;
  parent: FakeCollRef;
  get: () => Promise<FakeSnap>;
  update: (data: Doc) => Promise<void>;
  collection: (name: string) => FakeCollRef;
}

interface FakeQuery {
  where: (field: string, op: string, value: unknown) => FakeQuery;
  orderBy: (field: string, dir?: "asc" | "desc") => FakeQuery;
  limit: (n: number) => FakeQuery;
  startAfter: (cursor: FakeSnap) => FakeQuery;
  get: () => Promise<{ docs: FakeSnap[]; size: number; empty: boolean }>;
}

interface FakeCollRef extends FakeQuery {
  id: string;
  path: string;
  parent: FakeDocRef | null;
  doc: (id: string) => FakeDocRef;
  add: (data: Doc) => Promise<FakeDocRef>;
}

type Scope = { kind: "collection"; path: string } | { kind: "group"; name: string };

interface QueryState {
  scope: Scope;
  filters: Array<[string, string, unknown]>;
  order?: [string, "asc" | "desc"];
  limitN?: number;
  after?: string;
}

/** Normaliza un Timestamp al instante en ms para poder comparar; el resto pasa. */
function comparable(value: unknown): unknown {
  const date = (value as { toDate?: () => Date } | null | undefined)?.toDate?.();
  return date instanceof Date ? date.getTime() : value;
}

function describeValue(value: unknown): string {
  const date = (value as { toDate?: () => Date } | null | undefined)?.toDate?.();
  return date instanceof Date ? date.toISOString() : String(value);
}

function createFake(initial: Record<string, Doc>) {
  const docs = new Map<string, Doc>();
  for (const [path, data] of Object.entries(initial)) docs.set(path, { ...data });
  const queryLog: QueryLogEntry[] = [];
  /**
   * Se ejecuta justo ANTES de cada transacción, o sea después de la lectura
   * previa del handler. Permite simular lo que pasa en el mundo real durante una
   * corrida larga: el usuario cambia algo entre que se lo lee y se lo reserva.
   */
  const hooks: { beforeTransaction?: () => void } = {};
  let autoId = 0;
  let txChain: Promise<unknown> = Promise.resolve();

  const DELETE = (
    dobleNamespaced().firestore as unknown as { FieldValue: { __DELETE: symbol } }
  ).FieldValue.__DELETE;

  const idOf = (path: string): string => path.slice(path.lastIndexOf("/") + 1);
  const parentOf = (path: string): string => path.slice(0, path.lastIndexOf("/"));

  function snapOf(path: string): FakeSnap {
    const raw = docs.get(path);
    return {
      id: idOf(path),
      exists: raw !== undefined,
      ref: docRef(path),
      data: () => (raw ? { ...raw } : undefined),
    };
  }

  function applyUpdate(path: string, update: Doc): void {
    const current = docs.get(path);
    if (!current) throw new Error(`NOT_FOUND ${path}`);
    const next = { ...current };
    for (const [k, v] of Object.entries(update)) {
      if (v === DELETE) delete next[k];
      else next[k] = v;
    }
    docs.set(path, next);
  }

  function docRef(path: string): FakeDocRef {
    return {
      id: idOf(path),
      path,
      parent: collectionRef(parentOf(path)),
      get: async () => snapOf(path),
      update: async (data: Doc) => applyUpdate(path, data),
      collection: (name: string) => collectionRef(`${path}/${name}`),
    };
  }

  function makeQuery(state: QueryState): FakeQuery {
    return {
      where: (field, op, value) =>
        makeQuery({ ...state, filters: [...state.filters, [field, op, value]] }),
      orderBy: (field, dir = "asc") => makeQuery({ ...state, order: [field, dir] }),
      limit: (n) => makeQuery({ ...state, limitN: n }),
      startAfter: (cursor) => makeQuery({ ...state, after: cursor.ref.path }),
      get: async () => {
        const scopeLabel =
          state.scope.kind === "group" ? `group:${state.scope.name}` : state.scope.path;
        queryLog.push({
          scope: scopeLabel,
          fields: [
            ...state.filters.map(([f, op, v]) => `${f}${op}${describeValue(v)}`),
            ...(state.order ? [`orderBy ${state.order[0]} ${state.order[1]}`] : []),
          ],
        });

        let paths = [...docs.keys()].filter((p) =>
          state.scope.kind === "collection" ?
            parentOf(p) === state.scope.path :
            idOf(parentOf(p)) === state.scope.name);

        paths = paths.filter((p) => {
          const doc = docs.get(p) as Doc;
          return state.filters.every(([field, op, expected]) => {
            if (doc[field] === undefined) return false;
            const a = comparable(doc[field]) as number | string;
            const b = comparable(expected) as number | string;
            if (op === "==") return a === b;
            if (op === ">=") return a >= b;
            if (op === ">") return a > b;
            if (op === "<=") return a <= b;
            if (op === "<") return a < b;
            throw new Error(`unexpected operator ${op}`);
          });
        });

        if (state.order) {
          const [field, dir] = state.order;
          paths = paths.filter((p) => (docs.get(p) as Doc)[field] !== undefined);
          paths.sort((p, q) => {
            const a = comparable((docs.get(p) as Doc)[field]) as number;
            const b = comparable((docs.get(q) as Doc)[field]) as number;
            const byField = dir === "asc" ? a - b : b - a;
            return byField !== 0 ? byField : p.localeCompare(q);
          });
        } else {
          paths.sort();
        }

        if (state.after !== undefined) {
          paths = paths.slice(paths.indexOf(state.after) + 1);
        }
        if (state.limitN !== undefined) paths = paths.slice(0, state.limitN);

        const snaps = paths.map(snapOf);
        return { docs: snaps, size: snaps.length, empty: snaps.length === 0 };
      },
    };
  }

  function collectionRef(path: string): FakeCollRef {
    const query = makeQuery({ scope: { kind: "collection", path }, filters: [] });
    return {
      ...query,
      id: idOf(path),
      path,
      parent: path.includes("/") ? docRef(parentOf(path)) : null,
      doc: (id: string) => docRef(`${path}/${id}`),
      add: async (data: Doc) => {
        const id = `auto-${++autoId}`;
        docs.set(`${path}/${id}`, { ...data });
        return docRef(`${path}/${id}`);
      },
    };
  }

  const firestore = {
    collection: (name: string) => collectionRef(name),
    collectionGroup: (name: string) => makeQuery({ scope: { kind: "group", name }, filters: [] }),
    runTransaction: <T>(
      fn: (tx: {
        get: (ref: FakeDocRef) => Promise<FakeSnap>;
        update: (ref: FakeDocRef, data: Doc) => void;
      }) => Promise<T>,
    ): Promise<T> => {
      const run = txChain.then(() => {
        hooks.beforeTransaction?.();
        return fn({
          get: (ref) => ref.get(),
          update: (ref, data) => applyUpdate(ref.path, data),
        });
      });
      txChain = run.catch(() => undefined);
      return run;
    },
  };

  (dobleNamespaced().firestore as unknown as jest.Mock).mockReturnValue(firestore);

  return {
    docs,
    queryLog,
    hooks,
    user: (uid: string): Doc => docs.get(`users/${uid}`) as Doc,
    historyOf: (uid: string): Doc[] =>
      [...docs.entries()]
        .filter(([p]) => p.startsWith(`users/${uid}/notifications/`))
        .map(([, d]) => d),
  };
}

// ─── Builders de datos ────────────────────────────────────────────────────────

/** Hora de pared argentina → instante. `at("2026-05-13T10:00:00")` es 10:00 ART. */
const at = (artWallClock: string): Date => new Date(`${artWallClock}-03:00`);

// Miércoles 2026-05-13, 10:00 ART. Quedan 5 días de la semana contando hoy
// (mié, jue, vie, sáb, dom). Semana en curso: lunes 2026-05-11.
const WED = at("2026-05-13T10:00:00");
// Domingo 2026-05-17: queda 1 día.
const SUN = at("2026-05-17T10:00:00");

let seq = 0;
type Entries = Array<[string, Doc]>;

function sessionAt(
  uid: string,
  wallClock: string,
  over: { status?: string; wasFullyCompleted?: boolean } = {},
): [string, Doc] {
  return [
    `users/${uid}/sessions/s${++seq}`,
    {
      startedAt: Timestamp.fromDate(at(wallClock)),
      status: over.status ?? "finished",
      wasFullyCompleted: over.wasFullyCompleted ?? true,
    },
  ];
}

function addDays(isoDay: string, days: number): string {
  const d = new Date(`${isoDay}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/**
 * [count] sesiones que cuentan en la semana que arranca el lunes [monday]. Las
 * primeras van de lunes a sábado y la ÚLTIMA siempre cae en domingo, para que el
 * "último entrenamiento" de la semana anterior quede a 3 días de un miércoles y
 * NO dispare el "volvé a entrenar" cuando el test es sobre la racha.
 */
function weekEndingSunday(uid: string, monday: string, count: number): Entries {
  const out: Entries = [];
  for (let i = 0; i < count; i++) {
    const day = i === count - 1 ? 6 : i % 6;
    const minute = String(Math.floor(i / 6) * 5).padStart(2, "0");
    out.push(sessionAt(uid, `${addDays(monday, day)}T12:${minute}:00`));
  }
  return out;
}

function user(uid: string, over: Doc = {}): [string, Doc] {
  return [`users/${uid}`, { role: "athlete", ...over }];
}

/** Un día con ejercicios (`work`) o de descanso (slots vacíos). */
function planDays(training: number, rest = 0): Doc[] {
  const day = (n: number, slots: unknown[]) => ({ dayNumber: n, name: `Día ${n}`, slots });
  return [
    ...Array.from({ length: training }, (_, i) => day(i + 1, [{ exerciseId: "e" }])),
    ...Array.from({ length: rest }, (_, i) => day(training + i + 1, [])),
  ];
}

function assignedPlan(id: string, uid: string, training: number, over: Doc = {}): [string, Doc] {
  return [
    `routines/${id}`,
    {
      source: "trainer-assigned",
      assignedTo: uid,
      status: "active",
      createdAt: 100,
      days: planDays(training),
      ...over,
    },
  ];
}

function ownPlan(id: string, uid: string, training: number, over: Doc = {}): [string, Doc] {
  return [
    `routines/${id}`,
    {
      source: "user-created",
      createdBy: uid,
      status: "active",
      createdAt: 50,
      days: planDays(training),
      ...over,
    },
  ];
}

/**
 * Un atleta con la racha de [weeks] semanas cumplidas (objetivo = [target]) y la
 * semana en curso VACÍA, en un miércoles: faltan [target] y quedan 5 días, así
 * que está en riesgo si y sólo si [target] vale 5. Plan asignado de [target] días.
 */
function atRiskAthlete(
  uid: string,
  target: number,
  weeks: number,
  opts: { lastTrainedFriday?: boolean } = {},
): Entries {
  const out: Entries = [user(uid), assignedPlan(`plan-${uid}`, uid, target)];
  for (let w = 1; w <= weeks; w++) {
    const monday = addDays("2026-05-11", -7 * w);
    if (w === 1 && opts.lastTrainedFriday) {
      // Lunes a viernes: el último entreno de la semana anterior queda a 5 días
      // de un miércoles, así que el atleta también califica para el comeback.
      for (let d = 0; d < target; d++) {
        const minute = String(Math.floor(d / 5) * 5).padStart(2, "0");
        out.push(sessionAt(uid, `${addDays(monday, d % 5)}T12:${minute}:00`));
      }
    } else {
      out.push(...weekEndingSunday(uid, monday, target));
    }
  }
  return out;
}

function seed(...groups: Array<Entries | [string, Doc]>): Record<string, Doc> {
  const out: Record<string, Doc> = {};
  for (const group of groups) {
    const entries: Entries = typeof group[0] === "string" ? [group as [string, Doc]] : (group as Entries);
    for (const [path, data] of entries) out[path] = data;
  }
  return out;
}

const app = {} as App;
const messaging = {} as Messaging;
const mockedSendFcm = sendFcm as jest.MockedFunction<typeof sendFcm>;

function lastCall(): SendFcmInput {
  const calls = mockedSendFcm.mock.calls;
  return calls[calls.length - 1][1];
}

let errorLog: jest.SpyInstance;

beforeEach(() => {
  jest.clearAllMocks();
  mockedSendFcm.mockReset();
  mockedSendFcm.mockResolvedValue({ successCount: 1, failureCount: 0 });
  // Sin esto cada corrida vuelca su resumen a la consola. El de errores se
  // espía para poder afirmar que una falla queda registrada.
  jest.spyOn(logger, "info").mockImplementation(() => undefined);
  jest.spyOn(logger, "warn").mockImplementation(() => undefined);
  errorLog = jest.spyOn(logger, "error").mockImplementation(() => undefined);
});

afterEach(() => {
  jest.restoreAllMocks();
});

// ─── Racha en riesgo ──────────────────────────────────────────────────────────

describe("streak-at-risk", () => {
  it("dispara cuando faltan EXACTAMENTE tantos entrenamientos como días quedan", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2)));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(result.notified).toBe(1);
    expect(result.notifiedStreakAtRisk).toBe(1);
    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(mockedSendFcm).toHaveBeenCalledWith(
      app,
      {
        uids: ["u1"],
        kind: "streak-at-risk",
        notification: {
          title: "Hoy o se corta 🔥",
          body: "Te faltan 5 entrenamientos esta semana para sostener tu racha de 2 semanas.",
        },
        data: { deepLink: "/home" },
        prefKey: DAILY_REMINDERS_PREF_KEY,
      },
      messaging,
    );
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
  });

  it("no dispara con UN día de margen (faltan menos de los que quedan)", async () => {
    // Objetivo 4, quedan 5: puede saltear hoy y llegar igual. Ni siquiera es
    // candidato — la semana anterior (4) no llega a `0 + 5`.
    createFake(seed(atRiskAthlete("u1", 4, 2)));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(result.candidates).toBe(0);
  });

  it("no dispara si ya es imposible (faltan MÁS de los que quedan)", async () => {
    // Objetivo 7 con una sesión el martes: faltan 6 y quedan 5. Aunque entrene
    // todos los días que quedan, no llega: la racha ya está perdida y avisarlo
    // sería ruido.
    const fake = createFake(seed(
      atRiskAthlete("u1", 7, 2),
      [sessionAt("u1", "2026-05-12T12:00:00")],
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    // Sí fue candidato (la semana anterior alcanza), pero el objetivo REAL lo descarta.
    expect(result.candidates).toBe(1);
    expect(result.skippedNotAtRisk).toBe(1);
    expect(fake.user("u1").lastDailyReminderDate).toBeUndefined();
  });

  it("dispara con una sesión ya hecha esta semana si el cálculo da justo", async () => {
    // Objetivo 6, una sesión el martes: faltan 5 y quedan 5. "Racha de 1 semana".
    createFake(seed(
      atRiskAthlete("u1", 6, 1),
      [sessionAt("u1", "2026-05-12T12:00:00")],
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(lastCall().notification.body).toBe(
      "Te faltan 5 entrenamientos esta semana para sostener tu racha de 1 semana.",
    );
  });

  it("no dispara sin racha previa: la semana anterior no cumplió", async () => {
    // Objetivo 5 (plan de 5 días) pero la semana pasada sólo hizo 4.
    createFake(seed(
      [user("u1")],
      [assignedPlan("p", "u1", 5)],
      weekEndingSunday("u1", "2026-05-04", 4),
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(result.candidates).toBe(0);
  });

  it("EXCLUYE a quien ya completó una sesión HOY (fecha ART)", async () => {
    // Mismo atleta, mismo objetivo: ayer entrenó → dispara; hoy entrenó → no.
    createFake(seed(
      atRiskAthlete("ayer", 6, 1),
      [sessionAt("ayer", "2026-05-12T12:00:00")],
      atRiskAthlete("hoy", 6, 1),
      [sessionAt("hoy", "2026-05-13T08:00:00")],
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(lastCall()).toMatchObject({ kind: "streak-at-risk" });
    expect(mockedSendFcm.mock.calls[0][1].uids).toEqual(["ayer"]);
    expect(result.notified).toBe(1);
  });

  it("'hoy' es el día ART: una sesión de las 23:30 de ayer NO cuenta como hoy", async () => {
    // 23:30 ART del martes es la 02:30 UTC del miércoles. Con día UTC esto
    // excluiría al atleta por error.
    createFake(seed(
      atRiskAthlete("u1", 6, 1),
      [sessionAt("u1", "2026-05-12T23:30:00")],
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  });

  it("singular: 'Te faltan 1 entrenamiento… racha de 1 semana' un domingo", async () => {
    // Domingo: queda 1 día. Objetivo 3, dos sesiones esta semana → falta 1.
    createFake(seed(
      [user("u1"), assignedPlan("p", "u1", 3)],
      weekEndingSunday("u1", "2026-05-04", 3),
      [sessionAt("u1", "2026-05-11T12:00:00"), sessionAt("u1", "2026-05-12T12:00:00")],
    ));

    await notifyDailyRemindersHandler(app, SUN, messaging);

    expect(lastCall().notification).toEqual({
      title: "Hoy o se corta 🔥",
      body: "Te faltan 1 entrenamiento esta semana para sostener tu racha de 1 semana.",
    });
  });

  it("completa la racha cuando toca el borde de la ventana de 8 semanas", async () => {
    // 8 semanas dentro de la ventana + 4 más ANTES de ella, y una tercera que
    // corta. La racha real es 12; sin la query extra el texto diría 8.
    const entries: Entries = [user("u1"), assignedPlan("p", "u1", 5)];
    for (let w = 1; w <= 12; w++) {
      entries.push(...weekEndingSunday("u1", addDays("2026-05-11", -7 * w), 5));
    }
    entries.push(...weekEndingSunday("u1", addDays("2026-05-11", -7 * 13), 2));
    const fake = createFake(seed(entries));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(lastCall().notification.body).toContain("racha de 12 semanas");
    // Y la extensión pidió las sesiones DE ESE USUARIO, anteriores a la ventana.
    const extension = fake.queryLog.filter((q) => q.scope === "users/u1/sessions");
    expect(extension.length).toBeGreaterThan(0);
    expect(extension[0].fields[0]).toBe("startedAt<2026-03-16T03:00:00.000Z");
  });

  it("la extensión pagina y no se confunde con una semana cortada por la página", async () => {
    // 100 semanas anteriores a la ventana con 6 sesiones cada una = 600 sesiones:
    // la primera página (500) corta la semana 84 por la MITAD. Si el corte se
    // tomara como «semana incumplida», la racha daría 8 + 83.
    const entries: Entries = [user("u1"), assignedPlan("p", "u1", 5)];
    for (let w = 1; w <= 108; w++) {
      entries.push(...weekEndingSunday("u1", addDays("2026-05-11", -7 * w), 6));
    }
    const fake = createFake(seed(entries));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(lastCall().notification.body).toContain("racha de 108 semanas");
    expect(fake.queryLog.filter((q) => q.scope === "users/u1/sessions").length).toBeGreaterThan(1);
  });
});

describe("el objetivo sale de la rutina ACTIVA, con la cadena de tres niveles", () => {
  // Miércoles, semana en curso vacía, quedan 5 días: dispara si y sólo si el
  // objetivo es 5. La semana anterior tiene 6 sesiones (cumple cualquier
  // objetivo ≤ 6), así que lo único que decide es QUÉ rutina se eligió.
  const cases: Array<{
    name: string;
    routines: Entries;
    activeRoutineId?: string;
    fires: boolean;
  }> = [
    {
      name: "el marcador explícito gana sobre un plan del PF más nuevo",
      routines: [assignedPlan("pf", "u1", 3), ownPlan("mia", "u1", 5)],
      activeRoutineId: "mia",
      fires: true,
    },
    {
      name: "sin marcador gana el plan del PF (3 días) y NO el propio (5)",
      routines: [assignedPlan("pf", "u1", 3), ownPlan("mia", "u1", 5)],
      fires: false,
    },
    {
      name: "una rutina asignada ARCHIVADA no cuenta: gana la única propia",
      routines: [assignedPlan("pf", "u1", 3, { status: "archived" }), ownPlan("mia", "u1", 5)],
      fires: true,
    },
    {
      name: "sin ninguna rutina el objetivo es 1",
      routines: [],
      fires: false,
    },
    {
      name: "los días de descanso (slots vacíos) no suman al objetivo",
      routines: [assignedPlan("pf", "u1", 5, { days: planDays(5, 2) })],
      fires: true,
    },
    {
      name: "varias propias sin marcador: no se adivina, el objetivo cae a 1",
      routines: [ownPlan("a", "u1", 5), ownPlan("b", "u1", 5, { createdAt: 60 })],
      fires: false,
    },
    {
      name: "el marcador puede ser una plantilla del catálogo (source system, public)",
      routines: [
        ["routines/ppl", {
          source: "system", visibility: "public", createdAt: 1, days: planDays(5),
        }],
      ],
      activeRoutineId: "ppl",
      fires: true,
    },
    {
      name: "una plantilla del catálogo NO pública no cuenta: el marcador es obsoleto",
      routines: [
        ["routines/ppl", {
          source: "system", visibility: "private", createdAt: 1, days: planDays(5),
        }],
      ],
      activeRoutineId: "ppl",
      fires: false,
    },
    {
      name: "un marcador obsoleto sigue la cadena en vez de dar null",
      routines: [assignedPlan("pf", "u1", 5)],
      activeRoutineId: "borrada",
      fires: true,
    },
  ];

  it.each(cases)("$name", async ({ routines, activeRoutineId, fires }) => {
    createFake(seed(
      [user("u1", activeRoutineId ? { activeRoutineId } : {})],
      routines,
      weekEndingSunday("u1", "2026-05-04", 6),
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(fires ? 1 : 0);
    if (fires) expect(lastCall().kind).toBe("streak-at-risk");
  });

  it("el limit(20) corta ANTES de descartar archivadas, igual que listAssignedTo", async () => {
    // 20 planes archivados (los más nuevos) ocupan toda la página; el único
    // activo es el 21°, que el cliente nunca llega a ver. Si acá se "arreglara"
    // pidiendo más, el servidor vería un objetivo (5) que la app no muestra.
    const archived: Entries = Array.from({ length: 20 }, (_, i) =>
      assignedPlan(`vieja-${i}`, "u1", 3, { status: "archived", createdAt: 1000 + i }));
    createFake(seed(
      [user("u1")],
      archived,
      [assignedPlan("la-21", "u1", 5, { createdAt: 1 })],
      weekEndingSunday("u1", "2026-05-04", 6),
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    // Objetivo 1 (nada visible): faltan 1 y quedan 5. No se manda.
    expect(mockedSendFcm).not.toHaveBeenCalled();
  });

  it("lee las rutinas con las mismas queries que el cliente", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 1)));

    await notifyDailyRemindersHandler(app, WED, messaging);

    const rutinas = fake.queryLog.filter((q) => q.scope === "routines").map((q) => q.fields);
    expect(rutinas).toEqual(expect.arrayContaining([
      ["assignedTo==u1", "source==trainer-assigned", "orderBy createdAt desc"],
      ["createdBy==u1", "source==user-created", "status==active", "orderBy createdAt desc"],
    ]));
  });

  it("NO lee rutinas de quien no es candidato a racha en riesgo", async () => {
    // Entrenó hoy: excluido de la racha antes de tocar nada más.
    const fake = createFake(seed(
      atRiskAthlete("u1", 6, 1),
      [sessionAt("u1", "2026-05-13T08:00:00")],
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(fake.queryLog.some((q) => q.scope === "routines")).toBe(false);
  });
});

// ─── Volvé a entrenar ─────────────────────────────────────────────────────────

describe("comeback-reminder", () => {
  it("dispara a los 4 días ART y escribe los dos marcadores", async () => {
    const fake = createFake(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")], // sábado: 4 días antes del miércoles
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(result.notifiedComeback).toBe(1);
    expect(mockedSendFcm).toHaveBeenCalledWith(
      app,
      {
        uids: ["u1"],
        kind: "comeback-reminder",
        notification: {
          title: "Te extrañamos en el gym 💪",
          body: "Hace 4 días que no entrenás. ¿Arrancamos hoy?",
        },
        data: { deepLink: "/home" },
        prefKey: DAILY_REMINDERS_PREF_KEY,
      },
      messaging,
    );
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
    expect(fake.user("u1").lastComebackReminderDate).toBe("2026-05-13");
  });

  it("no dispara a los 3 días", async () => {
    createFake(seed([user("u1")], [sessionAt("u1", "2026-05-10T12:00:00")]));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(result.candidates).toBe(0);
  });

  it("cuenta DÍAS CALENDARIO ART, no horas corridas", async () => {
    // Sábado 23:30 ART → miércoles 10:00 ART son 82,5 horas (menos de 96) pero
    // 4 días calendario: dispara. Domingo 00:30 ART son 3 días: no.
    createFake(seed(
      [user("tarde")], [sessionAt("tarde", "2026-05-09T23:30:00")],
      [user("temprano")], [sessionAt("temprano", "2026-05-10T00:30:00")],
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(mockedSendFcm.mock.calls[0][1].uids).toEqual(["tarde"]);
  });

  it("la cantidad de días del texto sale de la última sesión que CUENTA", async () => {
    // Una abandonada de ayer no cuenta; la última real fue hace 6 días.
    createFake(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-07T12:00:00")],
      [sessionAt("u1", "2026-05-12T12:00:00", { wasFullyCompleted: false })],
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(lastCall().notification.body).toBe("Hace 6 días que no entrenás. ¿Arrancamos hoy?");
  });

  it("solo ve la ventana: quien se fue hace más de 8 semanas NO recibe nada", async () => {
    // La ventana arranca el lunes 2026-03-16 00:00 ART (03:00 UTC), inclusive.
    const fake = createFake(seed(
      [user("dentro")], [sessionAt("dentro", "2026-03-16T00:00:00")],
      [user("fuera")], [sessionAt("fuera", "2026-03-15T23:59:00")],
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(mockedSendFcm.mock.calls[0][1].uids).toEqual(["dentro"]);
    expect(result.athletesWithSessions).toBe(1);
    // Y la query pidió exactamente esa ventana.
    expect(fake.queryLog[0].fields.slice(0, 2)).toEqual([
      "startedAt>=2026-03-16T03:00:00.000Z",
      "startedAt<2026-05-13T13:00:00.000Z",
    ]);
  });

  it("ignora sesiones abandonadas y en curso: no hay actividad que contar", async () => {
    createFake(seed(
      [user("u1")],
      [
        sessionAt("u1", "2026-05-01T12:00:00", { wasFullyCompleted: false }),
        sessionAt("u1", "2026-05-02T12:00:00", { status: "active" }),
      ],
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(result.athletesWithSessions).toBe(0);
    expect(mockedSendFcm).not.toHaveBeenCalled();
  });
});

describe("cooldown de 7 días del comeback-reminder", () => {
  const run = async (lastComebackReminderDate?: string) => {
    const fake = createFake(seed(
      [user("u1", lastComebackReminderDate ? { lastComebackReminderDate } : {})],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));
    const result = await notifyDailyRemindersHandler(app, WED, messaging);
    return { fake, result };
  };

  it("un envío de hace 6 días sigue bloqueado", async () => {
    const { fake, result } = await run("2026-05-07");
    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(result.skippedCooldown).toBe(1);
    // Bloqueado = no se toca NADA: ni el marcador diario.
    expect(fake.user("u1").lastDailyReminderDate).toBeUndefined();
    expect(fake.user("u1").lastComebackReminderDate).toBe("2026-05-07");
  });

  it("un envío de hace 7 días ya pasa", async () => {
    const { fake } = await run("2026-05-06");
    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(fake.user("u1").lastComebackReminderDate).toBe("2026-05-13");
  });

  it("sin envío previo pasa", async () => {
    await run();
    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  });

  it("la racha NO consume el cooldown del comeback", async () => {
    // Un atleta que califica para los DOS: gana la racha, y el comeback queda
    // disponible para otro día.
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2, { lastTrainedFriday: true })));

    await notifyDailyRemindersHandler(app, WED, messaging);

    // Última sesión el viernes 8: son 5 días, también era candidato a comeback.
    expect(lastCall().kind).toBe("streak-at-risk");
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
    expect(fake.user("u1").lastComebackReminderDate).toBeUndefined();
  });

  it("COMEBACK_COOLDOWN_DAYS es 7 y los bordes de comebackCooldownElapsed", () => {
    expect(COMEBACK_COOLDOWN_DAYS).toBe(7);
    expect(comebackCooldownElapsed(undefined, "2026-05-13")).toBe(true);
    expect(comebackCooldownElapsed("2026-05-07", "2026-05-13")).toBe(false); // 6
    expect(comebackCooldownElapsed("2026-05-06", "2026-05-13")).toBe(true); // 7
    // Cruza fin de mes: en 2028 (bisiesto) existe el 29/2, en 2027 no.
    expect(comebackCooldownElapsed("2028-02-23", "2028-03-01")).toBe(true); // 7 días
    expect(comebackCooldownElapsed("2027-02-23", "2027-03-01")).toBe(false); // 6 días
    expect(daysBetweenDateKeys("2028-02-23", "2028-03-01")).toBe(7);
    expect(daysBetweenDateKeys("2027-02-23", "2027-03-01")).toBe(6);
    // Un valor que no es una fecha no bloquea (y no tira).
    expect(comebackCooldownElapsed("mañana", "2026-05-13")).toBe(true);
    expect(comebackCooldownElapsed(42, "2026-05-13")).toBe(true);
    expect(daysBetweenDateKeys("x", "2026-05-13")).toBeNull();
  });
});

describe("prioridad", () => {
  it("racha en riesgo gana sobre comeback cuando califica para los dos", async () => {
    // Última sesión el viernes (5 días): comeback elegible. Y la racha de 2
    // semanas está en riesgo. Sale un solo push, el de racha.
    createFake(seed(atRiskAthlete("u1", 5, 2, { lastTrainedFriday: true })));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(lastCall().kind).toBe("streak-at-risk");
    expect(result.notifiedStreakAtRisk).toBe(1);
    expect(result.notifiedComeback).toBe(0);
  });

  it("si la racha es candidata pero NO se confirma, cae al comeback", async () => {
    // Plan de 6 días: la semana anterior (6 sesiones, la última el viernes)
    // pasa el filtro barato, pero el objetivo real es 6 y faltan 6 con 5 días
    // por delante: no está en riesgo. Su último entreno fue hace 5 días: comeback.
    createFake(seed(
      [user("u1"), assignedPlan("p", "u1", 6)],
      [0, 1, 2, 3, 4, 4].map((d, i) =>
        sessionAt("u1", `2026-05-0${4 + d}T12:0${i}:00`)),
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(result.skippedNotAtRisk).toBe(0);
    expect(result.notifiedComeback).toBe(1);
    expect(lastCall().kind).toBe("comeback-reminder");
  });

  it("máximo UN push por atleta por día aunque tenga muchas sesiones", async () => {
    createFake(seed(
      [user("u1")],
      [
        sessionAt("u1", "2026-05-04T12:00:00"),
        sessionAt("u1", "2026-05-05T12:00:00"),
        sessionAt("u1", "2026-05-06T12:00:00"),
      ],
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  });
});

// ─── Opt-out, rol, idempotencia, fallas ───────────────────────────────────────

describe("opt-out", () => {
  const comebackAthlete = (prefs?: Doc) => seed(
    [user("u1", prefs ? { notificationPrefs: prefs } : {})],
    [sessionAt("u1", "2026-05-09T12:00:00")],
  );

  it("push === false: no reserva, no envía y no toca el doc", async () => {
    const fake = createFake(comebackAthlete({ [DAILY_REMINDERS_PREF_KEY]: { push: false } }));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(result.skippedOptedOut).toBe(1);
    expect(fake.user("u1").lastDailyReminderDate).toBeUndefined();
    expect(fake.user("u1").lastComebackReminderDate).toBeUndefined();
  });

  it("el opt-out también frena la racha en riesgo, sin gastar lecturas de rutinas", async () => {
    const fake = createFake(seed(
      atRiskAthlete("u1", 5, 2),
      [["users/u1", { role: "athlete", notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } } }]],
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    // Cortó con la lectura previa del usuario, antes de pedir las rutinas.
    expect(fake.queryLog.some((q) => q.scope === "routines")).toBe(false);
  });

  it.each([
    ["sin notificationPrefs", undefined],
    ["la fila existe sin `push`", { [DAILY_REMINDERS_PREF_KEY]: {} }],
    ["push: true", { [DAILY_REMINDERS_PREF_KEY]: { push: true } }],
    ["apagó OTRA fila", { novedades_plan: { push: false } }],
    ["sólo el canal de mail apagado", { [DAILY_REMINDERS_PREF_KEY]: { email: false } }],
  ])("una preferencia ausente cuenta como encendida: %s", async (_name, prefs) => {
    createFake(comebackAthlete(prefs));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  });

  it("si apaga el push MIENTRAS corre el job, la transacción lo respeta", async () => {
    // La corrida es secuencial y puede tardar minutos: entre la lectura previa y
    // la reserva el atleta puede entrar a Privacidad y apagar el interruptor.
    const fake = createFake(comebackAthlete());
    fake.hooks.beforeTransaction = () => {
      fake.docs.set("users/u1", {
        role: "athlete",
        notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
      });
    };

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(result.skippedOptedOut).toBe(1);
    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
  });

  describe("con el sendFcm REAL, para ver el historial", () => {
    // `sendFcm` con la preferencia apagada frena el banner pero SÍ escribe la
    // entrada de `users/{uid}/notifications`. De eso depende que el handler corte
    // ANTES de llamarlo: si esto deja de ser cierto, el corte sobra (y este test
    // avisa); si el corte se saca, el segundo test se pone rojo.
    const real = (
      jest.requireActual("../notifications/send-fcm") as { sendFcm: typeof sendFcm }
    ).sendFcm;
    const multicast = jest.fn(async (m: { tokens: string[] }) => ({
      successCount: m.tokens.length,
      failureCount: 0,
      responses: m.tokens.map(() => ({ success: true })),
    }));
    const realMessaging = { sendEachForMulticast: multicast } as unknown as Messaging;

    beforeEach(() => {
      multicast.mockClear();
      mockedSendFcm.mockImplementation(real);
    });

    it("premisa: sendFcm con la pref apagada escribe historial pero no hace push", async () => {
      const fake = createFake(seed([
        "users/u1",
        { role: "athlete", fcmTokens: ["t1"], notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } } },
      ]));

      await real(
        app,
        {
          uids: ["u1"],
          kind: "comeback-reminder",
          notification: { title: "t", body: "b" },
          data: { deepLink: "/home" },
          prefKey: DAILY_REMINDERS_PREF_KEY,
        },
        realMessaging,
      );

      expect(fake.historyOf("u1")).toHaveLength(1);
      expect(multicast).not.toHaveBeenCalled();
    });

    it("el handler con la pref apagada NO deja una fila en la bandeja", async () => {
      const fake = createFake(seed(
        [["users/u1", {
          role: "athlete",
          fcmTokens: ["t1"],
          notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
        }]],
        [sessionAt("u1", "2026-05-09T12:00:00")],
      ));

      await notifyDailyRemindersHandler(app, WED, realMessaging);

      expect(fake.historyOf("u1")).toHaveLength(0);
      expect(multicast).not.toHaveBeenCalled();
    });

    it("y con la pref encendida deja UNA fila y manda el push con kind y deepLink", async () => {
      const fake = createFake(seed(
        [["users/u1", { role: "athlete", fcmTokens: ["t1", "t2"] }]],
        [sessionAt("u1", "2026-05-09T12:00:00")],
      ));

      await notifyDailyRemindersHandler(app, WED, realMessaging);

      expect(fake.historyOf("u1")).toEqual([
        expect.objectContaining({ kind: "comeback-reminder", deepLink: "/home" }),
      ]);
      expect(multicast).toHaveBeenCalledWith(expect.objectContaining({
        tokens: ["t1", "t2"],
        data: { deepLink: "/home", kind: "comeback-reminder" },
      }));
    });
  });
});

describe("rol", () => {
  it("no manda a quien no es atleta", async () => {
    const fake = createFake(seed(
      [["users/pf", { role: "trainer" }]],
      [sessionAt("pf", "2026-05-09T12:00:00")],
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(result.skippedNotAthlete).toBe(1);
    expect(fake.user("pf").lastDailyReminderDate).toBeUndefined();
  });

  it("un usuario borrado con sesiones huérfanas se saltea sin fallar", async () => {
    createFake(seed([sessionAt("fantasma", "2026-05-09T12:00:00")]));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(result.skippedNotAthlete).toBe(1);
    expect(result.failed).toBe(0);
  });
});

describe("idempotencia", () => {
  it("una segunda corrida el mismo día no vuelve a mandar", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2)));

    await notifyDailyRemindersHandler(app, WED, messaging);
    const second = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(second.notified).toBe(0);
    expect(second.skippedAlreadySent).toBe(1);
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
  });

  it("dos corridas SOLAPADAS mandan un solo push: la transacción es la autoridad", async () => {
    createFake(seed(atRiskAthlete("u1", 5, 2)));

    const [a, b] = await Promise.all([
      notifyDailyRemindersHandler(app, WED, messaging),
      notifyDailyRemindersHandler(app, WED, messaging),
    ]);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(a.notified + b.notified).toBe(1);
    expect(a.skippedAlreadySent + b.skippedAlreadySent).toBe(1);
  });

  it("al día siguiente vuelve a evaluar (el marcador es del día, no para siempre)", async () => {
    const fake = createFake(seed(
      [user("u1", { lastDailyReminderDate: "2026-05-12" })],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
  });

  it("el día lo marca la fecha ART: 00:30 ART y 23:30 ART del mismo día son lo mismo", async () => {
    const fake = createFake(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));

    await notifyDailyRemindersHandler(app, at("2026-05-13T00:30:00"), messaging);
    await notifyDailyRemindersHandler(app, at("2026-05-13T23:30:00"), messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
  });
});

describe("si el envío falla", () => {
  it("suelta la reserva y el reintento vuelve a mandar", async () => {
    const fake = createFake(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));

    const primera = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(primera.notified).toBe(0);
    expect(primera.failed).toBe(1);
    expect(errorLog).toHaveBeenCalledWith(
      "notifyDailyReminders: failed for athlete",
      expect.objectContaining({ uid: "u1", error: "FCM caído" }),
    );
    // Nunca había tenido marcadores: se borran, no quedan en null.
    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");

    const segunda = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(segunda.notified).toBe(1);
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
  });

  it("restaura los valores PREVIOS, no los borra", async () => {
    const fake = createFake(seed(
      [user("u1", {
        lastDailyReminderDate: "2026-05-12",
        lastComebackReminderDate: "2026-05-05",
      })],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-12");
    expect(fake.user("u1").lastComebackReminderDate).toBe("2026-05-05");
  });

  it("en la racha restaura sólo el marcador diario y no inventa el del comeback", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2)));
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));

    await notifyDailyRemindersHandler(app, WED, messaging);

    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
  });

  it("un atleta que falla no frena a los demás", async () => {
    createFake(seed(
      [user("a")], [sessionAt("a", "2026-05-09T12:00:00")],
      [user("b")], [sessionAt("b", "2026-05-09T12:00:00")],
    ));
    // El primero en enviar falla, sea quien sea; el otro tiene que salir igual.
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(result.failed).toBe(1);
    expect(result.notified).toBe(1);
  });
});

describe("escaneo", () => {
  it("pagina la collectionGroup query", async () => {
    const abandoned: Entries = Array.from({ length: 500 }, (_, i) => sessionAt(
      `ab-${i}`,
      `2026-04-${String((i % 28) + 1).padStart(2, "0")}T12:00:00`,
      { wasFullyCompleted: false },
    ));
    const fake = createFake(seed(
      abandoned,
      [user("pagina-dos")],
      [sessionAt("pagina-dos", "2026-05-09T20:00:00")],
    ));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(result.scannedSessions).toBe(501);
    expect(result.notified).toBe(1);
    expect(fake.queryLog.filter((q) => q.scope === "group:sessions")).toHaveLength(2);
  });

  it("no suma al contador las sesiones del futuro: la query corta en `now`", async () => {
    createFake(seed([user("u1")], [sessionAt("u1", "2026-05-14T12:00:00")]));

    const result = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(result.scannedSessions).toBe(0);
  });

  it("candidates = notified + skipped + failed", async () => {
    createFake(seed(
      [user("ok")], [sessionAt("ok", "2026-05-09T12:00:00")],
      [user("off", { notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } } })],
      [sessionAt("off", "2026-05-09T12:00:00")],
      [user("ya", { lastDailyReminderDate: "2026-05-13" })], [sessionAt("ya", "2026-05-09T12:00:00")],
      [["users/pf", { role: "trainer" }]], [sessionAt("pf", "2026-05-09T12:00:00")],
      [user("falla")], [sessionAt("falla", "2026-05-09T12:00:00")],
    ));
    mockedSendFcm.mockImplementation(async (_app, input) => {
      if (input.uids[0] === "falla") throw new Error("FCM caído");
      return { successCount: 1, failureCount: 0 };
    });

    const r = await notifyDailyRemindersHandler(app, WED, messaging);

    expect(r).toMatchObject({
      candidates: 5,
      notified: 1,
      skipped: 3,
      failed: 1,
      skippedOptedOut: 1,
      skippedAlreadySent: 1,
      skippedNotAthlete: 1,
    });
    expect(r.candidates).toBe(r.notified + r.skipped + r.failed);
  });
});

// ─── Copy ─────────────────────────────────────────────────────────────────────

describe("copy", () => {
  it.each([
    [1, 1, "Te faltan 1 entrenamiento esta semana para sostener tu racha de 1 semana."],
    [1, 2, "Te faltan 1 entrenamiento esta semana para sostener tu racha de 2 semanas."],
    [2, 1, "Te faltan 2 entrenamientos esta semana para sostener tu racha de 1 semana."],
    [7, 12, "Te faltan 7 entrenamientos esta semana para sostener tu racha de 12 semanas."],
  ])("streakAtRiskCopy(%i, %i)", (missing, weeks, body) => {
    expect(streakAtRiskCopy(missing, weeks)).toEqual({ title: "Hoy o se corta 🔥", body });
  });

  it("comebackCopy", () => {
    expect(comebackCopy(4)).toEqual({
      title: "Te extrañamos en el gym 💪",
      body: "Hace 4 días que no entrenás. ¿Arrancamos hoy?",
    });
  });
});
