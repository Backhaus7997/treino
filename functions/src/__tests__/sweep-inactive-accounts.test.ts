/**
 * sweep-inactive-accounts.test.ts — plazos, exclusiones y modo de prueba de la
 * baja automática por inactividad. LOCAL — sin emulador.
 *
 * ─── Qué se está probando, y por qué así ────────────────────────────────────
 *
 * Este barrido BORRA CUENTAS. No hay deshacer, no hay papelera de 30 días, y el
 * usuario al que le toca es, por definición, alguien que no está mirando. O
 * sea: el modo de falla de un bug acá no es una pantalla rota, es un dato de
 * salud de alguien que no pidió nada, borrado para siempre.
 *
 * Por eso la señal de actividad y el reloj se INYECTAN. Un test que dependa de
 * `new Date()` no puede afirmar nada sobre un plazo de 36 meses sin esperar 36
 * meses, y un test que dependa de `listUsers` no puede describir una cuenta con
 * la forma exacta que hace falta para caer del lado peligroso de un borde.
 *
 * Las aserciones que más importan son NEGATIVAS: que NO borre. Ver el `describe`
 * de "nunca borra sin aviso previo".
 */

jest.mock("firebase-admin", () => {
  /**
   * `Timestamp` tiene que ser una CLASE de verdad, no un objeto con métodos:
   * `leerAviso` hace `raw instanceof Timestamp` para decidir si el registro de
   * aviso sirve. Con un doble que no sea instanciable ese chequeo da `false`
   * SIEMPRE, el test pasa en verde y lo que se probó es la rama de "registro
   * ilegible" — o sea, no se probó nada de lo que dice el nombre.
   */
  class FakeTimestamp {
    constructor(readonly ms: number) {}
    static fromDate(d: Date) {
      return new FakeTimestamp(d.getTime());
    }
    toDate() {
      return new Date(this.ms);
    }
  }
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  firestore.Timestamp = FakeTimestamp;
  firestore.FieldValue = {
    // El centinela, igual que el real: `serverTimestamp()` no es un valor, es
    // una instrucción para el servidor. El doble de la base lo resuelve al
    // escribir (ver `installDb`), que es exactamente lo que pasa contra la base
    // real.
    serverTimestamp: () => ({ __serverTimestamp: true }),
    delete: () => ({ __fakeFieldValue: "delete" }),
  };
  return { firestore, app: jest.fn(), initializeApp: jest.fn() };
});

jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());

jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

// Las dos puertas que el grafo de este test alcanza SIN llamarlas nunca. No es
// ceremonia: el barrido trae `runDeleteAccount`, y con el la cascada entera —
// incluida `cascade/storage.ts`. Sin estos dos dobles, esos modulos resuelven
// contra el SDK REAL con un `firebase-admin/app` de mentira al lado, que es
// exactamente el agujero que vigila `firebase-admin-mock-surface.test.ts`.
//
// OJO AL ESCRIBIR ACA ARRIBA: ese gate parsea el archivo con una regex laxa que
// arranca en la palabra i-m-p-o-r-t (o e-x-p-o-r-t) y traga hasta el `from`
// siguiente. Un comentario que la use, puesto antes de la primera declaracion,
// le regala sus palabras sueltas al subpath equivocado y el gate se pone rojo
// nombrando simbolos que no existen. Por eso ninguna de estas lineas la
// contiene. Es un bug del gate, no de este archivo — queda anotado aparte.
jest.mock("firebase-admin/auth", () => ({ getAuth: jest.fn() }));
jest.mock("firebase-admin/storage", () => ({ getStorage: jest.fn() }));

