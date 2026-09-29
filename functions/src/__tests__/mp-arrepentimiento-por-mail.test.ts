/**
 * mp-arrepentimiento-por-mail.test.ts — el Botón de Arrepentimiento, verificado
 * por mail y con el plazo decidido por NUESTRO registro.
 *
 * LOCAL: Firestore en memoria (con transacciones optimistas de verdad), Auth
 * falso, y el cliente de MP y el reloj por `deps`. La cancelación que corre
 * adentro es la REAL (`runCancelMySubscription` + reconciliador).
 *
 * Lo que protege, en orden de qué tan caro sale:
 *
 *   1. Que la FECHA salga de Mercado Pago y no del formulario. Con la del
 *      formulario, un pedido de hace tres meses entra como «de ayer».
 *   2. Que sólo se cancele DENTRO de plazo. Cancelar es irreversible, y fuera de
 *      plazo el usuario tiene la baja, que conserva el acceso.
 *   3. Que un aviso al equipo perdido NO se pierda en silencio: la devolución es
 *      manual, y si nadie sabe que hay una, no se hace.
 *   4. Que un link de baja no sirva de arrepentimiento, ni al revés.
 *   5. Que en la franja del último día —donde un feriado pudo correr el plazo—
 *      no se rechace ni se apruebe solo: lo decide una persona.
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

/** El padrón de Auth: mail → uid, y uid → mail. */
const AUTH: Record<string, string> = {};
const getUserByEmail = jest.fn(async (email: string) => {
  const uid = AUTH[email];
  if (!uid) throw Object.assign(new Error("no"), { code: "auth/user-not-found" });
  return { uid, email, providerData: [] };
});
const getUser = jest.fn(async (uid: string) => {
  const email = Object.keys(AUTH).find((e) => AUTH[e] === uid);
  if (!email) throw Object.assign(new Error("no"), { code: "auth/user-not-found" });
  return { uid, email };
});

jest.mock("firebase-admin/auth", () => ({
  getAuth: () => ({
    getUserByEmail: (e: string) => getUserByEmail(e),
    getUser: (u: string) => getUser(u),
  }),
}));

import {
  ARREPENTIMIENTOS_POR_MAIL_COLLECTION,
  EQUIPO_MAILBOX,
  contratoMasReciente,
  normalizarCodigoArrepentimiento,
  runConfirmarArrepentimientoPorMail,
  runSolicitarArrepentimientoPorMail,
} from "../subscriptions/mp/arrepentimiento-por-mail";
import {
  BAJAS_POR_MAIL_COLLECTION,
  TOKEN_TTL_MS,
  hashToken,
  runConfirmarBajaPorMail,
} from "../subscriptions/mp/baja-por-mail";
import {
  CANCEL_COOLDOWN_MS,
  runCancelMySubscription,
} from "../subscriptions/mp/cancel-my-subscription";
import { CAMPO_ARREPENTIDO, reconcileSubscription } from "../subscriptions/mp/reconcile";
import { effectiveWeightLimit } from "../subscriptions/effective-limit";
import { Doc, Store, fakeApp } from "./helpers/firestore-en-memoria";

// Miércoles 30/09/2026, 12:00 en Argentina.
const AHORA = Date.parse("2026-09-30T15:00:00.000Z");
const DIA_MS = 24 * 60 * 60 * 1000;
const UID = "u1";
const OTRO_UID = "u2";
const MAIL = "ana@example.com";
const CODE = "ARR-2026-0A1B2C";

/** Hace `dias` días, a la misma hora. */
const haceDias = (dias: number) => new Date(AHORA - dias * DIA_MS).toISOString();

/** Un PF con un plan. */
const MUNDO = (): Store => ({
  users: { [UID]: { role: "trainer", subscription: { tier: "plan2", status: "active" } } },
  mp_plans: { p1: { producto: "trainer", uid: UID, tier: "plan2", cycle: "monthly" } },
});

/** Una suscripción autorizada en MP, contratada hace `dias` días. */
const SUB = (id: string, dias: number, extra: Doc = {}) => ({
  id,
  status: "authorized",
  external_reference: UID,
  date_created: haceDias(dias),
  next_payment_date: new Date(AHORA + (30 - dias) * DIA_MS).toISOString(),
  auto_recurring: { transaction_amount: 22000 },
  summarized: { pending_charge_quantity: 0, charged_quantity: 1 },
  ...extra,
});

