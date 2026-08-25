/**
 * Unit tests for linkLoadReconcile / linkLoadReconcileHandler (paywall Fase
 * 7, PR4, tasks 1.9-1.10). LOCAL — no emulator, same FakeTx firestore double
 * as promote-link.test.ts (design D-6).
 *
 * Covers:
 *   - the weightedLoad recompute: idempotent, full-recompute (no increments),
 *     error-safe — catches all exceptions and never rethrows (mirrors
 *     link-aggregate.ts's recomputeAthleteCount pattern) so a malformed doc or
 *     a missing users/{trainerId} profile never triggers an Eventarc retry
 *     storm;
 *   - the entitlement reconcile added on top of it, which is what closes the
 *     up-to-24h window between a change in the LINK SET and the 04:00 sweep,
 *     INCLUDING its failure path — the branch that swallows a permanent,
 *     client-reachable breakage;
 *   - TERMINATION of the cycle that reconcile opens — `syncTrainerEntitlements`
 *     writes `trainer_links`, and this trigger fires on every `trainer_links`
 *     write. Those tests COUNT the hops of the simulated cascade instead of
 *     assuming it stops;
 *   - the TRIGGER wrapper: the metric line, the trainerId fallback, and the
 *     guard that skips our own entitlement writes so a downgrade doesn't
 *     fan out into one invocation per blocked link.
 */

jest.mock("firebase-admin", () => {
  // Timestamp/FieldValue hacen falta porque el handler ahora llega a
  // `syncTrainerEntitlements`, que estampa blockedAt y borra los campos al
  // desbloquear. Mismo doble que sync-entitlements.test.ts.
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  const deleteSentinel = { __fakeFieldValue: "delete" };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms }),
  };
  firestore.FieldValue = { delete: () => deleteSentinel };
  // `app()` lo usa el getApp() del trigger; el handler recibe la app por
  // parametro, asi que solo hace falta para los tests del wrapper.
  return { firestore, app: () => ({}) };
});

/**
 * El wrapper se prueba DIRECTO: el doble de `onDocumentWritten` devuelve el
 * handler que recibe, asi que `linkLoadReconcile` ES esa funcion y se la puede
 * invocar con un evento armado a mano. Sin esto el trigger quedaba a 0% —
 * incluida la guarda que decide saltear un evento.
 */
jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentWritten: (_opts: unknown, handler: unknown) => handler,
}));

const warnSpy = jest.fn();
const infoSpy = jest.fn();
const errorSpy = jest.fn();
const debugSpy = jest.fn();
jest.mock("firebase-functions", () => ({
  logger: {
    warn: (...args: unknown[]) => warnSpy(...args),
    info: (...args: unknown[]) => infoSpy(...args),
    error: (...args: unknown[]) => errorSpy(...args),
    debug: (...args: unknown[]) => debugSpy(...args),
  },
}));

import * as admin from "firebase-admin";
import {
  createFakeFirestore,
  FakeCollectionName,
  FakeDoc,
  FakeDocRef,
  FakeFirestore,
  FakeFirestoreState,
  FakeTransaction,
} from "./helpers/fake-tx-firestore";
import {
  isEntitlementOnlyWrite,
  linkLoadReconcile,
  linkLoadReconcileHandler,
} from "../subscriptions/link-load-reconcile";
import { subscriptionChanged } from "../subscriptions/entitlement-triggers";

/** Una escritura observada, en orden. Es lo que hace contables los saltos. */
interface RecordedWrite {
  collection: FakeCollectionName;
  id: string;
  op: "update" | "set";
}

/**
 * Instala el fake firestore envolviendo cada transaccion en un grabador que
 * anota TODA escritura sin cambiar su semantica: `get` sigue delegando en la
 * transaccion real, asi que la guarda de reads-before-writes del doble sigue
 * activa.
 */
