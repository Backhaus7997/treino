/**
 * Unit tests for the daily reminders: the 06:00 PLANNER (notifyDailyReminders)
 * and the every-15-minutes DISPATCHER (dispatchDailyReminders). No emulator or
 * real FCM.
 */

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
import { artDateKey } from "../mail/format";
import { SendFcmInput, sendFcm } from "../notifications/send-fcm";
import { dobleNamespaced } from "./helpers/modular-from-namespaced";
import {
  MAX_SEND_ATTEMPTS,
  dispatchDailyReminders,
  dispatchDailyRemindersHandler,
  parseDailyReminderPlan,
} from "../notifications/dispatch-daily-reminders";
import {
  COMEBACK_COOLDOWN_DAYS,
  COMEBACK_MAX_DAYS,
  DAILY_REMINDERS_PREF_KEY,
  comebackCooldownElapsed,
  comebackCopy,
  daysBetweenDateKeys,
  notifyDailyReminders,
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
  /** Cuántos documentos devolvió: lo que Firestore cobraría como lecturas. */
  returned: number;
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

/** `a.b` lee el campo `b` del mapa `a`, como los filtros de Firestore sobre mapas. */
function fieldOf(doc: Doc, field: string): unknown {
  return field.split(".").reduce<unknown>(
    (current, key) => (current as Doc | undefined)?.[key],
    doc,
  );
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
  const hooks: {
    beforeTransaction?: () => void;
    /** Se ejecuta antes de cada `ref.update` (no de las de una transacción). */
    beforeUpdate?: (path: string, data: Doc) => void;
  } = {};
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
      update: async (data: Doc) => {
        hooks.beforeUpdate?.(path, data);
        applyUpdate(path, data);
      },
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
        const logEntry: QueryLogEntry = {
          scope: scopeLabel,
          fields: [
            ...state.filters.map(([f, op, v]) => `${f}${op}${describeValue(v)}`),
            ...(state.order ? [`orderBy ${state.order[0]} ${state.order[1]}`] : []),
          ],
          returned: 0,
        };
        queryLog.push(logEntry);

        let paths = [...docs.keys()].filter((p) =>
          state.scope.kind === "collection" ?
            parentOf(p) === state.scope.path :
            idOf(parentOf(p)) === state.scope.name);

        paths = paths.filter((p) => {
          const doc = docs.get(p) as Doc;
          return state.filters.every(([field, op, expected]) => {
            if (fieldOf(doc, field) === undefined) return false;
            const a = comparable(fieldOf(doc, field)) as number | string;
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
          paths = paths.filter((p) => fieldOf(docs.get(p) as Doc, field) !== undefined);
          paths.sort((p, q) => {
            const a = comparable(fieldOf(docs.get(p) as Doc, field)) as number;
            const b = comparable(fieldOf(docs.get(q) as Doc, field)) as number;
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
        logEntry.returned = snaps.length;
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

// Miércoles 2026-05-13, 06:00 ART: la hora a la que corre el planificador. Quedan
// 5 días de la semana contando hoy (mié, jue, vie, sáb, dom). Semana en curso:
// lunes 2026-05-11.
const WED = at("2026-05-13T06:00:00");
// Jueves 2026-05-14: quedan 4 días.
const THU = at("2026-05-14T06:00:00");
// Domingo 2026-05-17: queda 1 día.
const SUN = at("2026-05-17T06:00:00");

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

const MIN = 60_000;

/** 23:45 ART del día de [planAt]: pasado el último horario posible de envío (22:30). */
const endOfDay = (planAt: Date): Date => at(`${artDateKey(planAt)}T23:45:00`);

/**
 * Un día "de un paso": el planificador a la hora [planAt] y UN despacho al final
 * del día, cuando ya venció cualquier plan. Es lo que hace falta cuando el test
 * es sobre QUÉ se manda y no sobre CUÁNDO.
 */
async function runDay(planAt: Date, withMessaging: Messaging = messaging) {
  const planner = await notifyDailyRemindersHandler(app, planAt);
  const dispatch = await dispatchDailyRemindersHandler(app, endOfDay(planAt), withMessaging);
  return { planner, dispatch };
}

/**
 * Un día CON RELOJ: el planificador a [planAt] y un tick del despachante cada 15
 * minutos desde ahí hasta las 23:45, como lo corre el scheduler. Devuelve los
 * resultados de los ticks que encontraron planes.
 */
async function playDay(planAt: Date) {
  const planner = await notifyDailyRemindersHandler(app, planAt);
  const ticks: Array<Awaited<ReturnType<typeof dispatchDailyRemindersHandler>>> = [];
  for (let t = planAt.getTime(); t <= endOfDay(planAt).getTime(); t += 15 * MIN) {
    ticks.push(await dispatchDailyRemindersHandler(app, new Date(t), messaging));
  }
  return { planner, ticks };
}

/** El texto del push de racha de [missing] entrenamientos, para no repetirlo. */
const streakBody = (missing: number, weeks: number): string =>
  streakAtRiskCopy(missing, weeks).body;

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

// ─── Builders del plan ────────────────────────────────────────────────────────

/** Los inicios de sesión de una racha de 1 semana (4 sesiones, del 4 al 10 de mayo). */
const EVENING = ["17:40", "18:12", "18:15", "18:05"]; // horario habitual ~18:08

/**
 * Un atleta con un plan de [clocks.length] días que cumplió la semana del 4 al
 * 10 de mayo entrenando a las [clocks], con la última sesión el domingo 10. Un
 * JUEVES (THU) faltan 4 y quedan 4 días: está en riesgo si y sólo si son 4
 * sesiones. También está a 4 días de su última sesión, o sea que califica para el
 * comeback: es el caso de «gana la racha».
 */
function weekAthlete(uid: string, clocks: string[], over: Doc = {}): Entries {
  const n = clocks.length;
  const out: Entries = [user(uid, over), assignedPlan(`plan-${uid}`, uid, n)];
  clocks.forEach((clock, i) => {
    const day = Math.round(4 + (6 * i) / (n - 1)); // 4..10
    out.push(sessionAt(uid, `2026-05-${String(day).padStart(2, "0")}T${clock}:00`));
  });
  return out;
}

/**
 * Un atleta que dejó de entrenar: sus sesiones fueron a las [clocks], la última
 * el sábado 9 de mayo (a 4 días de un miércoles) y las otras del 4 al 7. Con 4
 * sesiones la semana anterior no alcanza para la racha de un miércoles, así que
 * sólo califica para el comeback.
 */
function lapsedAthlete(uid: string, clocks: string[], over: Doc = {}): Entries {
  const n = clocks.length;
  const out: Entries = [user(uid, over)];
  clocks.forEach((clock, i) => {
    const day = i === n - 1 ? 9 : 4 + i;
    out.push(sessionAt(uid, `2026-05-0${day}T${clock}:00`));
  });
  return out;
}

const hm = (clock: string): number => {
  const [h, m] = clock.split(":").map(Number);
  return h * 60 + m;
};

/** La hora de pared ART de [date] como "HH:MM". */
const clockOf = (date: Date): string => new Date(date.getTime() - 3 * 60 * MIN).toISOString().slice(11, 16);

// ─── Racha en riesgo ──────────────────────────────────────────────────────────

describe("streak-at-risk", () => {
  it("se planifica a la mañana y sale del despachante: faltan EXACTAMENTE tantos como días quedan", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2)));

    const { planner, dispatch } = await runDay(WED);

    expect(planner.plannedStreakAtRisk).toBe(1);
    expect(dispatch.notified).toBe(1);
    expect(dispatch.notifiedStreakAtRisk).toBe(1);
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

    const { planner } = await runDay(WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(planner.candidates).toBe(0);
  });

  it("no dispara si ya es imposible (faltan MÁS de los que quedan)", async () => {
    // Objetivo 7 con una sesión el martes: faltan 6 y quedan 5. Aunque entrene
    // todos los días que quedan, no llega: la racha ya está perdida y avisarlo
    // sería ruido.
    const fake = createFake(seed(
      atRiskAthlete("u1", 7, 2),
      [sessionAt("u1", "2026-05-12T12:00:00")],
    ));

    const { planner } = await runDay(WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    // Sí fue candidato (la semana anterior alcanza), pero el objetivo REAL lo descarta.
    expect(planner.candidates).toBe(1);
    expect(planner.skippedNotAtRisk).toBe(1);
    expect(fake.user("u1").lastDailyReminderDate).toBeUndefined();
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
  });

  it("dispara con una sesión ya hecha esta semana si el cálculo da justo", async () => {
    // Objetivo 6, una sesión el martes: faltan 5 y quedan 5. "Racha de 1 semana".
    createFake(seed(
      atRiskAthlete("u1", 6, 1),
      [sessionAt("u1", "2026-05-12T12:00:00")],
    ));

    await runDay(WED);

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

    const { planner } = await runDay(WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(planner.candidates).toBe(0);
  });

  it("EXCLUYE a quien ya completó una sesión HOY (fecha ART)", async () => {
    // Mismo atleta, mismo objetivo: ayer entrenó → dispara; hoy entrenó (antes de
    // que corra el planificador) → no.
    createFake(seed(
      atRiskAthlete("ayer", 6, 1),
      [sessionAt("ayer", "2026-05-12T12:00:00")],
      atRiskAthlete("hoy", 6, 1),
      [sessionAt("hoy", "2026-05-13T05:00:00")],
    ));

    const { dispatch } = await runDay(WED);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(lastCall()).toMatchObject({ kind: "streak-at-risk" });
    expect(mockedSendFcm.mock.calls[0][1].uids).toEqual(["ayer"]);
    expect(dispatch.notified).toBe(1);
  });

  it("'hoy' es el día ART: una sesión de las 23:30 de ayer NO cuenta como hoy", async () => {
    // 23:30 ART del martes es la 02:30 UTC del miércoles. Con día UTC esto
    // excluiría al atleta por error, en el planificador y en el despachante.
    createFake(seed(
      atRiskAthlete("u1", 6, 1),
      [sessionAt("u1", "2026-05-12T23:30:00")],
    ));

    await runDay(WED);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  });

  it("singular: 'Te falta 1 entrenamiento… racha de 1 semana' un domingo", async () => {
    // Domingo: queda 1 día. Objetivo 3, dos sesiones esta semana → falta 1.
    createFake(seed(
      [user("u1"), assignedPlan("p", "u1", 3)],
      weekEndingSunday("u1", "2026-05-04", 3),
      [sessionAt("u1", "2026-05-11T12:00:00"), sessionAt("u1", "2026-05-12T12:00:00")],
    ));

    await runDay(SUN);

    expect(lastCall().notification).toEqual({
      title: "Hoy o se corta 🔥",
      body: "Te falta 1 entrenamiento esta semana para sostener tu racha de 1 semana.",
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

    await runDay(WED);

    expect(lastCall().notification.body).toContain("racha de 12 semanas");
    // Y la extensión pidió las sesiones DE ESE USUARIO, anteriores a la ventana.
    const extension = fake.queryLog.filter(
      (q) => q.scope === "users/u1/sessions" && q.fields[0].startsWith("startedAt<"),
    );
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

    await runDay(WED);

    expect(lastCall().notification.body).toContain("racha de 108 semanas");
    expect(
      fake.queryLog.filter(
        (q) => q.scope === "users/u1/sessions" && q.fields[0].startsWith("startedAt<"),
      ).length,
    ).toBeGreaterThan(1);
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

    await runDay(WED);

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

    await runDay(WED);

    // Objetivo 1 (nada visible): faltan 1 y quedan 5. No se manda.
    expect(mockedSendFcm).not.toHaveBeenCalled();
  });

  it("lee las rutinas con las mismas queries que el cliente", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 1)));

    await runDay(WED);

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
      [sessionAt("u1", "2026-05-13T05:00:00")],
    ));

    await runDay(WED);

    expect(fake.queryLog.some((q) => q.scope === "routines")).toBe(false);
  });

  it("el despachante NO lee rutinas ni la ventana de sesiones: sólo planes y sesiones de hoy", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2)));
    await notifyDailyRemindersHandler(app, WED);
    fake.queryLog.length = 0;

    await dispatchDailyRemindersHandler(app, endOfDay(WED), messaging);

    expect(fake.queryLog.map((q) => q.scope)).toEqual(["users", "users/u1/sessions"]);
  });
});

