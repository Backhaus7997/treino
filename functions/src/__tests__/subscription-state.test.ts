/**
 * subscription-state.test.ts — el mapper compartido de
 * `users/{uid}.subscription` y la PROPAGACION de un dato degradado por los dos
 * consumidores del limite (paywall Fase 7).
 *
 * LOCAL — sin emulador, mismo doble FakeTx que promote-link.test.ts (design
 * D-6). Se mockea `firebase-functions` para poder afirmar que el warn salio: el
 * log es la mitad del arreglo, hoy un typo degrada en silencio.
 *
 * ── QUE TIENE QUE PINEAR ESTE ARCHIVO ─────────────────────────────────────
 *
 * Los bloques de "propagacion" existen para que revertir `promote-link.ts` y
 * `sync-entitlements.ts` a su version anterior — la del `as` ciego con el
 * mapper duplicado — ponga el suite ROJO. No alcanza con afirmar que el limite
 * da 2: ESO ya lo garantiza el `default` de effective-limit.ts y pasa igual con
 * el cast ciego, asi que un test asi no guarda nada.
 *
 * Lo que SI distingue a los dos mundos, y por eso es lo que se afirma aca:
 *   1. el WARN con el uid sale desde adentro de cada caller (el cast ciego no
 *      logea nada, y sin uid no hay como encontrar el documento roto);
 *   2. el TIER degradado viaja a los `details` del error (el cast ciego le
 *      manda al cliente un tier que su propia union no conoce);
 *   3. un `currentPeriodEnd` numerico ya no revienta con TypeError adentro de
 *      la transaccion;
 *   4. la VALVULA del barrido: con datos degradados no se bloquea a nadie.
 */

jest.mock("firebase-admin", () => {
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  const deleteSentinel = { __fakeFieldValue: "delete" };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms }),
  };
  firestore.FieldValue = { delete: () => deleteSentinel };
  return { firestore };
});

const warnSpy = jest.fn();
const infoSpy = jest.fn();
const errorSpy = jest.fn();
jest.mock("firebase-functions", () => ({
  logger: {
    warn: (...args: unknown[]) => warnSpy(...args),
    info: (...args: unknown[]) => infoSpy(...args),
    error: (...args: unknown[]) => errorSpy(...args),
  },
}));

import * as admin from "firebase-admin";

import { createFakeFirestore, FakeDoc, FakeFirestoreState } from "./helpers/fake-tx-firestore";
import { syncTrainerLoad } from "../subscriptions/promote-link";
import { syncTrainerEntitlements } from "../subscriptions/sync-entitlements";
import { toSubscriptionState } from "../subscriptions/subscription-state";

const app = {} as admin.app.App;

function install(seed: Partial<FakeFirestoreState>): FakeFirestoreState {
  const { db, state } = createFakeFirestore(seed);
  (admin.firestore as unknown as jest.Mock).mockReturnValue(db);
  return state;
}

const ts = (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms });

const link = (athleteId: string, status: string, extra: Record<string, unknown> = {}): FakeDoc => ({
  trainerId: "t1",
  athleteId,
  status,
  entitlement: "entitled",
  ...extra,
});

/** El typo: `cancelled` con una sola L. Ningun tipo lo frena — el dato se
 * escribe a mano con el Admin SDK. */
const TYPO_SUB = { tier: "plan1", status: "canceled" };

/** El otro error a mano igual de plausible: epoch ms en vez de Timestamp. */
const EPOCH_SUB = { tier: "plan1", status: "cancelled", currentPeriodEnd: 7000 };

beforeEach(() => jest.clearAllMocks());

