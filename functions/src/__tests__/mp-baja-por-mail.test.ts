/**
 * mp-baja-por-mail.test.ts — el Botón de Baja de Servicio, verificado por mail.
 *
 * LOCAL: Firestore en memoria (con transacciones optimistas de verdad, para que
 * la carrera de dos clicks se pueda probar), Auth falso, y el cliente de MP y
 * el reloj por `deps`. La baja que corre adentro es la REAL
 * (`runCancelMySubscription` + reconciliador), no un doble: lo que se prueba es
 * que el token lleve a esa baja y a ninguna otra.
 *
 * Lo que protege, en orden de qué tan caro sale:
 *
 *   1. Que el uid salga del documento del token y NUNCA del request. En MP una
 *      baja no se deshace.
 *   2. Que el token crudo no quede guardado en ningún documento propio.
 *   3. Que la respuesta de la solicitud no distinga cuentas (anti-enumeración).
 *   4. Que un link sirva una sola vez, y que una falla de MP no lo queme.
 */

import { createHash } from "crypto";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
}));

jest.mock("firebase-functions/params", () => ({
  defineSecret: () => ({ value: () => "token-falso" }),
}));

jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: () => ({}),
}));

jest.mock("firebase-functions/v2/https", () => {
  class HttpsError extends Error {
    constructor(readonly code: string, message: string) {
      super(message);
    }
  }
  return { HttpsError, onCall: () => ({}) };
});

jest.mock("firebase-admin/app", () => ({
  getApp: () => ({}),
  initializeApp: () => ({}),
}));

const ts = (ms: number) => ({ toMillis: () => ms, __ts: true });

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: (app: { firestore: () => unknown }) => app.firestore(),
  FieldValue: { serverTimestamp: () => ({ __sentinel: "now" }) },
  Timestamp: {
    fromMillis: (ms: number) => ts(ms),
    fromDate: (d: Date) => ts(d.getTime()),
  },
}));

/** El padrón de Auth: mail → uid. */
const AUTH: Record<string, string> = {};
const getUserByEmail = jest.fn(async (email: string) => {
  const uid = AUTH[email];
  if (!uid) throw Object.assign(new Error("no"), { code: "auth/user-not-found" });
  return { uid, email, providerData: [] };
});

jest.mock("firebase-admin/auth", () => ({
  getAuth: () => ({ getUserByEmail: (e: string) => getUserByEmail(e) }),
}));

import type { App } from "firebase-admin/app";

import {
  BAJAS_POR_MAIL_COLLECTION,
  TOKEN_TTL_MS,
  hashToken,
  runConfirmarBajaPorMail,
  runSolicitarBajaPorMail,
} from "../subscriptions/mp/baja-por-mail";
import { CANCEL_COOLDOWN_MS } from "../subscriptions/mp/cancel-my-subscription";

const AHORA = Date.parse("2026-09-28T12:00:00.000Z");
const DIA_MS = 24 * 60 * 60 * 1000;
const UID = "u1";
const MAIL = "ana@example.com";
const CODE = "BAJA-2026-0A1B2C";

type Doc = Record<string, unknown>;
type Store = Record<string, Record<string, Doc>>;

/**
 * Firestore en memoria. Cada documento lleva una versión; `runTransaction`
 * reintenta si algo que leyó cambió antes de commitear, que es lo que hace el
 * servidor real. Sin eso, la prueba de los dos clicks simultáneos pasaría por
 * construcción.
 */