// ─── El plan que escribe el planificador ──────────────────────────────────────

describe("el planificador (06:00): escribe el plan, no manda nada", () => {
  it("racha: guarda fecha, tipo, hora y los datos del texto; no hay push ni marcadores", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2)));

    const result = await notifyDailyRemindersHandler(app, WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(result).toMatchObject({ planned: 1, plannedStreakAtRisk: 1, plannedComeback: 0 });
    // 10 sesiones a las 12:00: horario habitual 12:00, el aviso a las 13:00.
    expect(fake.user("u1").dailyReminderPlan).toEqual({
      date: "2026-05-13",
      kind: "streak-at-risk",
      sendAtMinute: 780,
      missing: 5,
      streakWeeks: 2,
    });
    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
  });

  it("racha: sale 60 minutos DESPUÉS del horario habitual aprendido (~18:08 → 19:08)", async () => {
    const fake = createFake(seed(weekAthlete("u1", EVENING)));

    await notifyDailyRemindersHandler(app, THU);

    expect(fake.user("u1").dailyReminderPlan).toEqual({
      date: "2026-05-14",
      kind: "streak-at-risk",
      sendAtMinute: hm("19:08"),
      missing: 4,
      streakWeeks: 1,
    });
  });

  it("racha: sin patrón claro sale a las 18:00", async () => {
    // Cuatro sesiones separadas por tres horas: ninguna ventana de una hora junta 4.
    const fake = createFake(seed(weekAthlete("sinpatron", ["07:00", "10:00", "13:00", "16:00"])));

    await notifyDailyRemindersHandler(app, THU);

    expect(fake.user("sinpatron").dailyReminderPlan).toMatchObject({
      kind: "streak-at-risk",
      sendAtMinute: 1080,
    });
  });

  it("racha: el piso es 08:00 aunque entrene a las 06:00", async () => {
    // Habitual ~06:15 → 07:15, que queda antes del piso.
    const fake = createFake(seed(weekAthlete("madrugador", ["06:00", "06:10", "06:20", "06:30"])));

    await notifyDailyRemindersHandler(app, THU);

    expect(fake.user("madrugador").dailyReminderPlan).toMatchObject({ sendAtMinute: 480 });
  });

  it("racha: el techo es 22:30 aunque entrene a las 22:00", async () => {
    const fake = createFake(seed(weekAthlete("nocturno", ["21:50", "22:00", "22:10", "22:20"])));

    await notifyDailyRemindersHandler(app, THU);

    expect(fake.user("nocturno").dailyReminderPlan).toMatchObject({ sendAtMinute: 1350 });
  });

  it("si califica a los dos, el plan es el de racha y NO se planifica el comeback", async () => {
    // Jueves: la última sesión fue el domingo (4 días) y la racha está en riesgo.
    const fake = createFake(seed(weekAthlete("u1", EVENING)));

    const result = await notifyDailyRemindersHandler(app, THU);

    expect(result).toMatchObject({ plannedStreakAtRisk: 1, plannedComeback: 0 });
    expect(fake.user("u1").dailyReminderPlan).toMatchObject({ kind: "streak-at-risk" });
    // Ni el cooldown del comeback corre.
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
  });

  it("y ese día sólo sale el push de racha, a la hora planificada", async () => {
    createFake(seed(weekAthlete("u1", EVENING)));

    await runDay(THU);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(lastCall().kind).toBe("streak-at-risk");
  });

  it("el opt-out no deja plan", async () => {
    const fake = createFake(seed(weekAthlete("u1", EVENING, {
      notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
    })));

    const result = await notifyDailyRemindersHandler(app, THU);

    expect(result.skippedOptedOut).toBe(1);
    expect(result.planned).toBe(0);
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
  });

  it("si ya se le mandó hoy (lastDailyReminderDate de hoy) no deja plan", async () => {
    const fake = createFake(seed(weekAthlete("u1", EVENING, {
      lastDailyReminderDate: "2026-05-14",
    })));

    const result = await notifyDailyRemindersHandler(app, THU);

    expect(result.skippedAlreadySent).toBe(1);
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
  });

  it("un lastDailyReminderDate de AYER no impide planificar", async () => {
    const fake = createFake(seed(weekAthlete("u1", EVENING, {
      lastDailyReminderDate: "2026-05-13",
    })));

    await notifyDailyRemindersHandler(app, THU);

    expect(fake.user("u1")).toHaveProperty("dailyReminderPlan");
  });

  it("correrlo dos veces el mismo día reescribe el MISMO plan", async () => {
    const fake = createFake(seed(weekAthlete("u1", EVENING)));

    await notifyDailyRemindersHandler(app, THU);
    const first = fake.user("u1").dailyReminderPlan;
    await notifyDailyRemindersHandler(app, THU);

    expect(fake.user("u1").dailyReminderPlan).toEqual(first);
    expect(mockedSendFcm).not.toHaveBeenCalled();
  });

  it("no le escribe un plan a quien no es atleta", async () => {
    const fake = createFake(seed(
      [["users/pf", { role: "trainer" }]],
      [sessionAt("pf", "2026-05-09T12:00:00")],
    ));

    await notifyDailyRemindersHandler(app, WED);

    expect(fake.user("pf")).not.toHaveProperty("dailyReminderPlan");
  });

  it("un atleta cuyo plan no se puede escribir falla solo y no frena a los demás", async () => {
    const fake = createFake(seed(
      [user("a")], [sessionAt("a", "2026-05-09T12:00:00")],
      [user("b")], [sessionAt("b", "2026-05-09T12:00:00")],
    ));
    fake.hooks.beforeUpdate = (path) => {
      if (path === "users/a") throw new Error("escritura rechazada");
    };

    const result = await notifyDailyRemindersHandler(app, WED);

    expect(result).toMatchObject({ failed: 1, planned: 1, candidates: 2 });
    expect(errorLog).toHaveBeenCalledWith(
      "notifyDailyReminders: failed for athlete",
      expect.objectContaining({ uid: "a", error: "escritura rechazada" }),
    );
    expect(fake.user("b")).toHaveProperty("dailyReminderPlan");
  });
});