function installRecording(seed: Partial<FakeFirestoreState>): {
  state: FakeFirestoreState;
  writes: RecordedWrite[];
} {
  const { db, state } = createFakeFirestore(seed);
  const writes: RecordedWrite[] = [];
  const inner: FakeFirestore["runTransaction"] = db.runTransaction;

  db.runTransaction = <T>(fn: (tx: FakeTransaction) => Promise<T>): Promise<T> =>
    inner<T>((tx) => {
      const recorder = {
        get: (target: Parameters<FakeTransaction["get"]>[0]) => tx.get(target),
        update: (ref: FakeDocRef, data: FakeDoc) => {
          writes.push({ collection: ref.collectionName, id: ref.id, op: "update" });
          tx.update(ref, data);
        },
        set: (ref: FakeDocRef, data: FakeDoc, opts?: { merge?: boolean }) => {
          writes.push({ collection: ref.collectionName, id: ref.id, op: "set" });
          tx.set(ref, data, opts);
        },
      };
      // Doble cast obligado: FakeTransaction tiene estado privado (`wrote`), asi
      // que un objeto estructural no le es asignable aunque cumpla la forma.
      return fn(recorder as unknown as FakeTransaction);
    });

  (admin.firestore as unknown as jest.Mock).mockReturnValue(db);
  return { state, writes };
}

function install(seed: Partial<FakeFirestoreState>): FakeFirestoreState {
  return installRecording(seed).state;
}

const app = {} as admin.app.App;

const ts = (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms });

const link = (athleteId: string, status: string, extra: Record<string, unknown> = {}): FakeDoc => ({
  trainerId: "trainer-1",
  athleteId,
  status,
  entitlement: "entitled",
  ...extra,
});

/** Evento de Eventarc armado a mano, con la forma que el wrapper consume. */
type TriggerEvent = {
  params: { linkId: string };
  data?: {
    before?: { data: () => FakeDoc | undefined };
    after?: { data: () => FakeDoc | undefined };
  };
};
const trigger = linkLoadReconcile as unknown as (event: TriggerEvent) => Promise<void>;
const writtenEvent = (
  linkId: string,
  before: FakeDoc | undefined,
  after: FakeDoc | undefined,
): TriggerEvent => ({
  params: { linkId },
  data: { before: { data: () => before }, after: { data: () => after } },
});

/**
 * Simula la CASCADA de Eventarc: corre el handler y, MIENTRAS la corrida haya
 * escrito en `trainer_links`, lo vuelve a correr — porque esa escritura
 * redispara `linkLoadReconcile`. Devuelve, por salto, cuantos documentos de
 * `trainer_links` se escribieron.
 *
 * Modela la PROFUNDIDAD de la cascada, no su ANCHO: Eventarc entrega un evento
 * por DOCUMENTO, asi que un salto que escribe k vinculos son k invocaciones
 * reales, no una. El ancho lo corta la guarda del wrapper
 * (`isEntitlementOnlyWrite`, con sus propios tests); esto mide que la cadena
 * termine aunque esa guarda no existiera.
 *
 * El tope existe para que un ciclo infinito falle como assert en vez de colgar
 * la suite: si el resultado tiene `maxHops` elementos, la cascada no murio.
 */
async function runCascade(
  writes: RecordedWrite[],
  trainerId: string,
  maxHops = 8,
): Promise<number[]> {
  const linkWritesPerHop: number[] = [];
  for (let hop = 0; hop < maxHops; hop++) {
    writes.length = 0;
    await linkLoadReconcileHandler(app, trainerId);
    const n = writes.filter((w) => w.collection === "trainer_links").length;
    linkWritesPerHop.push(n);
    if (n === 0) break;
  }
  return linkWritesPerHop;
}