function fakeApp(seed: Store = {}, opts: { fallaCola?: boolean } = {}) {
  const store: Store = {};
  const version: Record<string, number> = {};
  /** Cada escritura, en orden: `col/id`. */
  const escritas: string[] = [];
  for (const [c, docs] of Object.entries(seed)) {
    store[c] = {};
    for (const [id, d] of Object.entries(docs)) store[c][id] = { ...d };
  }
  const key = (col: string, id: string) => `${col}/${id}`;
  const bump = (col: string, id: string) => {
    version[key(col, id)] = (version[key(col, id)] ?? 0) + 1;
  };
  const write = (col: string, id: string, d: Doc | undefined) => {
    store[col] = store[col] ?? {};
    if (d === undefined) delete store[col][id];
    else store[col][id] = d;
    bump(col, id);
    escritas.push(key(col, id));
  };
  const snapOf = (col: string, id: string) => {
    const d = store[col]?.[id];
    return { id, exists: d !== undefined, data: () => (d ? { ...d } : undefined) };
  };

  const docRef = (col: string, id: string) => ({
    id,
    __col: col,
    get: async () => snapOf(col, id),
    set: async (data: Doc) => {
      write(col, id, { ...(store[col]?.[id] ?? {}), ...data });
    },
    create: async (data: Doc) => {
      if (opts.fallaCola && col === "mail_queue") throw new Error("UNAVAILABLE");
      if (store[col]?.[id] !== undefined) {
        throw Object.assign(new Error("ALREADY_EXISTS"), { code: 6 });
      }
      write(col, id, { ...data });
    },
    update: async (data: Doc) => {
      if (store[col]?.[id] === undefined) throw new Error("NOT_FOUND");
      write(col, id, { ...store[col][id], ...data });
    },
    delete: async () => write(col, id, undefined),
  });
  type Ref = ReturnType<typeof docRef>;

  const filtrada = (col: string, filtros: [string, unknown][]) => ({
    where: (campo: string, _op: string, valor: unknown) =>
      filtrada(col, [...filtros, [campo, valor]]),
    limit: () => filtrada(col, filtros),
    get: async () => {
      const docs = Object.entries(store[col] ?? {})
        .filter(([, d]) => filtros.every(([c, v]) => d[c] === v))
        .map(([id, d]) => ({ id, exists: true, data: () => d }));
      return { empty: docs.length === 0, docs, size: docs.length };
    },
  });

  const runTransaction = async <T>(fn: (tx: unknown) => Promise<T>): Promise<T> => {
    for (let intento = 0; intento < 10; intento++) {
      const leidas: Record<string, number> = {};
      const escrituras: [Ref, Doc][] = [];
      const tx = {
        get: async (ref: Ref) => {
          leidas[key(ref.__col, ref.id)] = version[key(ref.__col, ref.id)] ?? 0;
          // Un tick en el medio: deja que la otra transacción lea también.
          await new Promise((r) => setImmediate(r));
          return snapOf(ref.__col, ref.id);
        },
        update: (ref: Ref, data: Doc) => {
          escrituras.push([ref, data]);
        },
      };
      const r = await fn(tx);
      const conflicto = Object.entries(leidas)
        .some(([k, v]) => (version[k] ?? 0) !== v);
      if (conflicto) continue;
      for (const [ref, data] of escrituras) {
        write(ref.__col, ref.id, { ...(store[ref.__col]?.[ref.id] ?? {}), ...data });
      }
      return r;
    }
    throw new Error("demasiados reintentos");
  };

  const app = {
    firestore: () => ({
      collection: (col: string) => ({
        doc: (id: string) => docRef(col, id),
        where: (campo: string, _op: string, valor: unknown) =>
          filtrada(col, [[campo, valor]]),
      }),
      runTransaction,
    }),
  } as unknown as App;
  return { app, store, escritas };
}

/** Un PF con un plan vivo. */
const MUNDO = (): Store => ({
  users: { [UID]: { role: "trainer", subscription: { tier: "plan2", status: "active" } } },
  mp_plans: { p1: { producto: "trainer", uid: UID, tier: "plan2", cycle: "monthly" } },
});

/** Una suscripción viva en MP, con próximo cobro en 10 días. */
const VIVA = (id: string, uid = UID) => ({
  id,
  status: "authorized",
  external_reference: uid,
  next_payment_date: new Date(AHORA + 10 * DIA_MS).toISOString(),
  auto_recurring: { transaction_amount: 22000 },
  summarized: { pending_charge_quantity: 0 },
});