describe("los schedules", () => {
  const trigger = (fn: unknown) =>
    (fn as { __endpoint: { scheduleTrigger: Record<string, unknown>; region: string[] } })
      .__endpoint;

  it("el planificador corre a las 06:00 ART", () => {
    expect(trigger(notifyDailyReminders).scheduleTrigger).toMatchObject({
      schedule: "0 6 * * *",
      timeZone: "America/Argentina/Buenos_Aires",
    });
    expect(trigger(notifyDailyReminders).region).toEqual(["southamerica-east1"]);
  });

  it("el despachante corre cada 15 minutos, en ART y en la misma región", () => {
    expect(trigger(dispatchDailyReminders).scheduleTrigger).toMatchObject({
      schedule: "*/15 * * * *",
      timeZone: "America/Argentina/Buenos_Aires",
    });
    expect(trigger(dispatchDailyReminders).region).toEqual(["southamerica-east1"]);
  });
});

// ─── Volvé a entrenar ─────────────────────────────────────────────────────────

/**
 * Planifica a [planAt] y corre el reloj tick a tick (cada 15 minutos hasta las
 * 23:45): devuelve a qué hora de pared ART salió cada push. Es la forma de medir
 * CUÁNDO sale algo, que es lo que `runDay` no mira.
 */
async function sendTimes(planAt: Date): Promise<string[]> {
  await notifyDailyRemindersHandler(app, planAt);
  const times: string[] = [];
  for (let t = planAt.getTime(); t <= endOfDay(planAt).getTime(); t += 15 * MIN) {
    const before = mockedSendFcm.mock.calls.length;
    await dispatchDailyRemindersHandler(app, new Date(t), messaging);
    if (mockedSendFcm.mock.calls.length > before) times.push(clockOf(new Date(t)));
  }
  return times;
}