describe("linkLoadReconcileHandler", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("recomputes weightedLoad from the live link set (full recompute, not an increment)", async () => {
    const state = install({
      trainer_links: {
        a1: link("a1", "active"),
        a2: link("a2", "active"),
        p1: link("p1", "paused"),
      },
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" }, weightedLoad: 999 } },
    });

    await linkLoadReconcileHandler(app, "trainer-1");

    expect(state.users["trainer-1"].weightedLoad).toBe(2.5);
  });

  it("is idempotent — running twice for equivalent state yields the same value, no drift", async () => {
    const state = install({
      trainer_links: { a1: link("a1", "active"), p1: link("p1", "paused") },
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" } } },
    });

    await linkLoadReconcileHandler(app, "trainer-1");
    const firstRun = state.users["trainer-1"].weightedLoad;
    await linkLoadReconcileHandler(app, "trainer-1");
    const secondRun = state.users["trainer-1"].weightedLoad;

    expect(firstRun).toBe(1.5);
    expect(secondRun).toBe(1.5);
  });

  it("missing users/{trainerId} doc — logs a warning and completes without throwing", async () => {
    install({
      trainer_links: { a1: link("a1", "active") },
      users: {}, // trainer profile absent
    });

    await expect(linkLoadReconcileHandler(app, "trainer-1")).resolves.toBeUndefined();
    expect(warnSpy).toHaveBeenCalledTimes(1);
    // Un solo warn Y ningun error: la segunda llamada NO corrio. Sin este
    // segundo assert, la guarda `if (!loadSynced) return;` queda pinneada por
    // un solo test.
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it("never rethrows on unexpected errors (error-safe, mirrors link-aggregate.ts)", async () => {
    (admin.firestore as unknown as jest.Mock).mockImplementation(() => {
      throw new Error("boom");
    });

    await expect(linkLoadReconcileHandler(app, "trainer-1")).resolves.toBeUndefined();
    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it("over the effective limit it PARKS the excess instead of denying (reconcile is not a gate)", async () => {
    const links: Record<string, FakeDoc> = {};
    for (let i = 0; i < 15; i++) links[`p${i}`] = link(`a${i}`, "paused");
    const state = install({
      trainer_links: links,
      // limite 7, carga cruda 7.5: el excedente no se rechaza, se aparca.
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" } } },
    });

    await expect(linkLoadReconcileHandler(app, "trainer-1")).resolves.toBeUndefined();

    const blocked = Object.values(state.trainer_links).filter((l) => l.entitlement === "blocked");
    expect(blocked).toHaveLength(1);
    // 14 pausados entitled x 0.5 — un `blocked` deja de contar (ADR-5).
    expect(state.users["trainer-1"].weightedLoad).toBe(7);
  });

  // ── el agujero que cierra este slice ───────────────────────────────────────

  it("reconciles entitlements on a LINK-SET change, without waiting for the 04:00 sweep", async () => {
    // Free (2) con 3 activos: hasta esta llamada nada reconciliaba esto antes
    // del barrido, porque `syncEntitlementsOnSubscription` mira SOLO el mapa
    // `subscription` y el mapa no se toco.
    const state = install({
      users: { "trainer-1": {} },
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3: link("a3", "active", { acceptedAt: ts(300) }),
      },
    });

    await linkLoadReconcileHandler(app, "trainer-1");

    // A PROPOSITO no se afirma CUAL vinculo queda aparcado: a quien se
    // conserva lo decide `reconcileEntitlements` y es una politica de producto
    // que vive en select-blocked-links.ts. Lo que este slice tiene que
    // demostrar es que la reconciliacion CORRIO en el mismo evento.
    const blocked = Object.values(state.trainer_links).filter((l) => l.entitlement === "blocked");
    expect(blocked).toHaveLength(1);
    expect(blocked[0].blockedReason).toBe("over-limit");
    expect(state.users["trainer-1"].weightedLoad).toBe(2);
  });

  it("entitlements corre SEGUNDO: el weightedLoad que queda es el YA reconciliado", async () => {
    const { state, writes } = installRecording({
      users: { "trainer-1": {} },
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3: link("a3", "active", { acceptedAt: ts(300) }),
      },
    });

    await linkLoadReconcileHandler(app, "trainer-1");

    // Las dos llamadas escriben users/{trainerId}.weightedLoad: gana la ultima.
    expect(writes.map((w) => `${w.collection}.${w.op}`)).toEqual([
      "users.set", // syncTrainerLoad: carga PREVIA a reconciliar (3.0)
      "trainer_links.update", // syncTrainerEntitlements: aparca el excedente
      "users.set", // ...y reescribe la carga YA reconciliada (2.0)
    ]);
    // 3.0 seria el valor de la primera llamada — que quede 2.0 es la prueba de
    // que la segunda corrio despues y piso el campo.
    expect(state.users["trainer-1"].weightedLoad).toBe(2);
  });

  it("sin perfil del PF no bloquea a nadie ni resucita el users/{trainerId} borrado", async () => {
    // La guarda: `syncTrainerEntitlements` no chequea que el doc exista, y con
    // `subscription` ausente resolveria limite 2 (Free, y NO degradado) — o
    // sea que bloquearia alumnos por un problema de datos NUESTRO. Ademas su
    // set(merge) crearia el doc fantasma. Por eso corre solo si la carga
    // sincronizo, y la carga tira not-found cuando el perfil falta.
    const { state, writes } = installRecording({
      users: {},
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3: link("a3", "active", { acceptedAt: ts(300) }),
      },
    });

    await expect(linkLoadReconcileHandler(app, "trainer-1")).resolves.toBeUndefined();

    expect(writes).toEqual([]);
    expect(state.users["trainer-1"]).toBeUndefined();
    expect(state.trainer_links.L1.entitlement).toBe("entitled");
    expect(state.trainer_links.L2.entitlement).toBe("entitled");
    expect(state.trainer_links.L3.entitlement).toBe("entitled");
  });

  it("un `acceptedAt` mal tipado YA NO voltea la reconciliacion: cae solo el vinculo roto", async () => {
    // HISTORIA, porque el test cambio de signo y conviene que se entienda.
    // `acceptedAt` es alcanzable desde el cliente: firestore.rules no lo pinnea
    // y el `allow update` de trainer_links autoriza a cualquiera de los dos
    // members. Cuando el mapeo de `syncTrainerEntitlements` lo casteaba a
    // Timestamp a ciegas, `acceptedAt.toMillis()` sobre un numero tiraba
    // TypeError y volteaba la transaccion del PF COMPLETO — la misma que usan
    // el barrido de las 04:00 y syncEntitlementsOnSubscription. O sea que UN
    // member le apagaba la reconciliacion al entrenador para TODOS sus alumnos,
    // con un solo write.
    //
    // Ahora `sync-entitlements.ts` lee esa fecha de forma total (readMillis) y
    // degrada a null. Este test pinea que el arreglo llega hasta ACA, que es el
    // camino que el cliente puede disparar.
    const { state, writes } = installRecording({
      users: { "trainer-1": {} }, // Free: limite 2, con 3 activos hay que bloquear
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3: link("a3", "active", { acceptedAt: 1700000000000 }), // el veneno
      },
    });

    await expect(linkLoadReconcileHandler(app, "trainer-1")).resolves.toBeUndefined();

    // Ya no hay error: no se voltea nada.
    expect(errorSpy).not.toHaveBeenCalled();

    // La reconciliacion SI corre, y falla del lado correcto: el faltante vale
    // POSITIVE_INFINITY, asi que el vinculo de la fecha rota es el que cae. El
    // costo lo paga quien rompio su propio dato, no los otros dos alumnos.
    expect(state.trainer_links.L3.entitlement).toBe("blocked");
    expect(state.trainer_links.L1.entitlement).toBe("entitled");
    expect(state.trainer_links.L2.entitlement).toBe("entitled");
    expect(state.users["trainer-1"].blockedAthleteIds).toEqual(["a3"]);
    // Bloquear a a3 baja la carga de 3 a 2, que es el limite Free.
    expect(state.users["trainer-1"].weightedLoad).toBe(2);
    expect(writes.some((w) => w.collection === "trainer_links")).toBe(true);
  });

  it("plan3 (limite null = SIN LIMITE) no bloquea a nadie y devuelve lo que hubiera bloqueado", async () => {
    // `null` es un valor legitimo y viaja hasta el log. `Infinity` no serviria:
    // JSON.stringify(Infinity) da null y rompe en silencio.
    const links: Record<string, FakeDoc> = {};
    for (let i = 0; i < 20; i++) {
      links[`L${i}`] = link(`a${i}`, "active", {
        acceptedAt: ts(100 + i),
        ...(i < 5 ? { entitlement: "blocked" } : {}),
      });
    }
    const state = install({
      users: { "trainer-1": { subscription: { tier: "plan3", status: "active" } } },
      trainer_links: links,
    });

    await linkLoadReconcileHandler(app, "trainer-1");

    const blocked = Object.values(state.trainer_links).filter((l) => l.entitlement === "blocked");
    expect(blocked).toEqual([]);
    expect(state.users["trainer-1"].weightedLoad).toBe(20);
    expect(state.users["trainer-1"].blockedAthleteIds).toEqual([]);
    expect(infoSpy).toHaveBeenCalledWith(
      "linkLoadReconcile: reconciled entitlements",
      expect.objectContaining({ limit: null, blocked: 0, unblocked: 5 }),
    );
  });

  it("con la suscripcion DEGRADADA no bloquea a ningun alumno (la friccion es del PF)", async () => {
    // Un tier que no entendemos es un problema de datos NUESTRO. La valvula de
    // sync-entitlements.ts no revoca nada por eso; el weightedLoad por arriba
    // del limite queda como senal visible.
    const { state, writes } = installRecording({
      users: { "trainer-1": { subscription: { tier: "plan9", status: "active" } } },
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3: link("a3", "active", { acceptedAt: ts(300) }),
      },
    });

    await linkLoadReconcileHandler(app, "trainer-1");

    expect(writes.filter((w) => w.collection === "trainer_links")).toEqual([]);
    const blocked = Object.values(state.trainer_links).filter((l) => l.entitlement === "blocked");
    expect(blocked).toEqual([]);
    expect(state.users["trainer-1"].weightedLoad).toBe(3);
  });

  // ── terminacion del ciclo trainer_links -> trigger -> trainer_links ────────

  it("TERMINACION (bloqueo): la cascada muere en 2 saltos — el segundo no escribe links", async () => {
    const { writes } = installRecording({
      users: { "trainer-1": {} }, // Free: limite 2
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3: link("a3", "active", { acceptedAt: ts(300) }),
      },
    });

    // [1, 0]: el primer salto bloquea UN vinculo (y por eso redispara), el
    // segundo no escribe nada y la cascada muere. Si el array llegara al tope
    // de runCascade, el ciclo seria infinito.
    expect(await runCascade(writes, "trainer-1")).toEqual([1, 0]);
  });

  it("TERMINACION (devolucion): tambien muere en 2 saltos al recuperar cupo", async () => {
    // El otro sentido de la reconciliacion — `unblock` tambien escribe links.
    const { state, writes } = installRecording({
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" } } }, // 7
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100), entitlement: "blocked" }),
        L2: link("a2", "active", { acceptedAt: ts(200), entitlement: "blocked" }),
        L3: link("a3", "active", { acceptedAt: ts(300) }),
      },
    });

    expect(await runCascade(writes, "trainer-1")).toEqual([2, 0]);
    const blocked = Object.values(state.trainer_links).filter((l) => l.entitlement === "blocked");
    expect(blocked).toEqual([]);
  });

  it("TERMINACION (duplicados): un atleta con DOS vinculos vivos tambien converge", async () => {
    // El caso que dejaba un punto fijo ROTO si la decision fuera por vinculo:
    // se bloqueaba el representante y el hermano seguia contando, con el PF
    // por encima del limite para siempre. `reconcileEntitlements` decide por
    // ATLETA y escribe TODOS sus vinculos vivos, asi que el aparcado SI deja
    // de contar — que es lo que afirma el header de link-load-reconcile.ts.
    const { state, writes } = installRecording({
      users: { "trainer-1": {} }, // Free: limite 2
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3a: link("a3", "active", { acceptedAt: ts(300) }),
        L3b: link("a3", "active", { acceptedAt: ts(301) }),
      },
    });

    expect(await runCascade(writes, "trainer-1")).toEqual([2, 0]);
    // La carga QUEDA en el limite, no en 3: ningun vinculo del atleta aparcado
    // sobrevive entitled.
    expect(state.users["trainer-1"].weightedLoad).toBe(2);
    const blocked = Object.values(state.trainer_links).filter((l) => l.entitlement === "blocked");
    expect(blocked).toHaveLength(2);
  });

  it("TERMINACION (users): la escritura de weightedLoad no reabre el ciclo por suscripcion", async () => {
    // El OTRO lado del ciclo: users/{trainerId} dispara
    // `syncEntitlementsOnSubscription`. La guarda que lo corta es
    // `subscriptionChanged`, y se la probamos con el payload REAL que deja
    // este handler, no con uno escrito a mano.
    const seededUser: FakeDoc = {
      subscription: { tier: "plan1", status: "active" },
      weightedLoad: 999,
    };
    const before: FakeDoc = { ...seededUser };
    const links: Record<string, FakeDoc> = {};
    // 8 activos contra un limite de 7: hace falta que la reconciliacion tenga
    // algo que hacer para que el payload sea el de ESTE slice.
    for (let i = 0; i < 8; i++) links[`L${i}`] = link(`a${i}`, "active", { acceptedAt: ts(100 + i) });
    const state = install({ users: { "trainer-1": seededUser }, trainer_links: links });

    await linkLoadReconcileHandler(app, "trainer-1");

    const after = state.users["trainer-1"];
    // No-vacuo, y ademas ATADO A ESTE SLICE: `blockedAthleteIds` lo escribe
    // UNICAMENTE `syncTrainerEntitlements`, o sea la segunda llamada. Sin ella
    // el campo no existe y este assert cae, que es lo que lo separa de un test
    // que pasaria igual en HEAD.
    expect(after.blockedAthleteIds).toEqual(["a7"]);
    expect(after.weightedLoad).toBe(7);
    expect(subscriptionChanged(before, after)).toBe(false);
  });
});