function fakeMp(
  over: { subs?: Record<string, unknown[]>; fallaBusqueda?: boolean } = {},
  nowMs = AHORA,
) {
  const canceladas: string[] = [];
  const estado: Record<string, Doc[]> = {};
  for (const [plan, subs] of Object.entries(over.subs ?? {})) {
    estado[plan] = subs.map((s) => ({ ...(s as object) }));
  }
  return {
    canceladas,
    deps: {
      nowMs,
      mpClient: {
        getPreapproval: async () => ({}),
        createPreapprovalPlan: async () => ({}),
        searchPreapprovalsByPlan: async (planId: string) => {
          if (over.fallaBusqueda) throw new Error("MP 503");
          return estado[planId] ?? [];
        },
        cancelPreapproval: async (id: string) => {
          canceladas.push(id);
          for (const subs of Object.values(estado)) {
            for (const s of subs) if (s.id === id) s.status = "cancelled";
          }
          return { id, status: "cancelled" };
        },
      },
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any,
  };
}

/** randomBytes fijo: el token del test es conocido de antemano. */
const BYTES = Buffer.alloc(32, 7);
const TOKEN = BYTES.toString("base64url");
const fijo = { nowMs: AHORA, randomBytes: () => BYTES };

const mails = (store: Store, kind?: string) =>
  Object.entries(store.mail_queue ?? {})
    .filter(([, d]) => !kind || d.kind === kind)
    .map(([id, d]) => ({ id, ...d }) as Doc & { id: string; params: Doc });

const bajas = (store: Store) => store[BAJAS_POR_MAIL_COLLECTION] ?? {};

beforeEach(() => {
  jest.clearAllMocks();
  for (const k of Object.keys(AUTH)) delete AUTH[k];
  AUTH[MAIL] = UID;
});

// ---------------------------------------------------------------------------
// La solicitud
// ---------------------------------------------------------------------------
describe("solicitarBajaPorMail — anti-enumeración", () => {
  it("contesta EXACTAMENTE lo mismo para un mail desconocido, sin plan, y válido", async () => {
    const desconocido = fakeApp(MUNDO());
    const sinPlan = fakeApp({ users: { [UID]: { role: "athlete" } } });
    const valido = fakeApp(MUNDO());

    const r1 = await runSolicitarBajaPorMail(desconocido.app, { email: "nadie@x.com" }, fijo);
    const r2 = await runSolicitarBajaPorMail(sinPlan.app, { email: MAIL }, fijo);
    const r3 = await runSolicitarBajaPorMail(valido.app, { email: MAIL }, fijo);

    expect(r1).toEqual({ status: "ok" });
    expect(r2).toEqual(r1);
    expect(r3).toEqual(r1);
    // Y lo que sí cambia queda del lado del servidor: sólo el válido encola.
    expect(mails(desconocido.store)).toHaveLength(0);
    expect(mails(sinPlan.store)).toHaveLength(0);
    expect(Object.keys(bajas(sinPlan.store))).toHaveLength(0);
    expect(mails(valido.store, "service-cancel-confirm")).toHaveLength(1);
  });

  it("input basura también da ok, sin tirar y sin consultar Auth", async () => {
    const { app, store } = fakeApp(MUNDO());
    for (const email of [undefined, null, 42, "", "sin-arroba", "a@b", {}]) {
      await expect(runSolicitarBajaPorMail(app, { email }, fijo))
        .resolves.toEqual({ status: "ok" });
    }
    await expect(
      runSolicitarBajaPorMail(app, undefined as unknown as { email: unknown }, fijo),
    ).resolves.toEqual({ status: "ok" });
    expect(getUserByEmail).not.toHaveBeenCalled();
    expect(mails(store)).toHaveLength(0);
  });

  it("un plan terminado (no por abandono) no dispara mail: mismo filtro que la baja", async () => {
    const mundo = MUNDO();
    mundo.mp_plans.p1.terminal = true;
    const { app, store } = fakeApp(mundo);

    await runSolicitarBajaPorMail(app, { email: MAIL }, fijo);

    expect(mails(store)).toHaveLength(0);
  });
});

describe("solicitarBajaPorMail — el token", () => {
  it("normaliza el mail antes de buscar la cuenta", async () => {
    const { app, store } = fakeApp(MUNDO());

    await runSolicitarBajaPorMail(app, { email: "  Ana@Example.COM " }, fijo);

    expect(getUserByEmail).toHaveBeenCalledWith(MAIL);
    expect(mails(store, "service-cancel-confirm")).toHaveLength(1);
  });

  it("el id del doc es el SHA-256 del token, y el crudo no está en ningún doc propio", async () => {
    const { app, store } = fakeApp(MUNDO());

    await runSolicitarBajaPorMail(app, { email: MAIL, code: CODE }, fijo);

    const sha = createHash("sha256").update(TOKEN).digest("hex");
    expect(hashToken(TOKEN)).toBe(sha);
    expect(Object.keys(bajas(store))).toEqual([sha]);

    // Fuera del outbox —donde `sendQueuedMail` lo borra al enviar— el token no
    // aparece en NINGUNA colección.
    const resto = Object.entries(store).filter(([col]) => col !== "mail_queue");
    expect(resto.length).toBeGreaterThan(0);
    expect(JSON.stringify(resto)).not.toContain(TOKEN);
  });

  it("guarda uid, código, vencimiento a 72 h y usedAt null", async () => {
    const { app, store } = fakeApp(MUNDO());

    await runSolicitarBajaPorMail(app, { email: MAIL, code: CODE }, fijo);

    const d = bajas(store)[hashToken(TOKEN)] as Record<string, { toMillis(): number }>;
    expect(d.uid).toBe(UID);
    expect(d.code).toBe(CODE);
    expect(d.usedAt).toBeNull();
    expect(d.createdAt.toMillis()).toBe(AHORA);
    expect(d.expiresAt.toMillis() - d.createdAt.toMillis()).toBe(72 * 60 * 60 * 1000);
    expect(TOKEN_TTL_MS).toBe(72 * 60 * 60 * 1000);
  });

  it("el mail va al uid, sin prefKey, con el token en el FRAGMENTO de la URL", async () => {
    const { app, store } = fakeApp(MUNDO());

    await runSolicitarBajaPorMail(app, { email: MAIL, code: CODE }, fijo);

    const [m] = mails(store, "service-cancel-confirm");
    expect(m.toUid).toBe(UID);
    expect(m.prefKey).toBeUndefined();
    expect(m.params.actionLink)
      .toBe(`https://gettreino.com/es/baja-de-servicio/confirmar#t=${TOKEN}`);
    expect(m.params.code).toBe(CODE);
  });

  it("un código con otra forma se descarta; uno en minúscula se normaliza", async () => {
    const malo = fakeApp(MUNDO());
    await runSolicitarBajaPorMail(malo.app, { email: MAIL, code: "hola <b>" }, fijo);
    expect(mails(malo.store)[0].params.code).toBeUndefined();
    expect(bajas(malo.store)[hashToken(TOKEN)].code).toBeNull();

    const minus = fakeApp(MUNDO());
    await runSolicitarBajaPorMail(minus.app, { email: MAIL, code: "baja-2026-0a1b2c" }, fijo);
    expect(mails(minus.store)[0].params.code).toBe(CODE);
  });
});

describe("solicitarBajaPorMail — throttle", () => {
  it("dos pedidos en la misma ventana: un mail y un solo token", async () => {
    const { app, store } = fakeApp(MUNDO());
    let n = 0;
    const deps = (nowMs: number) => ({
      nowMs, randomBytes: () => Buffer.alloc(32, ++n),
    });

    await runSolicitarBajaPorMail(app, { email: MAIL }, deps(AHORA));
    await runSolicitarBajaPorMail(app, { email: MAIL }, deps(AHORA + 60_000));

    expect(mails(store, "service-cancel-confirm")).toHaveLength(1);
    expect(Object.keys(bajas(store))).toHaveLength(1);
  });

  it("el pedido frenado por el throttle ni siquiera crea un token", async () => {
    // No alcanza con que el outbox deduplique el mail: sin el chequeo previo,
    // cada pedido de la ventana acuñaría un secreto que no sale en ningún mail.
    const { app, escritas } = fakeApp(MUNDO());
    let n = 0;
    const deps = (nowMs: number) => ({
      nowMs, randomBytes: () => Buffer.alloc(32, ++n),
    });

    await runSolicitarBajaPorMail(app, { email: MAIL }, deps(AHORA));
    const antes = escritas.length;
    await runSolicitarBajaPorMail(app, { email: MAIL }, deps(AHORA + 60_000));

    expect(escritas.slice(antes)).toEqual([]);
  });

  it("si el mail no se pudo encolar, el token se borra: no queda un secreto sin dueño", async () => {
    const { app, store } = fakeApp(MUNDO(), { fallaCola: true });

    await expect(runSolicitarBajaPorMail(app, { email: MAIL }, fijo))
      .resolves.toEqual({ status: "ok" });

    expect(Object.keys(bajas(store))).toEqual([]);
  });

  it("pasada la ventana de 10 minutos sale otro", async () => {
    const { app, store } = fakeApp(MUNDO());
    let n = 0;
    const deps = (nowMs: number) => ({
      nowMs, randomBytes: () => Buffer.alloc(32, ++n),
    });

    await runSolicitarBajaPorMail(app, { email: MAIL }, deps(AHORA));
    await runSolicitarBajaPorMail(app, { email: MAIL }, deps(AHORA + 10 * 60_000));

    expect(mails(store, "service-cancel-confirm")).toHaveLength(2);
    expect(Object.keys(bajas(store))).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
// La confirmación
// ---------------------------------------------------------------------------

/** Un mundo con un link ya pedido. */
async function conLinkPedido(mundo: Store = MUNDO()) {
  const f = fakeApp(mundo);
  await runSolicitarBajaPorMail(f.app, { email: MAIL, code: CODE }, fijo);
  return f;
}

describe("confirmarBajaPorMail — tokens que no sirven", () => {
  it("sin forma, o bien formado pero inexistente: `invalido`, y no se llama a MP", async () => {
    const { app } = await conLinkPedido();
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1")] } });

    for (const token of [undefined, 42, "", "corto", `${TOKEN}x`, "Z".repeat(43)]) {
      expect(await runConfirmarBajaPorMail(app, { token }, mp.deps))
        .toEqual({ status: "invalido" });
    }
    expect(mp.canceladas).toEqual([]);
  });

  it("vencido: `vencido`, no toca MP y no lo quema", async () => {
    const { app, store } = await conLinkPedido();
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1")] } }, AHORA + TOKEN_TTL_MS);

    const r = await runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps);

    expect(r).toEqual({ status: "vencido" });
    expect(mp.canceladas).toEqual([]);
    expect(bajas(store)[hashToken(TOKEN)].usedAt).toBeNull();
  });

  it("un minuto antes del vencimiento todavía sirve", async () => {
    const { app } = await conLinkPedido();
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1")] } }, AHORA + TOKEN_TTL_MS - 60_000);

    expect((await runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps)).status)
      .toBe("dada-de-baja");
  });
});

describe("confirmarBajaPorMail — la baja", () => {
  it("da de baja, devuelve la fecha y encola `service-cancel-done` con código y fecha", async () => {
    const { app, store } = await conLinkPedido();
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1")] } });

    const r = await runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("dada-de-baja");
    expect(Date.parse(r.accesoHastaIso!)).toBe(AHORA + 10 * DIA_MS);
    expect(mp.canceladas).toEqual(["sub-1"]);

    const [m] = mails(store, "service-cancel-done");
    expect(m.toUid).toBe(UID);
    expect(m.prefKey).toBeUndefined();
    expect(m.params).toEqual({ code: CODE, accesoHastaIso: r.accesoHastaIso });
  });

  it("el uid sale del DOCUMENTO: un uid en el request no cambia a quién se da de baja", async () => {
    const mundo = MUNDO();
    mundo.mp_plans.ajeno = { producto: "trainer", uid: "otro", tier: "plan3", cycle: "annual" };
    mundo.users.otro = { role: "trainer", subscription: { tier: "plan3", status: "active" } };
    const { app } = await conLinkPedido(mundo);
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1")], ajeno: [VIVA("sub-ajena", "otro")] } });

    await runConfirmarBajaPorMail(
      app,
      { token: TOKEN, uid: "otro", email: "otro@x.com" } as unknown as { token: unknown },
      mp.deps,
    );

    // LA aserción de seguridad del archivo.
    expect(mp.canceladas).toEqual(["sub-1"]);
  });

  it("un solo uso: el segundo canje da `ya-usado` y MP se llama una vez", async () => {
    const { app, store } = await conLinkPedido();
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1")] } });

    await runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps);
    const segundo = await runConfirmarBajaPorMail(
      app, { token: TOKEN }, { ...mp.deps, nowMs: AHORA + CANCEL_COOLDOWN_MS + 1 },
    );

    expect(segundo).toEqual({ status: "ya-usado" });
    expect(mp.canceladas).toEqual(["sub-1"]);
    expect(mails(store, "service-cancel-done")).toHaveLength(1);
  });

  it("dos clicks SIMULTÁNEOS: uno da de baja, el otro `ya-usado`", async () => {
    const { app } = await conLinkPedido();
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1")] } });

    const rs = await Promise.all([
      runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps),
      runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps),
    ]);

    expect(rs.map((r) => r.status).sort()).toEqual(["dada-de-baja", "ya-usado"]);
    expect(mp.canceladas).toEqual(["sub-1"]);
  });

  it("`sin-suscripcion` deja el token usado y no manda mail de baja", async () => {
    const { app, store } = await conLinkPedido();
    // El plan existe pero no hay suscripción viva detrás.
    const mp = fakeMp({ subs: { p1: [] } });

    const r = await runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps);

    expect(r).toEqual({ status: "sin-suscripcion" });
    expect(bajas(store)[hashToken(TOKEN)].usedAt).not.toBeNull();
    expect(mails(store, "service-cancel-done")).toHaveLength(0);
    expect(await runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps))
      .toEqual({ status: "ya-usado" });
  });
});