describe("comeback-reminder", () => {
  it("se planifica a los 4 días ART, sale del despachante y escribe los dos marcadores", async () => {
    const fake = createFake(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")], // sábado: 4 días antes del miércoles
    ));

    const { planner, dispatch } = await runDay(WED);

    expect(planner.plannedComeback).toBe(1);
    expect(dispatch.notifiedComeback).toBe(1);
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

    const { planner } = await runDay(WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(planner.candidates).toBe(0);
  });

  it("cuenta DÍAS CALENDARIO ART, no horas corridas", async () => {
    // Sábado 23:30 ART → miércoles 06:00 ART son 78,5 horas (menos de 96) pero
    // 4 días calendario: dispara. Domingo 00:30 ART son 3 días: no.
    createFake(seed(
      [user("tarde")], [sessionAt("tarde", "2026-05-09T23:30:00")],
      [user("temprano")], [sessionAt("temprano", "2026-05-10T00:30:00")],
    ));

    await runDay(WED);

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

    await runDay(WED);

    expect(lastCall().notification.body).toBe("Hace 6 días que no entrenás. ¿Arrancamos hoy?");
  });

  it("el escaneo ve exactamente la ventana de 8 semanas + la actual", async () => {
    // La ventana arranca el lunes 2026-03-16 00:00 ART (03:00 UTC), inclusive.
    // Ninguno de los dos recibe push: 58 días sin entrenar ya pasó el tope del
    // comeback. Lo que se mide acá es qué entra al escaneo.
    const fake = createFake(seed(
      [user("dentro")], [sessionAt("dentro", "2026-03-16T00:00:00")],
      [user("fuera")], [sessionAt("fuera", "2026-03-15T23:59:00")],
    ));

    const { planner } = await runDay(WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(planner.athletesWithSessions).toBe(1);
    // Y la query pidió exactamente esa ventana (el planificador corre a las 06:00 ART).
    expect(fake.queryLog[0].fields.slice(0, 2)).toEqual([
      "startedAt>=2026-03-16T03:00:00.000Z",
      "startedAt<2026-05-13T09:00:00.000Z",
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

    const { planner } = await runDay(WED);

    expect(planner.athletesWithSessions).toBe(0);
    expect(mockedSendFcm).not.toHaveBeenCalled();
  });

  describe("sale a la hora habitual del atleta", () => {
    it("planificado a la hora a la que suele entrenar (~18:08), sin offset", async () => {
      const fake = createFake(seed(lapsedAthlete("u1", EVENING)));

      const result = await notifyDailyRemindersHandler(app, WED);

      expect(result).toMatchObject({ plannedComeback: 1, plannedStreakAtRisk: 0 });
      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(fake.user("u1").dailyReminderPlan).toEqual({
        date: "2026-05-13",
        kind: "comeback-reminder",
        sendAtMinute: hm("18:08"),
        daysSince: 4,
      });
    });

    it("y sale en el primer tick a partir de esa hora: el de las 18:15", async () => {
      createFake(seed(lapsedAthlete("u1", EVENING)));

      // A las 18:00 (1080) todavía no es 18:08 (1088); a las 18:15 sí.
      expect(await sendTimes(WED)).toEqual(["18:15"]);
    });

    it("sin patrón claro (una sola sesión) sale a las 09:00", async () => {
      const fake = createFake(seed(lapsedAthlete("u1", ["12:00"])));

      expect(await sendTimes(WED)).toEqual(["09:00"]);
      expect(fake.user("u1").lastComebackReminderDate).toBe("2026-05-13");
    });

    it("el plan sin patrón dice 09:00 (540) y no antes", async () => {
      const fake = createFake(seed(lapsedAthlete("u1", ["12:00"])));

      await notifyDailyRemindersHandler(app, WED);

      expect(fake.user("u1").dailyReminderPlan).toMatchObject({ sendAtMinute: 540 });
    });

    it("el piso es 08:00: quien entrena a las 06:15 lo recibe a las 08:00", async () => {
      const fake = createFake(seed(lapsedAthlete("u1", ["06:00", "06:10", "06:20", "06:30"])));

      await notifyDailyRemindersHandler(app, WED);
      expect(fake.user("u1").dailyReminderPlan).toMatchObject({ sendAtMinute: 480 });

      expect(await sendTimes(WED)).toEqual(["08:00"]);
    });

    it("el techo es 22:30: quien entrena a las 22:47 lo recibe a las 22:30", async () => {
      const fake = createFake(seed(lapsedAthlete("u1", ["22:40", "22:45", "22:50", "22:55"])));

      await notifyDailyRemindersHandler(app, WED);
      expect(fake.user("u1").dailyReminderPlan).toMatchObject({ sendAtMinute: 1350 });

      expect(await sendTimes(WED)).toEqual(["22:30"]);
    });

    it("NO se manda si el atleta entrenó hoy antes del tick: ya volvió", async () => {
      // Una sesión TERMINADA hoy a las 10:00, o sea después de la planificación de
      // las 06:00 y antes del tick de las 18:15.
      const fake = createFake(seed(
        lapsedAthlete("u1", EVENING),
        [sessionAt("u1", "2026-05-13T10:00:00")],
      ));

      expect(await sendTimes(WED)).toEqual([]);
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
      // Y no gastó nada del tope: ni el marcador del día ni el del comeback.
      expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
      expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
    });
  });
});

describe("tope del comeback-reminder: día 4 y día 11, después silencio", () => {
  const DAY = 24 * 60 * 60 * 1000;

  /**
   * Corre el sistema entero un día por vez, `fromDay`..`toDay` días después del
   * 9/5: el planificador a las 06:00 y un tick del despachante cada 15 minutos
   * hasta las 23:45. La última sesión es el sábado 9/5; WED (13/5) es el día 4.
   */
  const runDays = async (fromDay: number, toDay: number, entries?: Entries) => {
    createFake(seed(entries ?? [user("u1"), sessionAt("u1", "2026-05-09T12:00:00")]));
    for (let d = fromDay; d <= toDay; d++) {
      await playDay(new Date(WED.getTime() + (d - 4) * DAY));
    }
    // Sólo los comeback: el tope es de ESE tipo. La racha en riesgo es otro
    // aviso y puede aparecer en el medio (ver el test de convivencia).
    return mockedSendFcm.mock.calls
      .filter((c) => c[1].kind === "comeback-reminder")
      .map((c) => c[1].notification.body);
  };

  it("COMEBACK_MAX_DAYS es 17", () => {
    expect(COMEBACK_MAX_DAYS).toBe(17);
  });

  it("con el reloj avanzando del día 4 al 30, llegan exactamente dos: día 4 y día 11", async () => {
    expect(await runDays(4, 30)).toEqual([
      "Hace 4 días que no entrenás. ¿Arrancamos hoy?",
      "Hace 11 días que no entrenás. ¿Arrancamos hoy?",
    ]);
  });

  it("si el primero sale tarde (día 6), siguen siendo dos como mucho: 6 y 13", async () => {
    expect(await runDays(6, 30)).toEqual([
      "Hace 6 días que no entrenás. ¿Arrancamos hoy?",
      "Hace 13 días que no entrenás. ¿Arrancamos hoy?",
    ]);
  });

  it("con horario habitual aprendido (18:08) también son dos: día 4 y día 11", async () => {
    expect(await runDays(4, 30, lapsedAthlete("u1", EVENING))).toEqual([
      "Hace 4 días que no entrenás. ¿Arrancamos hoy?",
      "Hace 11 días que no entrenás. ¿Arrancamos hoy?",
    ]);
  });

  it("convive con la racha: el domingo de la semana sin entrenar llega la racha en riesgo", async () => {
    // Entrenó el sábado 9/5: cumplió esa semana (sin rutina, objetivo 1) y
    // tiene racha de 1. El domingo 17/5 (día 8) es su última chance de
    // sostenerla. En total, del día 4 al 30: volvé (4), racha (8), volvé (11).
    await runDays(4, 30);
    expect(mockedSendFcm.mock.calls.map((c) => [c[1].kind, c[1].notification.body])).toEqual([
      ["comeback-reminder", "Hace 4 días que no entrenás. ¿Arrancamos hoy?"],
      ["streak-at-risk", "Te falta 1 entrenamiento esta semana para sostener tu racha de 1 semana."],
      ["comeback-reminder", "Hace 11 días que no entrenás. ¿Arrancamos hoy?"],
    ]);
  });

  it("día 17 todavía dispara, día 18 ya no (y no cuesta lecturas)", async () => {
    createFake(seed(
      [user("d17")], [sessionAt("d17", "2026-04-26T12:00:00")],
      [user("d18")], [sessionAt("d18", "2026-04-25T12:00:00")],
    ));

    const { planner } = await runDay(WED);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(mockedSendFcm.mock.calls[0][1].uids).toEqual(["d17"]);
    expect(planner.candidates).toBe(1);
  });

  it("al volver a entrenar, la cuenta arranca de nuevo", async () => {
    // Ya recibió sus dos avisos de la inactividad anterior (el último hace 8
    // días); entrenó el sábado 9/5 y hoy, día 4, vuelve a calificar.
    createFake(seed(
      [user("u1", { lastComebackReminderDate: "2026-05-05" })],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));

    await runDay(WED);

    expect(lastCall().notification.body).toBe("Hace 4 días que no entrenás. ¿Arrancamos hoy?");
  });
});

describe("cooldown de 7 días del comeback-reminder", () => {
  const run = async (lastComebackReminderDate?: string) => {
    const fake = createFake(seed(
      [user("u1", lastComebackReminderDate ? { lastComebackReminderDate } : {})],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));
    const days = await runDay(WED);
    return { fake, ...days };
  };

  it("un envío de hace 6 días sigue bloqueado: ni plan", async () => {
    const { fake, planner } = await run("2026-05-07");
    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(planner.skippedCooldown).toBe(1);
    // Bloqueado = no se toca NADA: ni el marcador diario, ni hay plan.
    expect(fake.user("u1").lastDailyReminderDate).toBeUndefined();
    expect(fake.user("u1").lastComebackReminderDate).toBe("2026-05-07");
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
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

    await runDay(WED);

    // Última sesión el viernes 8: son 5 días, también era candidato a comeback.
    expect(lastCall().kind).toBe("streak-at-risk");
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
    expect(fake.user("u1").lastComebackReminderDate).toBeUndefined();
  });

  it("un plan de comeback que NO se despacha tampoco consume el cooldown", async () => {
    // Se planifica pero el atleta entrena antes del tick: el marcador del
    // comeback se escribe cuando el push sale, no cuando se planifica.
    const fake = createFake(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")],
      [sessionAt("u1", "2026-05-13T10:00:00")],
    ));

    await runDay(WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
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
    // semanas está en riesgo. Se planifica y sale un solo push, el de racha.
    createFake(seed(atRiskAthlete("u1", 5, 2, { lastTrainedFriday: true })));

    const { planner, dispatch } = await runDay(WED);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(lastCall().kind).toBe("streak-at-risk");
    expect(planner.plannedStreakAtRisk).toBe(1);
    expect(planner.plannedComeback).toBe(0);
    expect(dispatch.notifiedStreakAtRisk).toBe(1);
    expect(dispatch.notifiedComeback).toBe(0);
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

    const { planner } = await runDay(WED);

    expect(planner.skippedNotAtRisk).toBe(0);
    expect(planner.plannedComeback).toBe(1);
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

    await runDay(WED);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  });

  it("máximo UN plan por atleta por día: el de racha reemplaza al del comeback", async () => {
    // Si hubiera quedado un plan de comeback escrito antes (una corrida previa del
    // planificador con otra información), el de racha lo pisa: nunca dos planes.
    const fake = createFake(seed(weekAthlete("u1", EVENING, {
      dailyReminderPlan: {
        date: "2026-05-14", kind: "comeback-reminder", sendAtMinute: 540, daysSince: 4,
      },
    })));

    await notifyDailyRemindersHandler(app, THU);

    expect(fake.user("u1").dailyReminderPlan).toMatchObject({ kind: "streak-at-risk" });
  });
});

// ─── El despachante ───────────────────────────────────────────────────────────

const TODAY = "2026-05-13";
const STREAK_PLAN: Doc = {
  date: TODAY, kind: "streak-at-risk", sendAtMinute: 1080, missing: 5, streakWeeks: 2,
};
const COMEBACK_PLAN: Doc = {
  date: TODAY, kind: "comeback-reminder", sendAtMinute: 540, daysSince: 4,
};

/** Un atleta que ya tiene su plan del día escrito, como lo deja el planificador. */
const planned = (uid: string, plan: Doc = STREAK_PLAN, over: Doc = {}): Entries =>
  [user(uid, { dailyReminderPlan: plan, ...over })];

/** Un tick del despachante, el 13/5 a la hora de pared ART [clock]. */
const tickAt = (clock: string, withMessaging: Messaging = messaging) =>
  dispatchDailyRemindersHandler(app, at(`${TODAY}T${clock}:00`), withMessaging);

describe("dispatchDailyReminders", () => {
  describe("cuándo manda", () => {
    it("antes de sendAtMinute no manda y el plan sigue en pie; en el minuto exacto, sí", async () => {
      const fake = createFake(seed(planned("u1"))); // sendAtMinute = 1080 = 18:00

      const early = await tickAt("17:59");

      expect(early).toMatchObject({ plans: 1, notDue: 1, notified: 0 });
      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(fake.user("u1").dailyReminderPlan).toEqual(STREAK_PLAN);
      expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");

      const onTime = await tickAt("18:00");

      expect(onTime.notified).toBe(1);
      expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    });

    it("después de la hora manda UNA vez, con el texto exacto, y en el tick siguiente no", async () => {
      const fake = createFake(seed(planned("u1")));

      const first = await tickAt("18:15");
      const second = await tickAt("18:30");

      expect(first).toMatchObject({ plans: 1, notified: 1, notifiedStreakAtRisk: 1 });
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
      // El plan se consumió: no hay nada que releer ni que mandar de nuevo.
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
      expect(fake.user("u1").lastDailyReminderDate).toBe(TODAY);
      expect(second.plans).toBe(0);
      expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    });

    it("el texto concuerda en singular: 'Te falta 1 entrenamiento… racha de 1 semana'", async () => {
      createFake(seed(planned("u1", { ...STREAK_PLAN, missing: 1, streakWeeks: 1 })));

      await tickAt("18:15");

      expect(lastCall().notification).toEqual({
        title: "Hoy o se corta 🔥",
        body: "Te falta 1 entrenamiento esta semana para sostener tu racha de 1 semana.",
      });
    });

    it("el comeback: texto exacto y los dos marcadores", async () => {
      const fake = createFake(seed(planned("u1", COMEBACK_PLAN)));

      await tickAt("09:00");

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
      expect(fake.user("u1").lastDailyReminderDate).toBe(TODAY);
      expect(fake.user("u1").lastComebackReminderDate).toBe(TODAY);
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
    });

    it("antes de las 08:00 ni siquiera lee: ningún plan puede vencer antes del piso", async () => {
      const fake = createFake(seed(planned("u1", { ...COMEBACK_PLAN, sendAtMinute: 480 })));

      const early = await tickAt("07:59");

      expect(early.plans).toBe(0);
      expect(fake.queryLog).toHaveLength(0);
      expect(mockedSendFcm).not.toHaveBeenCalled();

      await tickAt("08:00");

      expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    });
  });

  describe("la query", () => {
    it("el plan de AYER se ignora: no matchea la query de hoy y no se toca", async () => {
      const yesterday = { ...STREAK_PLAN, date: "2026-05-12" };
      const fake = createFake(seed(planned("u1", yesterday)));

      const result = await tickAt("23:00");

      expect(result.plans).toBe(0);
      expect(fake.queryLog[0].returned).toBe(0);
      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(fake.user("u1").dailyReminderPlan).toEqual(yesterday);
    });

    it("es una IGUALDAD pura sobre la fecha: sin rangos, sin orderBy, sin índices nuevos", async () => {
      const fake = createFake(seed(planned("u1")));

      await tickAt("18:15");

      const usersQuery = fake.queryLog.filter((q) => q.scope === "users");
      expect(usersQuery).toHaveLength(1);
      expect(usersQuery[0].fields).toEqual([`dailyReminderPlan.date==${TODAY}`]);
    });

    it("lee las sesiones de HOY de cada vencido: desde las 00:00 ART, sin filtrar por estado", async () => {
      const fake = createFake(seed(planned("u1")));

      await tickAt("18:15");

      const sessions = fake.queryLog.filter((q) => q.scope === "users/u1/sessions");
      expect(sessions).toHaveLength(1);
      expect(sessions[0].fields).toEqual(["startedAt>=2026-05-13T03:00:00.000Z"]);
    });

    it("sólo cuesta una query de sesiones por plan VENCIDO: los que no vencieron no la hacen", async () => {
      const fake = createFake(seed(
        planned("vence", { ...STREAK_PLAN, sendAtMinute: 600 }),
        planned("no-vence", { ...STREAK_PLAN, sendAtMinute: 1300 }),
      ));

      await tickAt("12:00");

      expect(fake.queryLog.map((q) => q.scope).sort()).toEqual(["users", "users/vence/sessions"]);
    });
  });

  const sessionStates: Array<[string, { status: string; wasFullyCompleted: boolean }]> = [
    ["en curso", { status: "active", wasFullyCompleted: false }],
    ["terminada", { status: "finished", wasFullyCompleted: true }],
    ["abandonada", { status: "finished", wasFullyCompleted: false }],
  ];

  describe.each<[string, Doc]>([
    ["racha", STREAK_PLAN],
    ["comeback", COMEBACK_PLAN],
  ])("si el atleta arrancó una sesión HOY, no manda el plan de %s", (_label, plan) => {
    it.each(sessionStates)("sesión %s: no manda, borra el plan y no gasta marcadores", async (_state, over) => {
      const fake = createFake(seed(
        planned("u1", plan),
        [sessionAt("u1", "2026-05-13T12:00:00", over)],
      ));

      const result = await tickAt("18:15");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result).toMatchObject({ plans: 1, skipped: 1, skippedTrainedToday: 1, notified: 0 });
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
      expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
      expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
      // Y no se vuelve a leer en el resto del día.
      expect((await tickAt("18:30")).plans).toBe(0);
    });
  });

  it("'hoy' empieza a las 00:00 ART: una sesión de las 23:59 de ayer no frena, una de las 00:00 sí", async () => {
    createFake(seed(
      planned("ayer"), [sessionAt("ayer", "2026-05-12T23:59:00")],
      planned("hoy"), [sessionAt("hoy", "2026-05-13T00:00:00")],
    ));

    const result = await tickAt("18:15");

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(mockedSendFcm.mock.calls[0][1].uids).toEqual(["ayer"]);
    expect(result).toMatchObject({ notified: 1, skippedTrainedToday: 1 });
  });

  describe("la reserva transaccional vuelve a verificar", () => {
    it("el opt-out ENTRE la planificación y el envío no manda, y suelta el plan", async () => {
      const fake = createFake(seed(planned("u1")));
      fake.hooks.beforeTransaction = () => {
        fake.docs.set("users/u1", {
          ...fake.user("u1"),
          notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
        });
      };

      const result = await tickAt("18:15");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result.skippedOptedOut).toBe(1);
      expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
      expect((await tickAt("18:30")).plans).toBe(0);
    });

    it("un opt-out que ya estaba al despachar tampoco manda", async () => {
      const fake = createFake(seed(planned("u1", STREAK_PLAN, {
        notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
      })));

      const result = await tickAt("18:15");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result.skippedOptedOut).toBe(1);
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
    });

    it("apagar OTRA fila de preferencias no frena el recordatorio", async () => {
      createFake(seed(planned("u1", STREAK_PLAN, {
        notificationPrefs: { novedades_plan: { push: false } },
      })));

      await tickAt("18:15");

      expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    });

    it("no manda a quien no es atleta", async () => {
      const fake = createFake(seed(planned("pf", STREAK_PLAN, { role: "trainer" })));

      const result = await tickAt("18:15");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result.skippedNotAthlete).toBe(1);
      expect(fake.user("pf")).not.toHaveProperty("dailyReminderPlan");
    });

    it("si ya se le mandó hoy (lastDailyReminderDate de hoy) no manda y borra el plan resucitado", async () => {
      const fake = createFake(seed(planned("u1", STREAK_PLAN, { lastDailyReminderDate: TODAY })));

      const result = await tickAt("18:15");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result.skippedAlreadySent).toBe(1);
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
      expect(fake.user("u1").lastDailyReminderDate).toBe(TODAY);
    });

    it("el cooldown del comeback: si se consumió mientras tanto, no manda y no toca el marcador", async () => {
      const fake = createFake(seed(planned("u1", COMEBACK_PLAN)));
      fake.hooks.beforeTransaction = () => {
        fake.docs.set("users/u1", { ...fake.user("u1"), lastComebackReminderDate: "2026-05-11" });
      };

      const result = await tickAt("09:00");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result.skippedCooldown).toBe(1);
      expect(fake.user("u1").lastComebackReminderDate).toBe("2026-05-11");
      expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
    });

    it("el cooldown del comeback pasa a los 7 días justos, y no aplica al plan de racha", async () => {
      createFake(seed(
        planned("siete", COMEBACK_PLAN, { lastComebackReminderDate: "2026-05-06" }),
        planned("racha", STREAK_PLAN, { lastComebackReminderDate: TODAY }),
      ));

      const result = await tickAt("18:15");

      expect(result.notified).toBe(2);
    });

    it("si otro tick (o el planificador) consumió el plan, no manda: skippedPlanGone", async () => {
      const fake = createFake(seed(planned("u1")));
      fake.hooks.beforeTransaction = () => {
        const withoutPlan = { ...fake.user("u1") };
        delete withoutPlan.dailyReminderPlan;
        fake.docs.set("users/u1", withoutPlan);
      };

      const result = await tickAt("18:15");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result.skippedPlanGone).toBe(1);
    });

    it("se manda lo que dice el plan AHORA, no el que vio la query", async () => {
      const fake = createFake(seed(planned("u1", STREAK_PLAN)));
      fake.hooks.beforeTransaction = () => {
        fake.docs.set("users/u1", {
          ...fake.user("u1"),
          dailyReminderPlan: { ...COMEBACK_PLAN, daysSince: 6 },
        });
      };

      await tickAt("18:15");

      expect(lastCall()).toMatchObject({
        kind: "comeback-reminder",
        notification: { body: "Hace 6 días que no entrenás. ¿Arrancamos hoy?" },
      });
      expect(fake.user("u1").lastComebackReminderDate).toBe(TODAY);
    });

    it("un plan de OTRO día que apareció entre la query y la reserva no se manda ni se toca", async () => {
      const fake = createFake(seed(planned("u1")));
      const other = { ...STREAK_PLAN, date: "2026-05-12" };
      fake.hooks.beforeTransaction = () => {
        fake.docs.set("users/u1", { ...fake.user("u1"), dailyReminderPlan: other });
      };

      const result = await tickAt("18:15");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result.skippedPlanGone).toBe(1);
      expect(fake.user("u1").dailyReminderPlan).toEqual(other);
    });
  });

  describe("un plan malformado se borra sin mandar", () => {
    const malformed: Array<[string, Doc]> = [
      ["missing no es un número", { ...STREAK_PLAN, missing: "5" }],
      ["missing es 0", { ...STREAK_PLAN, missing: 0 }],
      ["streakWeeks fraccionario", { ...STREAK_PLAN, streakWeeks: 1.5 }],
      ["daysSince es 0", { ...COMEBACK_PLAN, daysSince: 0 }],
      ["daysSince falta", { date: TODAY, kind: "comeback-reminder", sendAtMinute: 540 }],
      ["kind desconocido", { ...STREAK_PLAN, kind: "otro" }],
      ["sendAtMinute no es un número", { ...STREAK_PLAN, sendAtMinute: "mediodía" }],
      ["sendAtMinute es NaN", { ...STREAK_PLAN, sendAtMinute: NaN }],
      ["sólo la fecha", { date: TODAY }],
    ];

    it.each(malformed)("%s", async (_name, plan) => {
      const fake = createFake(seed(planned("u1", plan)));

      const result = await tickAt("23:00");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result).toMatchObject({ plans: 1, skippedInvalidPlan: 1, failed: 0 });
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
    });

    it("también si se corrompe entre la query y la reserva", async () => {
      const fake = createFake(seed(planned("u1")));
      fake.hooks.beforeTransaction = () => {
        fake.docs.set("users/u1", {
          ...fake.user("u1"),
          dailyReminderPlan: { ...STREAK_PLAN, missing: "mucho" },
        });
      };

      const result = await tickAt("18:15");

      expect(mockedSendFcm).not.toHaveBeenCalled();
      expect(result.skippedInvalidPlan).toBe(1);
      expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
    });

    it("parseDailyReminderPlan devuelve sólo los campos conocidos", () => {
      expect(parseDailyReminderPlan({ ...STREAK_PLAN, extra: "<script>" })).toEqual(STREAK_PLAN);
      expect(parseDailyReminderPlan({ ...COMEBACK_PLAN, extra: 1 })).toEqual(COMEBACK_PLAN);
      expect(parseDailyReminderPlan(null)).toBeNull();
      expect(parseDailyReminderPlan("plan")).toBeNull();
      expect(parseDailyReminderPlan(undefined)).toBeNull();
    });
  });

  describe("los contadores", () => {
    it("plans = notDue + notified + skipped + failed", async () => {
      createFake(seed(
        planned("manda"),
        planned("no-vence", { ...STREAK_PLAN, sendAtMinute: 1300 }),
        planned("entreno"), [sessionAt("entreno", "2026-05-13T10:00:00")],
        planned("apagado", STREAK_PLAN, {
          notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
        }),
        planned("falla"),
      ));
      mockedSendFcm.mockImplementation(async (_app, input) => {
        if (input.uids[0] === "falla") throw new Error("FCM caído");
        return { successCount: 1, failureCount: 0 };
      });

      const r = await tickAt("18:15");

      expect(r).toMatchObject({
        plans: 5, notDue: 1, notified: 1, skipped: 2, failed: 1,
        skippedTrainedToday: 1, skippedOptedOut: 1, dateKey: TODAY, minuteOfDay: 1095,
      });
      expect(r.plans).toBe(r.notDue + r.notified + r.skipped + r.failed);
    });
  });

  it("dos ticks SOLAPADOS mandan un solo push: la transacción es la autoridad", async () => {
    createFake(seed(planned("u1")));

    const [a, b] = await Promise.all([tickAt("18:15"), tickAt("18:15")]);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(a.notified + b.notified).toBe(1);
    expect(a.skippedAlreadySent + b.skippedAlreadySent).toBe(1);
  });
});