// ── el wrapper del trigger ───────────────────────────────────────────────────

describe("isEntitlementOnlyWrite", () => {
  const base = link("a1", "active", { acceptedAt: ts(100) });

  it("es true cuando SOLO cambian los campos CF-write-only", () => {
    expect(
      isEntitlementOnlyWrite(base, {
        ...base,
        acceptedAt: ts(100), // otro objeto, mismo valor: no es un cambio
        entitlement: "blocked",
        blockedAt: ts(999),
        blockedReason: "over-limit",
      }),
    ).toBe(true);
  });

  it("es true en el sentido inverso (devolucion: se borran blockedAt/blockedReason)", () => {
    const blockedDoc = { ...base, entitlement: "blocked", blockedAt: ts(999), blockedReason: "over-limit" };
    expect(isEntitlementOnlyWrite(blockedDoc, { ...base, entitlement: "entitled" })).toBe(true);
  });

  it("es false si cambia CUALQUIER otro campo, aunque tambien cambie el entitlement", () => {
    expect(isEntitlementOnlyWrite(base, { ...base, status: "paused", entitlement: "blocked" })).toBe(false);
    // `acceptedAt` es escribible por los members y SI mueve la decision.
    expect(isEntitlementOnlyWrite(base, { ...base, acceptedAt: ts(1) })).toBe(false);
  });

  it("es false en un create, en un delete y cuando no cambio nada", () => {
    expect(isEntitlementOnlyWrite(undefined, base)).toBe(false);
    expect(isEntitlementOnlyWrite(base, undefined)).toBe(false);
    expect(isEntitlementOnlyWrite(base, { ...base })).toBe(false);
  });

  it("un campo que no se puede serializar cuenta como distinto y NO tira", () => {
    // Una DocumentReference del Admin SDK es ciclica. Si la comparacion tirara,
    // la excepcion saldria del trigger sin catch y Eventarc reintentaria —
    // justo lo que todo este archivo se cuida de no provocar.
    const cyclic = (): Record<string, unknown> => {
      const o: Record<string, unknown> = { name: "ref" };
      o.self = o;
      return o;
    };
    // Dos objetos DISTINTOS (como los entrega Eventarc): no hay atajo por
    // identidad, la serializacion se intenta de verdad y explota adentro.
    const call = () =>
      isEntitlementOnlyWrite({ ...base, ref: cyclic() }, { ...base, ref: cyclic(), entitlement: "blocked" });
    expect(call).not.toThrow();
    expect(call()).toBe(false);
  });
});