function fakeMp(
  over: {
    subs?: Record<string, unknown[]>;
    fallaBusqueda?: boolean;
    /** La búsqueda tira a partir de la llamada N (1-based). */
    fallaBusquedaDesde?: number;
    fallaBaja?: boolean;
    /**
     * La búsqueda devuelve SIEMPRE el estado del principio, como hace Mercado
     * Pago durante unos segundos después de cancelar (medido en el sandbox: a los
     * 0 s la búsqueda decía `authorized` y la lectura por id `cancelled`).
     */
    busquedaVieja?: boolean;
    /** La lectura por id tira. */
    fallaPorId?: boolean;
  } = {},
  nowMs = AHORA,
) {
  const canceladas: string[] = [];
  let busquedas = 0;
  const estado: Record<string, Doc[]> = {};
  for (const [plan, subs] of Object.entries(over.subs ?? {})) {
    estado[plan] = subs.map((s) => ({ ...(s as object) }));
  }
  /** Lo que ve la búsqueda cuando está desactualizada: el estado inicial. */
  const foto: Record<string, Doc[]> = JSON.parse(JSON.stringify(estado));
  return {
    canceladas,
    deps: {
      nowMs,
      mpClient: {
        // La lectura por id es CONSISTENTE: refleja la cancelación al instante.
        getPreapproval: async (id: string) => {
          if (over.fallaPorId) throw new Error("MP 503");
          for (const [planId, subs] of Object.entries(estado)) {
            const s = subs.find((x) => x.id === id);
            if (s) return { ...s, preapproval_plan_id: planId };
          }
          throw new Error(`MP 404: ${id}`);
        },
        createPreapprovalPlan: async () => ({}),
        searchPreapprovalsByPlan: async (planId: string) => {
          busquedas += 1;
          if (over.fallaBusqueda) throw new Error("MP 503");
          if (over.fallaBusquedaDesde !== undefined && busquedas >= over.fallaBusquedaDesde) {
            throw new Error("MP 503");
          }
          return (over.busquedaVieja ? foto : estado)[planId] ?? [];
        },
        cancelPreapproval: async (id: string) => {
          if (over.fallaBaja) throw new Error("MP 503");
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
const BYTES = Buffer.alloc(32, 9);
const TOKEN = BYTES.toString("base64url");
const fijo = { nowMs: AHORA, randomBytes: () => BYTES };

const mails = (store: Store, kind?: string) =>
  Object.entries(store.mail_queue ?? {})
    .filter(([, d]) => !kind || d.kind === kind)
    .map(([id, d]) => ({ id, ...d }) as Doc & { id: string; params: Doc });

const tokens = (store: Store) => store[ARREPENTIMIENTOS_POR_MAIL_COLLECTION] ?? {};

beforeEach(() => {
  jest.clearAllMocks();
  for (const k of Object.keys(AUTH)) delete AUTH[k];
  AUTH[MAIL] = UID;
});

/** Arma el mundo, pide el link, y devuelve todo listo para confirmar. */
async function conLinkPedido(
  mundo: Store,
  mp = fakeMp({ subs: { p1: [SUB("s1", 3)] } }),
) {
  const fake = fakeApp(mundo);
  await runSolicitarArrepentimientoPorMail(fake.app, { email: MAIL, code: CODE }, fijo);
  return { ...fake, mp };
}

// ---------------------------------------------------------------------------
// La solicitud
// ---------------------------------------------------------------------------
describe("solicitarArrepentimientoPorMail", () => {
  it("anti-enumeración: mail desconocido, sin plan y válido contestan LO MISMO", async () => {
    const desconocido = fakeApp(MUNDO());
    const sinPlan = fakeApp({ users: { [UID]: { role: "athlete" } } });
    const valido = fakeApp(MUNDO());

    const r1 = await runSolicitarArrepentimientoPorMail(desconocido.app, { email: "nadie@x.com" }, fijo);
    const r2 = await runSolicitarArrepentimientoPorMail(sinPlan.app, { email: MAIL }, fijo);
    const r3 = await runSolicitarArrepentimientoPorMail(valido.app, { email: MAIL }, fijo);

    expect(r1).toEqual({ status: "ok" });
    expect(r2).toEqual(r1);
    expect(r3).toEqual(r1);
    expect(mails(desconocido.store)).toHaveLength(0);
    expect(mails(sinPlan.store)).toHaveLength(0);
    expect(mails(valido.store, "withdrawal-confirm")).toHaveLength(1);
  });

  it("⚠️ un plan TERMINAL también recibe el mail: darse de baja no le quita el arrepentimiento", async () => {
    // La baja no devuelve plata. Con el filtro de la baja (`planesQueCobran`,
    // que excluye lo terminal) esta persona no recibía ni el mail.
    const mundo = MUNDO();
    mundo.mp_plans.p1.terminal = true;
    const { app, store } = fakeApp(mundo);

    await runSolicitarArrepentimientoPorMail(app, { email: MAIL }, fijo);

    expect(mails(store, "withdrawal-confirm")).toHaveLength(1);
  });

  it("input basura también da ok, sin tirar y sin consultar Auth", async () => {
    const { app, store } = fakeApp(MUNDO());
    for (const email of [undefined, null, 42, "", "sin-arroba", "a@b", {}]) {
      await expect(runSolicitarArrepentimientoPorMail(app, { email }, fijo))
        .resolves.toEqual({ status: "ok" });
    }
    await expect(
      runSolicitarArrepentimientoPorMail(app, undefined as unknown as { email: unknown }, fijo),
    ).resolves.toEqual({ status: "ok" });
    expect(getUserByEmail).not.toHaveBeenCalled();
    expect(mails(store)).toHaveLength(0);
  });

  it("⚠️ el token vive en SU colección, no en la de la baja", async () => {
    const { app, store } = fakeApp(MUNDO());

    await runSolicitarArrepentimientoPorMail(app, { email: MAIL, code: CODE }, fijo);

    const sha = createHash("sha256").update(TOKEN).digest("hex");
    expect(Object.keys(tokens(store))).toEqual([sha]);
    expect(store[BAJAS_POR_MAIL_COLLECTION]).toBeUndefined();
    expect(tokens(store)[sha]).toMatchObject({ uid: UID, code: CODE, usedAt: null });
  });

  it("el link va a la página de confirmación de ARREPENTIMIENTO, en el fragmento", async () => {
    const { app, store } = fakeApp(MUNDO());

    await runSolicitarArrepentimientoPorMail(app, { email: MAIL, code: CODE }, fijo);

    const [mail] = mails(store, "withdrawal-confirm");
    expect(mail.params.actionLink).toBe(
      `https://gettreino.com/es/arrepentimiento/confirmar#t=${TOKEN}`,
    );
    expect(mail.params.code).toBe(CODE);
  });

  it("el código: normaliza a mayúsculas y descarta lo que no tiene su forma", async () => {
    expect(normalizarCodigoArrepentimiento(" arr-2026-0a1b2c ")).toBe(CODE);
    // El código de una BAJA no es un código de arrepentimiento.
    expect(normalizarCodigoArrepentimiento("BAJA-2026-0A1B2C")).toBeNull();
    expect(normalizarCodigoArrepentimiento("ARR-2026-XYZ")).toBeNull();
    expect(normalizarCodigoArrepentimiento("Hola <script>")).toBeNull();
    expect(normalizarCodigoArrepentimiento(42)).toBeNull();
  });

  it("throttle: dos pedidos de la misma ventana dejan UN mail y UN token", async () => {
    const { app, store } = fakeApp(MUNDO());
    let n = 0;
    const distintos = { nowMs: AHORA, randomBytes: () => Buffer.alloc(32, ++n) };

    await runSolicitarArrepentimientoPorMail(app, { email: MAIL }, distintos);
    await runSolicitarArrepentimientoPorMail(app, { email: MAIL }, distintos);

    expect(mails(store, "withdrawal-confirm")).toHaveLength(1);
    expect(Object.keys(tokens(store))).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// El plazo decide qué pasa
// ---------------------------------------------------------------------------
describe("confirmarArrepentimientoPorMail — DENTRO de plazo", () => {
  it("corta la suscripción, avisa al equipo con todo lo necesario y le contesta al usuario", async () => {
    const { app, store, mp } = await conLinkPedido(MUNDO());

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r).toEqual({ status: "recibido" });
    expect(mp.canceladas).toEqual(["s1"]);

    // Al equipo, a la casilla literal y no a un uid.
    const [aviso] = mails(store, "withdrawal-team-notice");
    expect(aviso).toMatchObject({ toAddress: EQUIPO_MAILBOX, toUid: "", status: "pending" });
    expect(aviso.params).toMatchObject({
      estado: "dentro",
      code: CODE,
      email: MAIL,
      uid: UID,
      monto: 22000,
      cobros: 1,
      suscripciones: "s1",
      canceladas: 1,
      diasTranscurridos: 3,
    });

    // Al usuario, con su código y sin la variante de revisión.
    const [aUsuario] = mails(store, "withdrawal-received");
    expect(aUsuario.toUid).toBe(UID);
    expect(aUsuario.params).toEqual({ code: CODE });
  });

  it("⚠️ la fecha sale de MERCADO PAGO: un dato del formulario no la mueve", async () => {
    // Contrató hace 40 días. Aunque el pedido diga que fue «hoy», manda MP.
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("s1", 40)] } }),
    );

    const r = await runConfirmarArrepentimientoPorMail(
      app,
      { token: TOKEN, purchaseDate: haceDias(0), fecha: "hoy" } as never,
      mp.deps,
    );

    expect(r.status).toBe("fuera-de-plazo");
    expect(mp.canceladas).toEqual([]);
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(0);
  });

  it("⚠️ quien ya se dio de baja dentro de los 10 días igual puede arrepentirse", async () => {
    // La baja NO devuelve plata; el arrepentimiento sí. Que ya no haya nada que
    // cortar no le quita el derecho, y el equipo igual tiene que devolver.
    //
    // Y el plan queda TERMINAL, que es lo que deja una baja confirmada por MP
    // (`reconcile.ts`). Un fake sin ese flag hacía pasar este test mientras en
    // producción `planesQueCobran` dejaba a esa persona sin ni siquiera el mail.
    const mundo = MUNDO();
    mundo.mp_plans.p1.terminal = true;
    const { app, store, mp } = await conLinkPedido(
      mundo,
      fakeMp({ subs: { p1: [SUB("s1", 3, { status: "cancelled" })] } }),
    );

    expect(mails(store, "withdrawal-confirm")).toHaveLength(1);

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("recibido");
    expect(mp.canceladas).toEqual([]);
    const [aviso] = mails(store, "withdrawal-team-notice");
    expect(aviso.params).toMatchObject({ estado: "dentro", canceladas: 0 });
  });

  it("si cambió de plan, cuenta la contratación MÁS RECIENTE y lista todas las suscripciones", async () => {
    // La vieja tiene 40 días (fuera de plazo); la nueva, 3. Se arrepiente de la
    // nueva, y el equipo ve las dos para decidir qué devolver.
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("vieja", 40, { status: "cancelled" }), SUB("nueva", 3)] } }),
    );

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("recibido");
    expect(mp.canceladas).toEqual(["nueva"]);
    const [aviso] = mails(store, "withdrawal-team-notice");
    expect(aviso.params.suscripciones).toBe("vieja, nueva");
  });
});