// ─── Opt-out, rol, idempotencia, fallas ───────────────────────────────────────

describe("opt-out", () => {
  const comebackAthlete = (prefs?: Doc) => seed(
    [user("u1", prefs ? { notificationPrefs: prefs } : {})],
    [sessionAt("u1", "2026-05-09T12:00:00")],
  );

  it("push === false: no planifica, no envía y no toca el doc", async () => {
    const fake = createFake(comebackAthlete({ [DAILY_REMINDERS_PREF_KEY]: { push: false } }));

    const { planner } = await runDay(WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(planner.skippedOptedOut).toBe(1);
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
    expect(fake.user("u1").lastDailyReminderDate).toBeUndefined();
    expect(fake.user("u1").lastComebackReminderDate).toBeUndefined();
  });

  it("el opt-out también frena la racha en riesgo, sin gastar lecturas de rutinas", async () => {
    const fake = createFake(seed(
      atRiskAthlete("u1", 5, 2),
      [["users/u1", { role: "athlete", notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } } }]],
    ));

    await runDay(WED);

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

    await runDay(WED);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  });

  it("si apaga el push MIENTRAS corre el sistema (entre el plan y el envío), la reserva lo respeta", async () => {
    // Entre las 06:00 y la hora del envío pasan horas: el atleta puede entrar a
    // Privacidad y apagar el interruptor.
    const fake = createFake(comebackAthlete());
    await notifyDailyRemindersHandler(app, WED);
    expect(fake.user("u1")).toHaveProperty("dailyReminderPlan");
    fake.docs.set("users/u1", {
      ...fake.user("u1"),
      notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
    });

    const dispatch = await dispatchDailyRemindersHandler(app, endOfDay(WED), messaging);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(dispatch.skippedOptedOut).toBe(1);
    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
  });

  describe("con el sendFcm REAL, para ver el historial", () => {
    // `sendFcm` con la preferencia apagada frena el banner pero SÍ escribe la
    // entrada de `users/{uid}/notifications`. De eso depende que el planificador
    // y la reserva del despachante corten ANTES de llamarlo: si esto deja de ser
    // cierto, el corte sobra (y este test avisa); si el corte se saca, los
    // siguientes se ponen rojos.
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

    it("con la pref apagada NO deja una fila en la bandeja", async () => {
      const fake = createFake(seed(
        [["users/u1", {
          role: "athlete",
          fcmTokens: ["t1"],
          notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
        }]],
        [sessionAt("u1", "2026-05-09T12:00:00")],
      ));

      await runDay(WED, realMessaging);

      expect(fake.historyOf("u1")).toHaveLength(0);
      expect(multicast).not.toHaveBeenCalled();
    });

    it("si la apaga ENTRE el plan y el envío, tampoco", async () => {
      const fake = createFake(seed(
        [["users/u1", { role: "athlete", fcmTokens: ["t1"] }]],
        [sessionAt("u1", "2026-05-09T12:00:00")],
      ));
      await notifyDailyRemindersHandler(app, WED);
      fake.docs.set("users/u1", {
        ...fake.user("u1"),
        notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } },
      });

      await dispatchDailyRemindersHandler(app, endOfDay(WED), realMessaging);

      expect(fake.historyOf("u1")).toHaveLength(0);
      expect(multicast).not.toHaveBeenCalled();
    });

    it("y con la pref encendida deja UNA fila y manda el push con kind y deepLink", async () => {
      const fake = createFake(seed(
        [["users/u1", { role: "athlete", fcmTokens: ["t1", "t2"] }]],
        [sessionAt("u1", "2026-05-09T12:00:00")],
      ));

      await runDay(WED, realMessaging);

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

    const { planner } = await runDay(WED);

    expect(mockedSendFcm).not.toHaveBeenCalled();
    expect(planner.skippedNotAthlete).toBe(1);
    expect(fake.user("pf").lastDailyReminderDate).toBeUndefined();
  });

  it("un usuario borrado con sesiones huérfanas se saltea sin fallar", async () => {
    createFake(seed([sessionAt("fantasma", "2026-05-09T12:00:00")]));

    const { planner } = await runDay(WED);

    expect(planner.skippedNotAthlete).toBe(1);
    expect(planner.failed).toBe(0);
  });
});