describe("linkLoadReconcile (trigger)", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("SALTEA nuestra propia escritura de entitlement — sin eso, un downgrade se abanica", async () => {
    // El estado esta por encima del limite a proposito: si el handler corriera,
    // escribiria. Que `writes` quede vacio es la prueba de que no corrio.
    const { writes } = installRecording({
      users: { "trainer-1": {} }, // Free: limite 2
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3: link("a3", "active", { acceptedAt: ts(300) }),
      },
    });

    const before = link("a3", "active", { acceptedAt: ts(300) });
    // `acceptedAt` va como OTRO objeto con el mismo valor, igual que lo entrega
    // Eventarc: before y after se deserializan por separado. Comparar por
    // identidad lo leeria como un cambio y la guarda no cortaria nunca.
    const after = link("a3", "active", {
      acceptedAt: ts(300),
      entitlement: "blocked",
      blockedAt: ts(999),
      blockedReason: "over-limit",
    });

    await trigger(writtenEvent("L3", before, after));

    expect(writes).toEqual([]);
    expect(debugSpy).toHaveBeenCalledTimes(1);
  });

  it("NO saltea un cambio de status: ahi si hay que reconciliar", async () => {
    const { state, writes } = installRecording({
      users: { "trainer-1": {} },
      trainer_links: {
        L1: link("a1", "active", { acceptedAt: ts(100) }),
        L2: link("a2", "active", { acceptedAt: ts(200) }),
        L3: link("a3", "active", { acceptedAt: ts(300) }),
      },
    });

    const before = link("a3", "paused", { acceptedAt: ts(300) });
    const after = link("a3", "active", { acceptedAt: ts(300) });

    await trigger(writtenEvent("L3", before, after));

    expect(writes.length).toBeGreaterThan(0);
    expect(state.users["trainer-1"].weightedLoad).toBe(2);
  });

  it("en un DELETE saca el trainerId del `before` y reconcilia igual", async () => {
    const { state } = installRecording({
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" } } },
      trainer_links: { L1: link("a1", "active", { acceptedAt: ts(100) }) },
    });

    await trigger(writtenEvent("L2", link("a2", "active", { acceptedAt: ts(200) }), undefined));

    // El vinculo borrado ya no esta en la coleccion: la carga se recalcula sobre
    // lo que queda vivo. Sin el fallback a `before` no habria trainerId y el
    // trigger saldria por el warn sin recalcular nada.
    expect(state.users["trainer-1"].weightedLoad).toBe(1);
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("sin trainerId en ningun lado avisa y no toca nada", async () => {
    const { writes } = installRecording({
      users: { "trainer-1": {} },
      trainer_links: { L1: link("a1", "active") },
    });

    await trigger(writtenEvent("L9", undefined, { athleteId: "a9", status: "pending" }));

    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(writes).toEqual([]);
  });

  it("emite la metrica M.4 `link-promoted-observed` al entrar en active, y solo ahi", async () => {
    installRecording({
      users: { "trainer-1": { subscription: { tier: "plan1", status: "active" } } },
      trainer_links: { L1: link("a1", "active", { acceptedAt: ts(100) }) },
    });

    await trigger(writtenEvent("L1", link("a1", "pending"), link("a1", "active", { acceptedAt: ts(100) })));

    expect(infoSpy).toHaveBeenCalledWith(
      "linkLoadReconcile: link promoted",
      expect.objectContaining({ event: "link-promoted-observed", linkId: "L1", trainerId: "trainer-1" }),
    );

    // Un active -> active (pausa que no fue, reescritura de otro campo) NO es
    // una promocion: si esto contara, la metrica de adopcion inflaria.
    infoSpy.mockClear();
    await trigger(
      writtenEvent("L1", link("a1", "active", { acceptedAt: ts(100) }), link("a1", "active", { acceptedAt: ts(101) })),
    );
    expect(infoSpy).not.toHaveBeenCalledWith(
      "linkLoadReconcile: link promoted",
      expect.anything(),
    );
  });
});