describe("confirmarArrepentimientoPorMail — FUERA de plazo", () => {
  it("⚠️ no cancela nada, no avisa al equipo, y le dice al usuario que venció", async () => {
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("s1", 40)] } }),
    );

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("fuera-de-plazo");
    // El último día fue el 31/08 (contrató el 21/08): la página lo muestra.
    expect(r.ultimoDiaIso).toBe("2026-08-31T03:00:00.000Z");
    expect(mp.canceladas).toEqual([]);
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(0);
    const [aviso] = mails(store, "withdrawal-expired");
    expect(aviso.toUid).toBe(UID);
    expect(aviso.params).toEqual({ code: CODE, ultimoDiaIso: "2026-08-31T03:00:00.000Z" });
  });

  it("el link queda usado: no se puede reintentar hasta que «cuele» un plazo que no es", async () => {
    const { app, mp } = await conLinkPedido(MUNDO(), fakeMp({ subs: { p1: [SUB("s1", 40)] } }));

    await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);
    const otra = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(otra.status).toBe("ya-usado");
  });
});

// ---------------------------------------------------------------------------
// Los beneficios terminan en el momento en que se confirma
//
// Es lo que separa el arrepentimiento de la baja: la baja conserva el acceso
// hasta el fin del período pagado; el arrepentimiento devuelve TODO lo pagado,
// así que no queda acceso gratis.
// ---------------------------------------------------------------------------
describe("confirmarArrepentimientoPorMail — el acceso termina en el acto", () => {
  /** El PF tal como queda en Firestore, listo para preguntarle su límite. */
  const limiteDe = (store: Store, nowMs: number) => {
    const sub = store.users[UID].subscription as Record<string, unknown>;
    const fin = (sub.currentPeriodEnd as { toMillis: () => number } | null)?.toMillis() ?? null;
    return effectiveWeightLimit(
      { tier: sub.tier, status: sub.status, currentPeriodEndMs: fin } as never,
      nowMs,
    );
  };
  const GRATIS = effectiveWeightLimit(null, AHORA);

  it("PF: el fin de período pasa a ser el momento de la confirmación", async () => {
    const { app, store, mp } = await conLinkPedido(MUNDO());
    // Antes de arrepentirse el PF tiene su plan: el límite es el del plan2.
    expect(limiteDe(store, AHORA)).not.toBe(GRATIS);

    await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    const sub = store.users[UID].subscription as Record<string, unknown>;
    expect(sub.status).toBe("cancelled");
    expect((sub.currentPeriodEnd as { toMillis: () => number }).toMillis()).toBe(AHORA);
    expect(sub.prepaidTier).toBeNull();
    expect(sub.prepaidUntil).toBeNull();
    // Y lo que importa: el límite efectivo es el del plan gratis.
    expect(limiteDe(store, AHORA + 1)).toBe(GRATIS);
    expect(store.mp_plans.p1[CAMPO_ARREPENTIDO]).toBe(AHORA);
  });

  it("⚠️ un evento posterior de MP NO le devuelve el acceso", async () => {
    // Sin el marcador, cada reconciliación —el evento de MP por esta misma
    // cancelación, el barrido de las 03:00— volvería a calcular «cancelado, con
    // período hasta el día X» y a devolvérselo.
    const { app, store, mp } = await conLinkPedido(MUNDO());
    await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    const despues = { ...mp.deps, nowMs: AHORA + 2 * DIA_MS };
    await reconcileSubscription(app, "p1", despues);
    await reconcileSubscription(app, "p1", despues);

    const sub = store.users[UID].subscription as Record<string, unknown>;
    expect((sub.currentPeriodEnd as { toMillis: () => number }).toMillis()).toBe(AHORA);
    expect(limiteDe(store, AHORA + 2 * DIA_MS)).toBe(GRATIS);
  });

  it("alumno: el derecho pasa a expired en el acto y sigue así", async () => {
    const mundo: Store = {
      users: { [UID]: { role: "athlete", athleteSubscription: { status: "active" } } },
      mp_plans: { p1: { producto: "athlete", uid: UID, cycle: "monthly" } },
    };
    const { app, store, mp } = await conLinkPedido(
      mundo,
      fakeMp({ subs: { p1: [SUB("s1", 3, { auto_recurring: { transaction_amount: 3500 } })] } }),
    );

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("recibido");
    expect(store.users[UID].athleteSubscription).toEqual({ status: "expired" });
    // Un evento posterior no se lo devuelve.
    await reconcileSubscription(app, "p1", { ...mp.deps, nowMs: AHORA + DIA_MS });
    expect(store.users[UID].athleteSubscription).toEqual({ status: "expired" });
  });

  it("CONTROL: una baja común, en cambio, conserva el acceso hasta el fin del período", async () => {
    // Es lo que este test protege de mezclarse: la baja NO devuelve plata, y por
    // eso el alumno sigue teniendo lo que pagó.
    const mundo: Store = {
      users: { [UID]: { role: "athlete", athleteSubscription: { status: "active" } } },
      mp_plans: { p1: { producto: "athlete", uid: UID, cycle: "monthly" } },
    };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp({ subs: { p1: [SUB("s1", 3, { auto_recurring: { transaction_amount: 3500 } })] } });

    await runCancelMySubscription(app, UID, mp.deps);

    expect(mp.canceladas).toEqual(["s1"]);
    expect(store.users[UID].athleteSubscription).toEqual({ status: "active" });
    expect(store.mp_plans.p1[CAMPO_ARREPENTIDO]).toBeUndefined();
  });

  it("⚠️ el momento es el de la PRIMERA confirmación: un reintento no lo mueve", async () => {
    // El corte falla porque MP no contesta al reconciliar (búsqueda #4: la 1ª es
    // la del arrepentimiento, la 2ª y 3ª las de la cancelación). El marcador ya
    // quedó escrito; el reintento, más tarde, lo termina de aplicar.
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("s1", 3)] }, fallaBusquedaDesde: 4 }),
    );

    const primero = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(primero.status).toBe("no-disponible");
    expect(tokens(store)[hashToken(TOKEN)].usedAt).toBeNull();
    // La obligación ya está registrada, aunque el corte no se aplicó todavía.
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(1);
    expect(store.mp_plans.p1[CAMPO_ARREPENTIDO]).toBe(AHORA);

    const reintento = fakeMp({ subs: { p1: [SUB("s1", 3, { status: "cancelled" })] } });
    const segundo = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, {
      ...reintento.deps,
      nowMs: AHORA + CANCEL_COOLDOWN_MS + 1,
    });

    expect(segundo.status).toBe("recibido");
    expect(store.mp_plans.p1[CAMPO_ARREPENTIDO]).toBe(AHORA);
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(1);
    const sub = store.users[UID].subscription as Record<string, unknown>;
    expect((sub.currentPeriodEnd as { toMillis: () => number }).toMillis()).toBe(AHORA);
  });

  it("⚠️ el corte lee la suscripción POR ID: una búsqueda desactualizada no lo desarma (PF)", async () => {
    // Producción, 2026-09-29: el trámite corrió bien y el alumno siguió `active`.
    // `/preapproval/search` devuelve el estado viejo justo después de cancelar, y
    // el marcador sólo vale con `cancelled`: el reconciliador veía una
    // suscripción viva y lo ignoraba. Con la búsqueda al día este test pasaba —y
    // pasó, sin ver el bug, hasta que se probó contra Mercado Pago de verdad.
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("s1", 3)] }, busquedaVieja: true }),
    );

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("recibido");
    expect(mp.canceladas).toEqual(["s1"]);
    const sub = store.users[UID].subscription as Record<string, unknown>;
    expect(sub.status).toBe("cancelled");
    expect((sub.currentPeriodEnd as { toMillis: () => number }).toMillis()).toBe(AHORA);
    expect(limiteDe(store, AHORA + 1)).toBe(GRATIS);
  });

  it("⚠️ el corte lee la suscripción POR ID: una búsqueda desactualizada no lo desarma (alumno)", async () => {
    const mundo: Store = {
      users: { [UID]: { role: "athlete", athleteSubscription: { status: "active" } } },
      mp_plans: { p1: { producto: "athlete", uid: UID, cycle: "monthly" } },
    };
    const { app, store, mp } = await conLinkPedido(
      mundo,
      fakeMp({
        subs: { p1: [SUB("s1", 3, { auto_recurring: { transaction_amount: 3500 } })] },
        busquedaVieja: true,
      }),
    );

    await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(store.users[UID].athleteSubscription).toEqual({ status: "expired" });
  });

  it("si MP no contesta la lectura por id, el corte no se aplicó y el link sigue sirviendo", async () => {
    // El marcador ya quedó escrito y la obligación de devolver ya está avisada;
    // lo que falta es aplicar el corte, y el reintento lo termina.
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("s1", 3)] }, fallaPorId: true }),
    );

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("no-disponible");
    expect(tokens(store)[hashToken(TOKEN)].usedAt).toBeNull();
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(1);
    expect(store.mp_plans.p1[CAMPO_ARREPENTIDO]).toBe(AHORA);
  });

  it("⚠️ un marcador con la suscripción todavía VIVA no corta: es una cancelación que falló", async () => {
    // El marcador sólo vale con `cancelled`. Si MP sigue diciendo `authorized`
    // la suscripción sigue cobrando, y cortarle el acceso a quien está pagando
    // sería peor que no cortarlo: el reintento la cancela y ahí sí corta.
    const mundo = MUNDO();
    mundo.mp_plans.p1[CAMPO_ARREPENTIDO] = AHORA;
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp({ subs: { p1: [SUB("s1", 3)] } });

    await reconcileSubscription(app, "p1", mp.deps);

    const sub = store.users[UID].subscription as Record<string, unknown>;
    expect(sub.status).toBe("active");
    expect(limiteDe(store, AHORA)).not.toBe(GRATIS);
    // Ni mueve el fin de período al momento del marcador: sigue siendo el que
    // dice Mercado Pago.
    expect((sub.currentPeriodEnd as { toMillis: () => number }).toMillis()).not.toBe(AHORA);
  });

  it("⚠️ alumno: un marcador con la suscripción todavía VIVA tampoco corta", async () => {
    const mundo: Store = {
      users: { [UID]: { role: "athlete", athleteSubscription: { status: "active" } } },
      mp_plans: { p1: { producto: "athlete", uid: UID, cycle: "monthly", [CAMPO_ARREPENTIDO]: AHORA } },
    };
    const { app, store } = fakeApp(mundo);
    const mp = fakeMp({ subs: { p1: [SUB("s1", 3, { auto_recurring: { transaction_amount: 3500 } })] } });

    await reconcileSubscription(app, "p1", mp.deps);

    expect(store.users[UID].athleteSubscription).toEqual({ status: "active" });
  });

  it("⚠️ el resto prepago de un plan ANTERIOR se conserva, y el aviso al equipo lo advierte", async () => {
    // Es plata YA PAGADA que este arrepentimiento no devuelve (el pedido es del
    // plan más reciente): quitársela sería revocar algo que sí pagó. Si el equipo
    // devuelve también ese pago, tiene que quitarlo a mano — por eso el aviso
    // lo dice.
    const hasta = AHORA + 20 * DIA_MS;
    const mundo = MUNDO();
    mundo.mp_plans.p1.tier = "plan1";
    mundo.users[UID].subscription = {
      tier: "plan1",
      status: "active",
      prepaidTier: "plan3",
      prepaidUntil: ts(hasta),
    };
    const { app, store, mp } = await conLinkPedido(mundo);

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("recibido");
    const sub = store.users[UID].subscription as Record<string, unknown>;
    expect(sub.prepaidTier).toBe("plan3");
    expect((sub.prepaidUntil as { toMillis: () => number }).toMillis()).toBe(hasta);
    const [aviso] = mails(store, "withdrawal-team-notice");
    expect(aviso.params).toMatchObject({
      pisoTier: "plan3",
      pisoHastaIso: new Date(hasta).toISOString(),
    });
  });

  it("sin resto prepago, el aviso no inventa uno", async () => {
    const { app, store, mp } = await conLinkPedido(MUNDO());

    await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    const [aviso] = mails(store, "withdrawal-team-notice");
    expect(aviso.params.pisoTier).toBeUndefined();
    expect(aviso.params.pisoHastaIso).toBeUndefined();
  });

  it("en el límite y fuera de plazo NO se corta nada", async () => {
    for (const dias of [11, 40]) {
      const { app, store, mp } = await conLinkPedido(
        MUNDO(),
        fakeMp({ subs: { p1: [SUB("s1", dias)] } }),
      );

      await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

      expect(store.mp_plans.p1[CAMPO_ARREPENTIDO]).toBeUndefined();
      expect(store.users[UID].subscription).toEqual({ tier: "plan2", status: "active" });
    }
  });
});

