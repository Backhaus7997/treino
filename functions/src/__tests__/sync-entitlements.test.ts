/**
 * sync-entitlements.test.ts — el escritor de `entitlement` (downgrade).
 * LOCAL — sin emulador, con el mismo fake tx que promote-link.
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

import * as admin from "firebase-admin";

import { createFakeFirestore, FakeFirestoreState } from "./helpers/fake-tx-firestore";
import { syncTrainerEntitlements } from "../subscriptions/sync-entitlements";

const app = {} as admin.app.App;

function install(seed: Partial<FakeFirestoreState>) {
  const { db, state } = createFakeFirestore(seed);
  (admin.firestore as unknown as jest.Mock).mockReturnValue(db);
  return state;
}

const ts = (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms });

const lnk = (o: Record<string, unknown>) => ({
  trainerId: "t1",
  status: "active",
  entitlement: "entitled",
  acceptedAt: ts(1000),
  ...o,
});

describe("syncTrainerEntitlements", () => {
  it("sin suscripcion (Free 2) bloquea el excedente y deja los 2 mas recientes", async () => {
    const state = install({
      users: { t1: {} },
      trainer_links: {
        L1: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(900) }),
        L4: lnk({ athleteId: "a4", acceptedAt: ts(800) }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.limit).toBe(2);
    expect(r.blocked.sort()).toEqual(["L1", "L2"]);
    expect(state.trainer_links.L1.entitlement).toBe("blocked");
    expect(state.trainer_links.L1.blockedReason).toBe("over-limit");
    expect(state.trainer_links.L3.entitlement).toBe("entitled");
    // weightedLoad refleja el estado YA reconciliado, no el previo.
    expect(state.users.t1.weightedLoad).toBe(2.0);
  });

  it("plan1 activo (7) no bloquea a nadie", async () => {
    const state = install({
      users: { t1: { subscription: { tier: "plan1", status: "active" } } },
      trainer_links: {
        L1: lnk({ athleteId: "a1" }),
        L2: lnk({ athleteId: "a2" }),
        L3: lnk({ athleteId: "a3" }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.limit).toBe(7);
    expect(r.blocked).toEqual([]);
    expect(state.users.t1.weightedLoad).toBe(3.0);
  });

  it("al volver a pagar devuelve a los bloqueados y limpia los campos", async () => {
    const state = install({
      users: { t1: { subscription: { tier: "plan1", status: "active" } } },
      trainer_links: {
        L1: lnk({
          athleteId: "a1",
          entitlement: "blocked",
          blockedAt: ts(1),
          blockedReason: "over-limit",
        }),
        L2: lnk({ athleteId: "a2" }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.unblocked).toEqual(["L1"]);
    expect(state.trainer_links.L1.entitlement).toBe("entitled");
    expect(state.trainer_links.L1.blockedAt).toBe(
      admin.firestore.FieldValue.delete(),
    );
  });

  it("cancelled: entitled hasta currentPeriodEnd, bloquea despues", async () => {
    const seed = () => ({
      users: {
        t1: {
          subscription: {
            tier: "plan1",
            status: "cancelled",
            currentPeriodEnd: ts(10_000),
          },
        },
      },
      trainer_links: {
        L1: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(300) }),
      },
    });

    install(seed());
    const antes = await syncTrainerEntitlements(app, "t1", 9_000);
    expect(antes.limit).toBe(7);
    expect(antes.blocked).toEqual([]);

    // Este es el disparador que NADIE detecta hoy: el limite cae solo por el
    // paso del tiempo, sin que se escriba un solo documento.
    install(seed());
    const despues = await syncTrainerEntitlements(app, "t1", 11_000);
    expect(despues.limit).toBe(2);
    expect(despues.blocked).toEqual(["L1"]);
  });

  it("es idempotente: correr dos veces no genera cambios nuevos", async () => {
    const state = install({
      users: { t1: {} },
      trainer_links: {
        L1: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(900) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(800) }),
      },
    });

    const primera = await syncTrainerEntitlements(app, "t1", 5_000);
    expect(primera.blocked).toEqual(["L1"]);

    (admin.firestore as unknown as jest.Mock).mockReturnValue(
      createFakeFirestore(state).db,
    );
    const segunda = await syncTrainerEntitlements(app, "t1", 5_000);
    expect(segunda.blocked).toEqual([]);
    expect(segunda.unblocked).toEqual([]);
  });
});