jest.mock("firebase-functions", () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

import { App } from "firebase-admin/app";
import { DocumentData, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { dobleNamespaced } from "./helpers/modular-from-namespaced";
import {
  AccountActivity,
  DELETE_AFTER_MONTHS,
  MIN_NOTICE_AGE_DAYS,
  NOTICE_AFTER_MONTHS,
  RETENTION_NOTICES_COLLECTION,
  RETENTION_SWEEP_DRY_RUN,
  RETENTION_SWEEP_PROVIDER,
  addMonths,
  proyeccionDeBaja,
  resolveLastActiveAt,
  sweepInactiveAccountsHandler,
} from "../retention/sweep-inactive-accounts";
import { MAIL_QUEUE_COLLECTION } from "../mail/types";
import { formatShortDateAR } from "../mail/format";

const APP = {} as App;

/** El "hoy" de todos los tests. Fijo: los plazos se miden contra esto. */
const HOY = new Date("2026-09-14T08:00:00.000Z");

/** Una fecha `n` meses antes de HOY. */
function haceMeses(n: number): Date {
  return addMonths(HOY, -n);
}

/** Una fecha `n` días antes de HOY. */
function haceDias(n: number): Date {
  return new Date(HOY.getTime() - n * 24 * 60 * 60 * 1000);
}

// ── El doble de Firestore ───────────────────────────────────────────────────

interface FakeDbOpts {
  /** `users/{uid}`. Ausente = el documento no existe. */
  users?: Record<string, DocumentData>;
  /** Uids con vínculo ACTIVO a un PF. */
  linked?: Set<string>;
  /** `retention_notices/{uid}` ya existentes. */
  notices?: Record<string, DocumentData>;
  /** Uids cuyo `users/{uid}.get()` explota. */
  userDocFails?: Set<string>;
}

function installDb(opts: FakeDbOpts = {}) {
  const notices: Record<string, DocumentData> = { ...(opts.notices ?? {}) };
  const mailQueue = new Map<string, DocumentData>();
  const noticeWrites: Array<{ uid: string; data: DocumentData }> = [];
  const linkQueries: string[] = [];

  /** Resuelve los centinelas de `serverTimestamp`, igual que el servidor. */
  function resolver(data: DocumentData): DocumentData {
    const salida: DocumentData = {};
    for (const [k, v] of Object.entries(data)) {
      salida[k] = (v as { __serverTimestamp?: boolean })?.__serverTimestamp
        ? Timestamp.fromDate(HOY)
        : v;
    }
    return salida;
  }

  function linksQuery(uid?: string) {
    const q: Record<string, unknown> = {
      where: () => linksQuery(uid),
      limit: () => linksQuery(uid),
      get: async () => {
        linkQueries.push(uid ?? "?");
        return { empty: !(opts.linked?.has(uid ?? "") ?? false) };
      },
    };
    return q;
  }

  (dobleNamespaced().firestore as unknown as jest.Mock).mockReturnValue({
    collection: (name: string) => {
      if (name === "users") {
        return {
          doc: (uid: string) => ({
            get: async () => {
              if (opts.userDocFails?.has(uid)) throw new Error("doc corrupto");
              return {
                exists: opts.users?.[uid] !== undefined,
                data: () => opts.users?.[uid],
              };
            },
          }),
        };
      }
      if (name === "trainer_links") {
        return {
          where: (_f: string, _op: string, value: string) => linksQuery(value),
        };
      }
      if (name === RETENTION_NOTICES_COLLECTION) {
        return {
          doc: (uid: string) => ({
            get: async () => ({
              exists: notices[uid] !== undefined,
              data: () => notices[uid],
            }),
            set: async (data: DocumentData, options?: { merge?: boolean }) => {
              const resuelto = resolver(data);
              noticeWrites.push({ uid, data: resuelto });
              notices[uid] = options?.merge
                ? { ...(notices[uid] ?? {}), ...resuelto }
                : resuelto;
            },
          }),
        };
      }
      if (name === MAIL_QUEUE_COLLECTION) {
        return {
          doc: (id: string) => ({
            // `create()` y no `set()`, con el mismo código gRPC que devuelve
            // Firestore (6 = ALREADY_EXISTS). Es el mecanismo entero de
            // deduplicación de `enqueueMail`: un doble que sobrescriba en
            // silencio haría pasar el test de "una sola vez" por el motivo
            // equivocado.
            create: async (data: DocumentData) => {
              if (mailQueue.has(id)) {
                const e = new Error("already exists") as Error & {
                  code?: number;
                };
                e.code = 6;
                throw e;
              }
              mailQueue.set(id, data);
            },
          }),
        };
      }
      throw new Error(`coleccion inesperada: ${name}`);
    },
  });

  return { notices, mailQueue, noticeWrites, linkQueries };
}

/** Corre el barrido sobre una lista fija de cuentas, con la baja espiada. */
async function correr(
  cuentas: AccountActivity[],
  extra: { dryRun?: boolean; maxPerRun?: number; now?: Date } = {},
) {
  const bajas: Array<{ uid: string; provider: string }> = [];
  const r = await sweepInactiveAccountsHandler(APP, {
    dryRun: false,
    now: HOY,
    ...extra,
    listAccounts: async function* () {
      for (const c of cuentas) yield c;
    },
    deleteAccount: async (_app, uid, provider) => {
      bajas.push({ uid, provider });
      return { status: "success" };
    },
  });
  return { r, bajas };
}

const ATLETA: DocumentData = { role: "athlete" };

beforeEach(() => {
  jest.clearAllMocks();
});

// ── La señal ────────────────────────────────────────────────────────────────

describe("resolveLastActiveAt — la señal y sus dos caídas", () => {
  it("usa lastRefreshTime cuando está", () => {
    const r = resolveLastActiveAt({
      lastRefreshTime: "Sat, 01 Mar 2025 10:00:00 GMT",
      lastSignInTime: "Sat, 01 Jan 2022 10:00:00 GMT",
      creationTime: "Sat, 01 Jan 2020 10:00:00 GMT",
    });
    expect(r?.toISOString()).toBe("2025-03-01T10:00:00.000Z");
  });

  it("cae a lastSignInTime cuando lastRefreshTime viene vacío", () => {
    // No es hipotético: `lastRefreshTime` es opcional en los metadatos y llega
    // `null` para cuentas que nunca refrescaron un token.
    const r = resolveLastActiveAt({
      lastRefreshTime: null,
      lastSignInTime: "Sat, 01 Jan 2022 10:00:00 GMT",
      creationTime: "Sat, 01 Jan 2020 10:00:00 GMT",
    });
    expect(r?.toISOString()).toBe("2022-01-01T10:00:00.000Z");
  });

  it("cae a creationTime cuando no hay ninguna de las dos", () => {
    const r = resolveLastActiveAt({
      creationTime: "Sat, 01 Jan 2020 10:00:00 GMT",
    });
    expect(r?.toISOString()).toBe("2020-01-01T10:00:00.000Z");
  });

  it("devuelve null cuando ninguna sirve", () => {
    // Y una cuenta sin señal NO se toca: `listarCuentasDeAuth` la saltea. Sin
    // señal no se puede afirmar inactividad, y lo que sigue es irreversible.
    expect(resolveLastActiveAt({ creationTime: "no es una fecha" })).toBeNull();
    expect(resolveLastActiveAt(undefined)).toBeNull();
  });
});

describe("addMonths — el recorte de día", () => {
  it("31 de marzo menos un mes cae en febrero, no se desborda a marzo", () => {
    // `setUTCMonth` sin recorte da el 3 de marzo, o sea una cuenta MENOS
    // inactiva de lo que es. Error chico, siempre en la misma dirección, y del
    // lado que retrasa una baja en silencio.
    const r = addMonths(new Date("2026-03-31T00:00:00.000Z"), -1);
    expect(r.toISOString().slice(0, 10)).toBe("2026-02-28");
  });

  it("un mes normal no se toca", () => {
    const r = addMonths(new Date("2026-03-15T00:00:00.000Z"), -1);
    expect(r.toISOString().slice(0, 10)).toBe("2026-02-15");
  });
});

// ── Los plazos ──────────────────────────────────────────────────────────────

describe("el aviso de los 24 meses", () => {
  it("NO avisa a una cuenta con 23 meses de inactividad", async () => {
    const db = installDb({ users: { u1: ATLETA } });
    const { r } = await correr([{ uid: "u1", lastActiveAt: haceMeses(23) }]);
    expect(r.noticed).toBe(0);
    expect(db.mailQueue.size).toBe(0);
    expect(db.noticeWrites).toHaveLength(0);
  });

  it("avisa a los 24 y deja el registro con la señal congelada", async () => {
    const activo = haceMeses(NOTICE_AFTER_MONTHS);
    const db = installDb({ users: { u1: ATLETA } });
    const { r } = await correr([{ uid: "u1", lastActiveAt: activo }]);

    expect(r.noticed).toBe(1);
    expect(db.mailQueue.size).toBe(1);
    const [mail] = [...db.mailQueue.values()];
    expect(mail.kind).toBe("inactive-account-notice");
    expect(mail.toUid).toBe("u1");
    // SIN prefKey: un aviso legal sobre la vida de la cuenta no se apaga desde
    // las preferencias de notificaciones.
    expect(mail.prefKey).toBeUndefined();

    expect(db.noticeWrites).toHaveLength(1);
    expect(db.notices.u1.lastSeenAt.toDate().toISOString())
      .toBe(activo.toISOString());
  });

  it("el mail lleva la fecha REAL de baja, no 'dentro de doce meses'", async () => {
    // Cuenta del backlog: ya tiene 40 meses. La baja NO es dentro de doce
    // meses, es al cumplirse el piso desde el aviso, y el mail tiene que
    // decir eso.
    const db = installDb({ users: { u1: ATLETA } });
    const { r } = await correr([{ uid: "u1", lastActiveAt: haceMeses(40) }]);
    expect(r.noticed).toBe(1);

    // Para 40 meses de inactividad manda el piso desde el aviso, no los 36
    // meses desde la última actividad.
    const esperada = proyeccionDeBaja(haceMeses(40), HOY);
    expect(esperada.getTime())
      .toBe(HOY.getTime() + MIN_NOTICE_AGE_DAYS * 86400000);

    const [mail] = [...db.mailQueue.values()];
    expect(mail.params.deleteOnLabel).toBe(formatShortDateAR(esperada));
    // Y para una cuenta que cruza los 24 con el barrido encendido, manda el
    // otro lado de la fórmula: 36 meses desde la última actividad.
    const normal = proyeccionDeBaja(haceMeses(NOTICE_AFTER_MONTHS), HOY);
    expect(normal.getTime())
      .toBe(addMonths(haceMeses(NOTICE_AFTER_MONTHS), DELETE_AFTER_MONTHS).getTime());
  });

  it("avisa UNA sola vez: la segunda corrida no reencola ni reescribe", async () => {
    const db = installDb({ users: { u1: ATLETA } });
    const cuenta = [{ uid: "u1", lastActiveAt: haceMeses(25) }];

    await correr(cuenta);
    const { r } = await correr(cuenta);

    // El registro de `retention_notices` es la primera barrera; el `create()`
    // de `mail_queue` es la segunda. Alcanza con que UNA funcione, y las dos
    // están puestas porque la que falla en silencio manda mail de verdad.
    expect(r.noticed).toBe(0);
    expect(db.mailQueue.size).toBe(1);
    expect(db.noticeWrites).toHaveLength(1);
  });
});

describe("nunca borra sin aviso previo registrado", () => {
  it("una cuenta de 5 años SIN registro de aviso recibe aviso, no baja", async () => {
    // La aserción más importante del archivo. El spec lo dice literal: nunca
    // borrar sin aviso previo registrado, aunque la cuenta tenga 5 años.
    const db = installDb({ users: { u1: ATLETA } });
    const { r, bajas } = await correr([
      { uid: "u1", lastActiveAt: haceMeses(60) },
    ]);
    expect(bajas).toHaveLength(0);
    expect(r.deleted).toBe(0);
    expect(r.noticed).toBe(1);
    expect(db.mailQueue.size).toBe(1);
  });

  it("un registro de aviso SIN fecha tampoco habilita la baja", async () => {
    // Registro ilegible = no se puede afirmar que tenga 30 días. Falla cerrado.
    const db = installDb({
      users: { u1: ATLETA },
      notices: { u1: { lastSeenAt: Timestamp.fromDate(haceMeses(60)) } },
    });
    const { r, bajas } = await correr([
      { uid: "u1", lastActiveAt: haceMeses(60) },
    ]);
    expect(bajas).toHaveLength(0);
    expect(r.deleted).toBe(0);
    expect(db.mailQueue.size).toBe(0);
  });
});

describe("la baja de los 36 meses", () => {
  const avisoViejo = {
    noticeSentAt: Timestamp.fromDate(haceDias(MIN_NOTICE_AGE_DAYS + 1)),
  };

  it("NO borra a los 35 meses aunque el aviso esté maduro", async () => {
    installDb({ users: { u1: ATLETA }, notices: { u1: avisoViejo } });
    const { r, bajas } = await correr([
      { uid: "u1", lastActiveAt: haceMeses(35) },
    ]);
    expect(bajas).toHaveLength(0);
    expect(r.deleted).toBe(0);
  });

  // ── El piso desde el aviso, por las dos puntas ──────────────────────────
  //
  // Este es EL caso del backlog, y el que justifica que el piso sea 90 y no 30.
  // Una cuenta con 40 meses de inactividad ya cumple la condición de los 36 el
  // día que recibe el aviso: lo único que la separa de la baja es este piso.
  // Un off-by-one acá no se ve en ningún lado — borra a alguien un día antes de
  // lo que le promete su propio mail.
  it("una cuenta del backlog NO se borra un día antes del piso", async () => {
    installDb({
      users: { u1: ATLETA },
      notices: {
        u1: { noticeSentAt: Timestamp.fromDate(haceDias(MIN_NOTICE_AGE_DAYS - 1)) },
      },
    });
    const { r, bajas } = await correr([
      { uid: "u1", lastActiveAt: haceMeses(40) },
    ]);
    expect(bajas).toHaveLength(0);
    expect(r.deleted).toBe(0);
  });

  it("y SÍ el día que el piso se cumple", async () => {
    // La otra punta. Sin esta, un piso roto hacia arriba —que no borra nunca—
    // pasa el test de arriba en verde y el barrido no ejerce jamás.
    installDb({
      users: { u1: ATLETA },
      notices: {
        u1: { noticeSentAt: Timestamp.fromDate(haceDias(MIN_NOTICE_AGE_DAYS)) },
      },
    });
    const { r, bajas } = await correr([
      { uid: "u1", lastActiveAt: haceMeses(40) },
    ]);
    expect(bajas).toHaveLength(1);
    expect(r.deleted).toBe(1);
  });

  it("borra con las DOS condiciones, y firma el audit log aparte", async () => {
    const db = installDb({ users: { u1: ATLETA }, notices: { u1: avisoViejo } });
    const { r, bajas } = await correr([
      { uid: "u1", lastActiveAt: haceMeses(DELETE_AFTER_MONTHS) },
    ]);

    expect(r.deleted).toBe(1);
    expect(bajas).toEqual([
      { uid: "u1", provider: RETENTION_SWEEP_PROVIDER },
    ]);
    // `deletedAt` se escribe ANTES de la cascada: el paso 9 de
    // `runDeleteAccount` se lleva el documento entero. Escribirlo después
    // resucitaría el uid de alguien recién borrado.
    expect(db.noticeWrites).toHaveLength(1);
    expect(db.noticeWrites[0].data.deletedAt).toBeDefined();
  });

  it("una cuenta rota no frena el barrido, y la que sigue sí se procesa", async () => {
    // Sin esta propiedad un solo documento raro congela la retención entera y
    // nadie se entera: el barrido devuelve verde con cero acciones.
    const db = installDb({
      users: { u1: ATLETA, u2: ATLETA },
      userDocFails: new Set(["u1"]),
    });
    const { r } = await correr([
      { uid: "u1", lastActiveAt: haceMeses(30) },
      { uid: "u2", lastActiveAt: haceMeses(30) },
    ]);
    expect(r.errors).toBe(1);
    expect(r.scanned).toBe(2);
    expect(r.noticed).toBe(1);
    expect([...db.mailQueue.values()][0].toUid).toBe("u2");
  });
});

// ── Exclusiones ─────────────────────────────────────────────────────────────

describe("exclusiones — sacan del barrido ENTERO, no sólo de la baja", () => {
  const avisoViejo = {
    noticeSentAt: Timestamp.fromDate(haceDias(MIN_NOTICE_AGE_DAYS + 1)),
  };
  const muyInactiva = { uid: "u1", lastActiveAt: haceMeses(60) };

  it("entrenador: ni aviso ni baja, y queda en el log con su uid", async () => {
    const db = installDb({
      users: { u1: { role: "trainer" } },
      notices: { u1: avisoViejo },
    });
    const { r, bajas } = await correr([muyInactiva]);

    expect(bajas).toHaveLength(0);
    expect(db.mailQueue.size).toBe(0);
    expect(r.excludedTrainers).toBe(1);
    // El spec pide revisión manual, y una revisión manual sobre un contador
    // agregado no se puede hacer: hace falta el uid en el log.
    expect(logger.info).toHaveBeenCalledWith(
      expect.stringContaining("entrenador inactivo"),
      expect.objectContaining({ uid: "u1" }),
    );
  });

  it("suscripción vigente: ni aviso ni baja", async () => {
    const db = installDb({
      users: { u1: { role: "athlete", athleteSubscription: { status: "active" } } },
      notices: { u1: avisoViejo },
    });
    const { r, bajas } = await correr([muyInactiva]);
    expect(bajas).toHaveLength(0);
    expect(db.mailQueue.size).toBe(0);
    expect(r.excludedSubscription).toBe(1);
  });

  it("`grace` también excluye: el cobro falló, la cuenta no está abandonada", async () => {
    const db = installDb({
      users: { u1: { role: "athlete", athleteSubscription: { status: "grace" } } },
    });
    const { r } = await correr([muyInactiva]);
    expect(db.mailQueue.size).toBe(0);
    expect(r.excludedSubscription).toBe(1);
  });

  it("vínculo activo con un PF: ni aviso ni baja", async () => {
    const db = installDb({
      users: { u1: ATLETA },
      linked: new Set(["u1"]),
      notices: { u1: avisoViejo },
    });
    const { r, bajas } = await correr([muyInactiva]);
    expect(bajas).toHaveLength(0);
    expect(db.mailQueue.size).toBe(0);
    expect(r.excludedActiveLink).toBe(1);
  });

  it("una cuenta ACTIVA no gasta la query de vínculos", async () => {
    // El orden de las guardas es por COSTO. Sin esta aserción nada impide que
    // alguien mueva la query arriba y el barrido pase a consultar
    // `trainer_links` una vez por usuario de la base, todos los días.
    const db = installDb({ users: { u1: ATLETA } });
    await correr([{ uid: "u1", lastActiveAt: haceMeses(3) }]);
    expect(db.linkQueries).toHaveLength(0);
  });

  it("una cuenta de Auth sin users/{uid} se saltea y se cuenta", async () => {
    const db = installDb({ users: {} });
    const { r, bajas } = await correr([muyInactiva]);
    expect(bajas).toHaveLength(0);
    expect(db.mailQueue.size).toBe(0);
    expect(r.skippedNoUserDoc).toBe(1);
  });
});

// ── Tope y modo de prueba ───────────────────────────────────────────────────

describe("maxPerRun — el tope de acciones", () => {
  it("corta después de N acciones y lo dice", async () => {
    installDb({
      users: { u1: ATLETA, u2: ATLETA, u3: ATLETA },
    });
    const { r } = await correr(
      ["u1", "u2", "u3"].map((uid) => ({ uid, lastActiveAt: haceMeses(30) })),
      { maxPerRun: 2 },
    );
    expect(r.noticed).toBe(2);
    expect(r.capped).toBe(true);
    expect(r.scanned).toBe(2);
  });
});

describe("dryRun — el modo obligatorio de la primera corrida", () => {
  it("no escribe NADA, pero cuenta lo que haría", async () => {
    const db = installDb({
      users: { u1: ATLETA, u2: ATLETA },
      notices: {
        u2: { noticeSentAt: Timestamp.fromDate(haceDias(MIN_NOTICE_AGE_DAYS + 1)) },
      },
    });
    const { r, bajas } = await correr(
      [
        { uid: "u1", lastActiveAt: haceMeses(25) },
        { uid: "u2", lastActiveAt: haceMeses(40) },
      ],
      { dryRun: true },
    );

    expect(r.noticed).toBe(1);
    expect(r.deleted).toBe(1);
    expect(bajas).toHaveLength(0);
    expect(db.mailQueue.size).toBe(0);
    expect(db.noticeWrites).toHaveLength(0);
  });

  it("el piso entre aviso y baja es el que promete el documento legal", () => {
    // Un test que fija una constante suele ser ruido. Éste no: no está
    // cuidando el número, está cuidando que el número y el documento no se
    // separen.
    //
    // `docs/legal/retencion-y-borrado.md` §6 dice, PUBLICADO al usuario, "entre
    // el aviso y la baja nunca pasan menos de 90 días". Los dos usos que este
    // archivo hace de la constante la toman como SÍMBOLO, así que la suite
    // seguía verde con cualquier valor: bajarla a 7 no ponía nada en rojo.
    // Mientras el número era un detalle de implementación daba igual; desde el
    // 2026-09-14 es la mitad de una promesa legal.
    //
    // Si esto se pone rojo, el arreglo NO es cambiar el 90 de acá: es cambiar
    // la frase de §6 en el mismo commit.
    expect(MIN_NOTICE_AGE_DAYS).toBe(90);
  });

  it("se despliega en dryRun", () => {
    // Trinquete, igual que el interruptor del paywall del alumno. La señal de
    // actividad ya tiene historia, así que la primera corrida ve TODO el
    // backlog de una. Si alguien apaga esto, que rompa este test y lea el
    // encabezado del módulo antes de deployar.
    expect(RETENTION_SWEEP_DRY_RUN).toBe(true);
  });
});