describe("confirmarArrepentimientoPorMail — en el LÍMITE del plazo", () => {
  // Contrató el sábado 19/09; el décimo día fue el martes 29; hoy es miércoles 30.
  // Un feriado el martes habría corrido el plazo hasta hoy (términos §6).
  const LIMITE = () => fakeMp({ subs: { p1: [SUB("s1", 11)] } });

  it("⚠️ NO cancela nada: lo decide una persona", async () => {
    const { app, store, mp } = await conLinkPedido(MUNDO(), LIMITE());

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r).toEqual({ status: "en-revision" });
    expect(mp.canceladas).toEqual([]);
    const [aviso] = mails(store, "withdrawal-team-notice");
    expect(aviso.params).toMatchObject({ estado: "a-revisar", canceladas: 0, email: MAIL });
    const [aUsuario] = mails(store, "withdrawal-received");
    expect(aUsuario.params).toEqual({ code: CODE, revision: "1" });
  });

  it("sin fecha de contratación que se entienda, tampoco se decide a ciegas", async () => {
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("s1", 3, { date_created: "no-es-una-fecha" })] } }),
    );

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("en-revision");
    expect(mp.canceladas).toEqual([]);
    expect(mails(store, "withdrawal-team-notice")[0].params.estado).toBe("a-revisar");
  });
});