describe("toSubscriptionState — el mapa se escribe A MANO, hay que validarlo", () => {
  it("subscription ausente → null SIN degradacion, y NO logea: es el PF free normal", () => {
    // `degraded: false` es load-bearing: el PF free es la MAYORIA. Si esto
    // contara como degradacion, la valvula del barrido se abriria para todos y
    // el downgrade dejaria de existir.
    expect(toSubscriptionState({}, "t1")).toEqual({ state: null, degraded: false });
    expect(toSubscriptionState(undefined, "t1")).toEqual({ state: null, degraded: false });
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("valores validos → passthrough sin ruido y sin degradacion", () => {
    expect(
      toSubscriptionState({ subscription: { tier: "plan2", status: "grace" } }, "t1"),
    ).toEqual({
      state: { tier: "plan2", status: "grace", currentPeriodEndMs: null },
      degraded: false,
    });
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("subscription que no es un mapa → null + degradado + warn", () => {
    // El estado se pierde pero la degradacion NO: por eso el flag vive al lado
    // del estado y no adentro. Un `state: null` tambien tiene que poder gritar.
    expect(toSubscriptionState({ subscription: "plan2" }, "t1")).toEqual({
      state: null,
      degraded: true,
    });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("no es un mapa"),
      expect.objectContaining({ trainerId: "t1" }),
    );
  });

  it("tier desconocido → free + degradado + warn con el uid", () => {
    // El uid es lo que hace el log ACCIONABLE: sin el no hay como encontrar el
    // documento roto.
    expect(
      toSubscriptionState({ subscription: { tier: "gold", status: "active" } }, "t1"),
    ).toEqual({
      state: { tier: "free", status: "active", currentPeriodEndMs: null },
      degraded: true,
    });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("tier desconocido"),
      expect.objectContaining({ trainerId: "t1", tier: "gold" }),
    );
  });

  it("tier heredado del prototipo ('toString') → free + degradado + warn", () => {
    expect(
      toSubscriptionState({ subscription: { tier: "toString", status: "active" } }, "t1"),
    ).toMatchObject({ state: { tier: "free" }, degraded: true });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("tier desconocido"),
      expect.objectContaining({ tier: "toString" }),
    );
  });

  it("tier que no es string (number) → free + degradado + warn", () => {
    expect(
      toSubscriptionState({ subscription: { tier: 2, status: "active" } }, "t1"),
    ).toMatchObject({ state: { tier: "free" }, degraded: true });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("tier desconocido"),
      expect.objectContaining({ tier: 2 }),
    );
  });

  it("status desconocido → paused, pero el tier se PRESERVA + degradado + warn", () => {
    // Degradar el status no puede borrar el tier: el tier es lo que hace que la
    // denegacion diga "revisá tu suscripción" en vez de "comprá mas plan".
    expect(
      toSubscriptionState({ subscription: { tier: "plan2", status: "canceled" } }, "t1"),
    ).toEqual({
      state: { tier: "plan2", status: "paused", currentPeriodEndMs: null },
      degraded: true,
    });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("status desconocido"),
      expect.objectContaining({ trainerId: "t1", status: "canceled", tier: "plan2" }),
    );
  });

  it("status ausente → paused + degradado + warn", () => {
    expect(toSubscriptionState({ subscription: { tier: "plan1" } }, "t1")).toMatchObject({
      state: { status: "paused" },
      degraded: true,
    });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("status desconocido"),
      expect.objectContaining({ status: undefined }),
    );
  });

  it("currentPeriodEnd Timestamp → milisegundos, sin degradacion", () => {
    expect(
      toSubscriptionState(
        { subscription: { tier: "plan1", status: "cancelled", currentPeriodEnd: ts(7000) } },
        "t1",
      ),
    ).toEqual({
      state: { tier: "plan1", status: "cancelled", currentPeriodEndMs: 7000 },
      degraded: false,
    });
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("currentPeriodEnd ausente o null → null, sin warn y sin degradacion", () => {
    const base = { tier: "plan1", status: "cancelled" };
    expect(toSubscriptionState({ subscription: base }, "t1")).toEqual({
      state: { tier: "plan1", status: "cancelled", currentPeriodEndMs: null },
      degraded: false,
    });
    expect(
      toSubscriptionState({ subscription: { ...base, currentPeriodEnd: null } }, "t1"),
    ).toMatchObject({ degraded: false });
    expect(warnSpy).not.toHaveBeenCalled();
  });

  it("currentPeriodEnd con forma desconocida (number) → null + DEGRADADO + warn", () => {
    // Conservador a proposito: un `cancelled` sin paid-through cae a Free. No
    // se regala entitlement por un dato que no entendemos. Pero ese mismo
    // `null` era antes un TypeError que abortaba la transaccion entera, o sea
    // que la degradacion CAMBIO el signo del fallo — por eso tiene que
    // reportarse, y no solo logearse.
    expect(
      toSubscriptionState({ subscription: EPOCH_SUB }, "t1"),
    ).toMatchObject({ state: { currentPeriodEndMs: null }, degraded: true });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("currentPeriodEnd"),
      expect.objectContaining({ trainerId: "t1", received: "number" }),
    );
  });
});