describe("idempotencia", () => {
  it("una segunda corrida el mismo día no vuelve a planificar ni a mandar", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2)));

    await runDay(WED);
    const second = await runDay(WED);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(second.dispatch.notified).toBe(0);
    expect(second.planner.planned).toBe(0);
    expect(second.planner.skippedAlreadySent).toBe(1);
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
  });

  it("dos planificadores SOLAPADOS dejan un solo plan y sale un solo push", async () => {
    const fake = createFake(seed(atRiskAthlete("u1", 5, 2)));

    await Promise.all([
      notifyDailyRemindersHandler(app, WED),
      notifyDailyRemindersHandler(app, WED),
    ]);
    const plan = fake.user("u1").dailyReminderPlan;
    await dispatchDailyRemindersHandler(app, endOfDay(WED), messaging);

    expect(plan).toMatchObject({ kind: "streak-at-risk", date: "2026-05-13" });
    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  });

  it("al día siguiente vuelve a evaluar (el marcador es del día, no para siempre)", async () => {
    const fake = createFake(seed(
      [user("u1", { lastDailyReminderDate: "2026-05-12" })],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));

    await runDay(WED);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
  });

  it("el día lo marca la fecha ART: 00:30 ART y 23:30 ART son el mismo día", async () => {
    const fake = createFake(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));

    await notifyDailyRemindersHandler(app, at("2026-05-13T00:30:00"));
    expect(fake.user("u1").dailyReminderPlan).toMatchObject({ date: "2026-05-13" });
    // 23:30 ART son las 02:30 UTC del 14: con fecha UTC sería otro día.
    await notifyDailyRemindersHandler(app, at("2026-05-13T23:30:00"));
    expect(fake.user("u1").dailyReminderPlan).toMatchObject({ date: "2026-05-13" });
    await dispatchDailyRemindersHandler(app, at("2026-05-13T23:30:00"), messaging);

    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
  });
});