// ---------------------------------------------------------------------------
// Lo que NO es una contratación, y lo que falla
// ---------------------------------------------------------------------------
describe("confirmarArrepentimientoPorMail — sin contratación / con fallas", () => {
  it("un checkout que nadie completó no es una contratación, y el link SIGUE sirviendo", async () => {
    // Además cubre la demora del índice de búsqueda de MP: una suscripción
    // recién creada tarda en aparecer, y quemar el link sobre eso dejaría sin
    // salida a alguien con un derecho irrenunciable.
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("s1", 1, { status: "pending" })] } }),
    );

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("sin-suscripcion");
    expect(tokens(store)[hashToken(TOKEN)].usedAt).toBeNull();
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(0);
  });

  it("si MP no contesta la búsqueda, no pasó nada y el link sigue sirviendo", async () => {
    const { app, store, mp } = await conLinkPedido(MUNDO(), fakeMp({ fallaBusqueda: true }));

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("no-disponible");
    expect(tokens(store)[hashToken(TOKEN)].usedAt).toBeNull();
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(0);
  });

  it("si MP rechaza la cancelación: no se avisa al equipo y el link sigue sirviendo", async () => {
    const { app, store, mp } = await conLinkPedido(
      MUNDO(),
      fakeMp({ subs: { p1: [SUB("s1", 3)] }, fallaBaja: true }),
    );

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(r.status).toBe("no-disponible");
    expect(tokens(store)[hashToken(TOKEN)].usedAt).toBeNull();
    // Avisar «devolvé el pago» de una suscripción que sigue viva cobrando sería
    // peor que no avisar.
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(0);
  });

  it("⚠️ si el aviso al equipo falla, NO se pierde: el link se libera y el reintento lo recupera", async () => {
    // El caso caro. La suscripción YA se canceló; si el aviso se perdiera en
    // silencio, nadie sabría que hay una devolución por hacer.
    const { app, store, control, mp } = await conLinkPedido(MUNDO());
    control.fallaCola = true;

    const primero = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps);

    expect(primero.status).toBe("no-disponible");
    expect(mp.canceladas).toEqual(["s1"]);
    expect(tokens(store)[hashToken(TOKEN)].usedAt).toBeNull();
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(0);

    // La cola vuelve. El reintento encuentra la suscripción ya cancelada, no
    // vuelve a llamar a MP, y ahora SÍ avisa.
    control.fallaCola = false;
    const depsReintento = { ...mp.deps, nowMs: AHORA + CANCEL_COOLDOWN_MS + 1 };
    const segundo = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, depsReintento);

    expect(segundo.status).toBe("recibido");
    expect(mp.canceladas).toEqual(["s1"]);
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// El token
// ---------------------------------------------------------------------------
describe("confirmarArrepentimientoPorMail — el token", () => {
  it("sin forma de token no toca nada", async () => {
    const { app, store, mp } = await conLinkPedido(MUNDO());
    const antes = JSON.stringify(store);

    for (const token of [undefined, null, 42, "", "corto", "x".repeat(43) + "!", {}]) {
      const r = await runConfirmarArrepentimientoPorMail(app, { token }, mp.deps);
      expect(r).toEqual({ status: "invalido" });
    }
    expect(JSON.stringify(store)).toBe(antes);
    expect(mp.canceladas).toEqual([]);
  });

  it("un link vencido (72 h) no sirve", async () => {
    const { app, mp } = await conLinkPedido(MUNDO());

    const r = await runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, {
      ...mp.deps,
      nowMs: AHORA + TOKEN_TTL_MS + 1,
    });

    expect(r.status).toBe("vencido");
  });

  it("dos clicks simultáneos: uno procesa y el otro ve ya-usado; se cancela y se avisa UNA vez", async () => {
    const { app, store, mp } = await conLinkPedido(MUNDO());

    const [a, b] = await Promise.all([
      runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps),
      runConfirmarArrepentimientoPorMail(app, { token: TOKEN }, mp.deps),
    ]);

    expect([a.status, b.status].sort()).toEqual(["recibido", "ya-usado"]);
    expect(mp.canceladas).toEqual(["s1"]);
    expect(mails(store, "withdrawal-team-notice")).toHaveLength(1);
  });

  it("⚠️ un link de BAJA no sirve de arrepentimiento, ni al revés", async () => {
    const mundo = MUNDO();
    const hash = hashToken(TOKEN);
    const doc = () => ({
      uid: UID,
      code: null,
      createdAt: ts(AHORA),
      expiresAt: ts(AHORA + TOKEN_TTL_MS),
      usedAt: null,
    });

    // Un token válido de BAJA presentado al arrepentimiento…
    const conBaja = fakeApp({ ...mundo, [BAJAS_POR_MAIL_COLLECTION]: { [hash]: doc() } });
    const mp1 = fakeMp({ subs: { p1: [SUB("s1", 3)] } });
    expect(await runConfirmarArrepentimientoPorMail(conBaja.app, { token: TOKEN }, mp1.deps))
      .toEqual({ status: "invalido" });
    expect(mp1.canceladas).toEqual([]);

    // …y uno de ARREPENTIMIENTO presentado a la baja.
    const conArr = fakeApp({ ...mundo, [ARREPENTIMIENTOS_POR_MAIL_COLLECTION]: { [hash]: doc() } });
    const mp2 = fakeMp({ subs: { p1: [SUB("s1", 3)] } });
    expect(await runConfirmarBajaPorMail(conArr.app, { token: TOKEN }, mp2.deps))
      .toEqual({ status: "invalido" });
    expect(mp2.canceladas).toEqual([]);
  });

  it("⚠️ el uid sale del documento del token: se corta la suscripción de ESA cuenta y no la de otra", async () => {
    const mundo = MUNDO();
    mundo.users[OTRO_UID] = { role: "trainer" };
    mundo.mp_plans.p2 = { producto: "trainer", uid: OTRO_UID, tier: "plan1", cycle: "monthly" };
    const fake = fakeApp(mundo);
    await runSolicitarArrepentimientoPorMail(fake.app, { email: MAIL }, fijo);
    const mp = fakeMp({
      subs: {
        p1: [SUB("de-u1", 3)],
        p2: [SUB("de-u2", 3, { external_reference: OTRO_UID })],
      },
    });

    await runConfirmarArrepentimientoPorMail(fake.app, { token: TOKEN }, mp.deps);

    expect(mp.canceladas).toEqual(["de-u1"]);
  });
});

// ---------------------------------------------------------------------------
// La fecha de contratación, sola
// ---------------------------------------------------------------------------
describe("contratoMasReciente", () => {
  it("ignora lo que nunca se autorizó", () => {
    expect(contratoMasReciente([{ id: "a", status: "pending", date_created: haceDias(1) }]))
      .toBeNull();
    expect(contratoMasReciente([])).toBeNull();
  });

  it("elige la más reciente", () => {
    const c = contratoMasReciente([
      { id: "vieja", status: "cancelled", date_created: haceDias(40) },
      { id: "nueva", status: "authorized", date_created: haceDias(2) },
    ]);

    expect(c?.sub.id).toBe("nueva");
    expect(c?.contratoMs).toBe(AHORA - 2 * DIA_MS);
  });

  it("una con fecha ilegible pierde contra una con fecha, pero no desaparece si es la única", () => {
    const sola = contratoMasReciente([{ id: "x", status: "authorized", date_created: "???" }]);
    expect(sola?.contratoMs).toBeNull();

    const dos = contratoMasReciente([
      { id: "rota", status: "authorized", date_created: "???" },
      { id: "buena", status: "authorized", date_created: haceDias(2) },
    ]);
    expect(dos?.sub.id).toBe("buena");
  });
});