/**
 * EL GATE — fail-closed contra el entrenador.
 *
 * POLITICA: la degradacion frena TRABAJO NUEVO. `promote-link.ts` ignora el
 * flag `degraded` a proposito y sigue denegando con el limite degradado.
 */
describe("propagacion de un dato degradado — el gate (promote-link)", () => {
  const tresLinks = () => ({
    A1: link("a1", "active"),
    A2: link("a2", "active"),
    L1: link("a3", "pending"),
  });

  const promover = () =>
    syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "t1", expectedFromStatus: "pending" },
    });

  it("DENIEGA cuando la promocion excede el limite degradado", async () => {
    // Con `undefined` como limite, `projectedLoad > undefined` es false y el
    // gate no denegaba NUNCA: el paywall dejaba de existir para ese PF.
    install({ trainer_links: tresLinks(), users: { t1: { subscription: TYPO_SUB } } });

    await expect(promover()).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { limit: 2, projectedLoad: 3 },
    });
  });

  it("el WARN con el uid sale desde adentro del gate", async () => {
    // ESTE es el test que pinea que el gate usa el mapper compartido. El cast
    // ciego que vivia aca antes producia EXACTAMENTE el mismo limite (2) — lo
    // unico que lo distingue es que no avisaba a nadie. Sin este assert,
    // devolver el gate al cast ciego deja el suite verde.
    install({ trainer_links: tresLinks(), users: { t1: { subscription: TYPO_SUB } } });

    await expect(promover()).rejects.toMatchObject({ code: "resource-exhausted" });

    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("status desconocido"),
      expect.objectContaining({ trainerId: "t1", status: "canceled" }),
    );
  });

  it("el motivo de denegacion es de FACTURACION, no de upsell", async () => {
    // El tier (`plan1`, limite nominal 7) se PRESERVA aunque el status no se
    // entienda: el PF ve "revisá tu suscripción", no "comprá un plan mas
    // grande" — que seria falso, ya pago uno.
    install({ trainer_links: tresLinks(), users: { t1: { subscription: TYPO_SUB } } });

    await expect(promover()).rejects.toMatchObject({
      details: { reason: "subscription-inactive", tier: "plan1" },
    });
  });

  it("un tier ilegible llega al cliente ya SANEADO, no crudo", async () => {
    // `details.tier` viaja al cliente, que lo parsea contra su propia union
    // `SubscriptionTier`. El cast ciego le mandaba "gold" tal cual — un valor
    // que ninguna de las dos puntas conoce. El mapper lo degrada a "free"
    // ANTES de que salga. Mismo limite (2) en los dos mundos: lo unico que
    // cambia es que ahora el payload es valido.
    install({
      trainer_links: tresLinks(),
      users: { t1: { subscription: { tier: "gold", status: "active" } } },
    });

    await expect(promover()).rejects.toMatchObject({
      details: { tier: "free", reason: "plan-limit", limit: 2 },
    });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("tier desconocido"),
      expect.objectContaining({ trainerId: "t1", tier: "gold" }),
    );
  });

  it("un currentPeriodEnd numerico ya no revienta la transaccion", async () => {
    // Antes: `sub.currentPeriodEnd.toMillis()` sobre un number tiraba TypeError
    // adentro de la transaccion. El PF no recibia una denegacion de paywall,
    // recibia un internal error. Ahora degrada a `null` ⇒ `cancelled` sin
    // paid-through ⇒ Free (2), y deniega como corresponde.
    install({ trainer_links: tresLinks(), users: { t1: { subscription: EPOCH_SUB } } });

    await expect(promover()).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "subscription-inactive", tier: "plan1", limit: 2, projectedLoad: 3 },
    });
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("currentPeriodEnd"),
      expect.objectContaining({ trainerId: "t1", received: "number" }),
    );
  });

  it("sigue promoviendo cuando la carga proyectada entra en el limite degradado", async () => {
    install({
      trainer_links: { A1: link("a1", "active"), L1: link("a2", "pending") },
      users: { t1: { subscription: TYPO_SUB } },
    });

    const res = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "t1", expectedFromStatus: "pending" },
    });

    expect(res).toMatchObject({ promoted: true, limit: 2, weightedLoad: 2 });
  });
});