describe("si el envío falla", () => {
  /** Planifica a las 06:00 y deja el estado listo para despachar a las [clock]. */
  const planFor = async (entries: Record<string, Doc>) => {
    const fake = createFake(entries);
    await notifyDailyRemindersHandler(app, WED);
    return fake;
  };
  const tick = (clock: string) =>
    dispatchDailyRemindersHandler(app, at(`2026-05-13T${clock}:00`), messaging);

  it("suelta la reserva, deja el plan en pie y el próximo tick reintenta", async () => {
    const fake = await planFor(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));
    const plan = fake.user("u1").dailyReminderPlan;
    expect(plan).toBeDefined();
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));

    const primera = await tick("09:00");

    expect(primera.notified).toBe(0);
    expect(primera.failed).toBe(1);
    expect(errorLog).toHaveBeenCalledWith(
      "dispatchDailyReminders: failed for athlete",
      expect.objectContaining({ uid: "u1", error: "FCM caído" }),
    );
    // Nunca había tenido marcadores: se borran, no quedan en null. Y el plan vuelve.
    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
    expect(fake.user("u1").dailyReminderPlan).toEqual({ ...(plan as object), attempts: 1 });

    const segunda = await tick("09:15");

    expect(segunda.notified).toBe(1);
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-13");
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
  });

  it(`con FCM caído reintenta ${MAX_SEND_ATTEMPTS} veces como mucho y descarta el plan`, async () => {
    // Cada intento fallido de sendFcm ya escribió una fila de historial: sin
    // tope, una tarde de FCM caído llenaba la campanita de avisos repetidos.
    const fake = await planFor(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));
    mockedSendFcm.mockRejectedValue(new Error("FCM caído"));

    for (const clock of ["09:00", "09:15", "09:30", "09:45", "10:00"]) await tick(clock);

    expect(mockedSendFcm).toHaveBeenCalledTimes(MAX_SEND_ATTEMPTS);
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
    // Los marcadores quedan como estaban: no hubo aviso ese día.
    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
    expect(jest.spyOn(logger, "warn")).toHaveBeenCalledWith(
      "dispatchDailyReminders: giving up after repeated send failures",
      { uid: "u1", attempts: MAX_SEND_ATTEMPTS },
    );
  });

  it("restaura los valores PREVIOS de los dos marcadores, no los borra", async () => {
    const fake = await planFor(seed(
      [user("u1", {
        lastDailyReminderDate: "2026-05-12",
        lastComebackReminderDate: "2026-05-05",
      })],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));

    await tick("09:00");

    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-12");
    expect(fake.user("u1").lastComebackReminderDate).toBe("2026-05-05");
    expect(fake.user("u1").dailyReminderPlan).toMatchObject({ kind: "comeback-reminder" });
  });

  it("en la racha restaura sólo el marcador diario y no inventa el del comeback", async () => {
    const fake = await planFor(seed(atRiskAthlete("u1", 5, 2)));
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));

    await dispatchDailyRemindersHandler(app, endOfDay(WED), messaging);

    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
    expect(fake.user("u1").dailyReminderPlan).toMatchObject({ kind: "streak-at-risk" });
  });

  it("un atleta que falla no frena a los demás", async () => {
    await planFor(seed(
      [user("a")], [sessionAt("a", "2026-05-09T12:00:00")],
      [user("b")], [sessionAt("b", "2026-05-09T12:00:00")],
    ));
    // El primero en enviar falla, sea quien sea; el otro tiene que salir igual.
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));

    const result = await tick("09:00");

    expect(result.failed).toBe(1);
    expect(result.notified).toBe(1);
  });

  it("si ni siquiera se puede soltar la reserva, queda un warn con el motivo", async () => {
    const fake = await planFor(seed(
      [user("u1")],
      [sessionAt("u1", "2026-05-09T12:00:00")],
    ));
    mockedSendFcm.mockRejectedValueOnce(new Error("FCM caído"));
    fake.hooks.beforeUpdate = () => {
      throw new Error("escritura rechazada");
    };

    const result = await tick("09:00");

    expect(result.failed).toBe(1);
    expect(jest.spyOn(logger, "warn")).toHaveBeenCalledWith(
      "dispatchDailyReminders: could not release the reservation",
      expect.objectContaining({ uid: "u1", error: "escritura rechazada" }),
    );
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

    const result = await notifyDailyRemindersHandler(app, WED);

    expect(result.scannedSessions).toBe(501);
    expect(result.planned).toBe(1);
    expect(fake.queryLog.filter((q) => q.scope === "group:sessions")).toHaveLength(2);
  });

  it("no suma al contador las sesiones del futuro: la query corta en `now`", async () => {
    createFake(seed([user("u1")], [sessionAt("u1", "2026-05-14T12:00:00")]));

    const result = await notifyDailyRemindersHandler(app, WED);

    expect(result.scannedSessions).toBe(0);
  });

  it("candidates = planned + skipped + failed", async () => {
    const fake = createFake(seed(
      [user("ok")], [sessionAt("ok", "2026-05-09T12:00:00")],
      [user("off", { notificationPrefs: { [DAILY_REMINDERS_PREF_KEY]: { push: false } } })],
      [sessionAt("off", "2026-05-09T12:00:00")],
      [user("ya", { lastDailyReminderDate: "2026-05-13" })], [sessionAt("ya", "2026-05-09T12:00:00")],
      [["users/pf", { role: "trainer" }]], [sessionAt("pf", "2026-05-09T12:00:00")],
      [user("falla")], [sessionAt("falla", "2026-05-09T12:00:00")],
    ));
    fake.hooks.beforeUpdate = (path) => {
      if (path === "users/falla") throw new Error("escritura rechazada");
    };

    const r = await notifyDailyRemindersHandler(app, WED);

    expect(r).toMatchObject({
      candidates: 5,
      planned: 1,
      skipped: 3,
      failed: 1,
      skippedOptedOut: 1,
      skippedAlreadySent: 1,
      skippedNotAthlete: 1,
    });
    expect(r.candidates).toBe(r.planned + r.skipped + r.failed);
  });
});