describe("confirmarBajaPorMail — cuando MP no contesta, el link NO se quema", () => {
  it("`no-disponible` libera el reclamo, y el reintento con el mismo link funciona", async () => {
    const { app, store } = await conLinkPedido();

    const caido = fakeMp({ fallaBusqueda: true });
    const r1 = await runConfirmarBajaPorMail(app, { token: TOKEN }, caido.deps);
    expect(r1).toEqual({ status: "no-disponible" });
    expect(bajas(store)[hashToken(TOKEN)].usedAt).toBeNull();
    expect(mails(store, "service-cancel-done")).toHaveLength(0);

    // Pasado el cooldown de la baja (10 s), MP ya contesta.
    const vuelto = fakeMp(
      { subs: { p1: [VIVA("sub-1")] } }, AHORA + CANCEL_COOLDOWN_MS + 1,
    );
    const r2 = await runConfirmarBajaPorMail(app, { token: TOKEN }, vuelto.deps);

    expect(r2.status).toBe("dada-de-baja");
    expect(vuelto.canceladas).toEqual(["sub-1"]);
  });

  it("el cooldown de 10 s también libera, en vez de contestar `sin-suscripcion`", async () => {
    // Si se mapeara el `enfriando` a `sin-suscripcion`, la persona leería «no
    // tenías nada que dar de baja» con la suscripción viva, y el link quemado.
    const mundo = MUNDO();
    mundo.mp_cancelaciones = { [UID]: { lastCancelMs: AHORA - 1_000 } };
    const { app, store } = await conLinkPedido(mundo);
    const mp = fakeMp({ subs: { p1: [VIVA("sub-1")] } });

    const r = await runConfirmarBajaPorMail(app, { token: TOKEN }, mp.deps);

    expect(r).toEqual({ status: "no-disponible" });
    expect(mp.canceladas).toEqual([]);
    expect(bajas(store)[hashToken(TOKEN)].usedAt).toBeNull();
  });
});