/**
 * EL BARRIDO — nunca revoca relaciones existentes.
 *
 * POLITICA: la degradacion de datos frena TRABAJO NUEVO (friccion sobre el
 * entrenador) pero NUNCA revoca relaciones existentes (friccion sobre el
 * alumno). Es la MISMA senal que el gate, con la decision opuesta.
 */
describe("propagacion de un dato degradado — el barrido (sync-entitlements)", () => {
  /**
   * 4 activos, del mas viejo al mas nuevo; L1 viene bloqueado de antes.
   *
   * El pre-bloqueado es el MAS VIEJO a proposito: el criterio de seleccion
   * conserva los mas antiguos (select-blocked-links.ts), asi que L1 es el que
   * tiene que volver. Si el pre-bloqueado fuera el mas nuevo no habria ninguna
   * devolucion que observar y estos tests dejarian de probar la mitad
   * asimetrica de la valvula.
   */
  const cuatroLinks = () => ({
    L1: link("a1", "active", {
      acceptedAt: ts(1000),
      entitlement: "blocked",
      blockedAt: ts(1),
      blockedReason: "over-limit",
    }),
    L2: link("a2", "active", { acceptedAt: ts(2000) }),
    L3: link("a3", "active", { acceptedAt: ts(3000) }),
    L4: link("a4", "active", { acceptedAt: ts(4000) }),
  });

  it("VALVULA: con datos degradados devuelve, pero NO bloquea a nadie", async () => {
    // Un typo NUESTRO no le corta el servicio a los alumnos de un PF que capaz
    // pago plan3. El limite degradado (2) diria que sobran dos vinculos; el
    // barrido los deja donde estan y grita con el uid.
    const state = install({
      trainer_links: cuatroLinks(),
      users: { t1: { subscription: TYPO_SUB } },
    });

    const res = await syncTrainerEntitlements(app, "t1", 9000);

    expect(res.limit).toBe(2);
    expect(res.blocked).toEqual([]);
    // Asimetrico a proposito: devolver NUNCA empeora la situacion de un alumno.
    expect(res.unblocked).toEqual(["L1"]);
    expect(state.trainer_links.L1.entitlement).toBe("entitled");
    expect(state.trainer_links.L2.entitlement).toBe("entitled");
    expect(state.trainer_links.L3.entitlement).toBe("entitled");
    expect(state.trainer_links.L4.entitlement).toBe("entitled");
    // weightedLoad refleja la carga REAL (4 > limite 2). Ese desfasaje es lo
    // que hace visible el documento roto en vez de esconderlo.
    expect(res.weightedLoad).toBe(4);
    expect(state.users.t1.weightedLoad).toBe(4);
  });

  it("el salteo se logea como ERROR, con el uid y los vinculos perdonados", async () => {
    // Perdonar el limite en silencio seria peor que bloquear: el PF cobraria
    // gratis y nadie se enteraria. Va con uid porque hay UN documento que
    // arreglar a mano entre cientos.
    install({ trainer_links: cuatroLinks(), users: { t1: { subscription: TYPO_SUB } } });

    await syncTrainerEntitlements(app, "t1", 9000);

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("se SALTEA el bloqueo"),
      expect.objectContaining({
        trainerId: "t1",
        limit: 2,
        skippedBlock: expect.arrayContaining(["L3", "L4"]),
      }),
    );
  });

  it("la valvula es CONDICIONAL: con datos sanos el barrido sigue bloqueando", async () => {
    // Sin este control, "no bloquear nunca" pasaria el test de arriba y el
    // downgrade entero quedaria muerto.
    const state = install({
      trainer_links: cuatroLinks(),
      users: { t1: { subscription: { tier: "free", status: "active" } } },
    });

    const res = await syncTrainerEntitlements(app, "t1", 9000);

    expect(res.limit).toBe(2);
    expect(res.blocked.sort()).toEqual(["L3", "L4"]);
    expect(res.unblocked).toEqual(["L1"]);
    expect(state.trainer_links.L3.entitlement).toBe("blocked");
    expect(res.weightedLoad).toBe(2);
    expect(errorSpy).not.toHaveBeenCalled();
  });
});