// ─── De punta a punta, con reloj ──────────────────────────────────────────────

describe("de punta a punta: el planificador a las 06:00 y el despachante cada 15 minutos", () => {
  it("racha: con horario habitual ~18:08 el aviso sale en el primer tick desde las 19:08 (19:15)", async () => {
    const fake = createFake(seed(weekAthlete("u1", EVENING)));

    const times = await sendTimes(THU);

    expect(times).toEqual(["19:15"]);
    // Y es el de racha, UNO solo; el comeback (también elegible ese jueves) no sale.
    expect(mockedSendFcm).toHaveBeenCalledTimes(1);
    expect(lastCall()).toMatchObject({
      kind: "streak-at-risk",
      notification: {
        title: "Hoy o se corta 🔥",
        body: streakBody(4, 1),
      },
    });
    expect(fake.user("u1").lastDailyReminderDate).toBe("2026-05-14");
    expect(fake.user("u1")).not.toHaveProperty("lastComebackReminderDate");
  });

  it("racha: si entrena a media tarde (ya sea en curso) no le llega nada en todo el día", async () => {
    const fake = createFake(seed(
      weekAthlete("u1", EVENING),
      [sessionAt("u1", "2026-05-14T15:00:00", { status: "active", wasFullyCompleted: false })],
    ));

    expect(await sendTimes(THU)).toEqual([]);
    expect(fake.user("u1")).not.toHaveProperty("dailyReminderPlan");
    expect(fake.user("u1")).not.toHaveProperty("lastDailyReminderDate");
  });

  it("racha: sin patrón claro sale en el tick de las 18:00", async () => {
    createFake(seed(weekAthlete("u1", ["07:00", "10:00", "13:00", "16:00"])));

    expect(await sendTimes(THU)).toEqual(["18:00"]);
  });

  it("racha: el piso (08:00) y el techo (22:30) también valen en el reloj", async () => {
    createFake(seed(
      weekAthlete("madrugador", ["06:00", "06:10", "06:20", "06:30"]),
      weekAthlete("nocturno", ["21:50", "22:00", "22:10", "22:20"]),
    ));

    await notifyDailyRemindersHandler(app, THU);
    const sentTo: Array<[string, string]> = [];
    for (let t = THU.getTime(); t <= endOfDay(THU).getTime(); t += 15 * MIN) {
      const before = mockedSendFcm.mock.calls.length;
      await dispatchDailyRemindersHandler(app, new Date(t), messaging);
      for (const call of mockedSendFcm.mock.calls.slice(before)) {
        sentTo.push([clockOf(new Date(t)), call[1].uids[0]]);
      }
    }

    expect(sentTo).toEqual([["08:00", "madrugador"], ["22:30", "nocturno"]]);
  });

  it("cada atleta recibe a SU hora, aunque compartan el día", async () => {
    createFake(seed(
      weekAthlete("tarde", EVENING),
      weekAthlete("sinpatron", ["07:00", "10:00", "13:00", "16:00"]),
    ));

    await notifyDailyRemindersHandler(app, THU);
    const sentTo: Array<[string, string]> = [];
    for (let t = THU.getTime(); t <= endOfDay(THU).getTime(); t += 15 * MIN) {
      const before = mockedSendFcm.mock.calls.length;
      await dispatchDailyRemindersHandler(app, new Date(t), messaging);
      for (const call of mockedSendFcm.mock.calls.slice(before)) {
        sentTo.push([clockOf(new Date(t)), call[1].uids[0]]);
      }
    }

    expect(sentTo).toEqual([["18:00", "sinpatron"], ["19:15", "tarde"]]);
  });
});

// ─── Copy ─────────────────────────────────────────────────────────────────────

describe("copy", () => {
  it.each([
    [1, 1, "Te falta 1 entrenamiento esta semana para sostener tu racha de 1 semana."],
    [1, 2, "Te falta 1 entrenamiento esta semana para sostener tu racha de 2 semanas."],
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
