/**
 * entitlement-triggers.test.ts — guarda anti-loop del trigger y barrido.
 * LOCAL — sin emulador.
 */

jest.mock("firebase-admin", () => {
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms }),
  };
  firestore.FieldValue = { delete: () => ({ __fakeFieldValue: "delete" }) };
  return { firestore, app: jest.fn(), initializeApp: jest.fn() };
});

jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());

// La puerta modular tiene que dar EL MISMO doble que la namespaced de arriba.
//
// `jest.mock("firebase-admin", …)` intercepta el specifier EXACTO. Producción
// importa Timestamp/FieldValue de `firebase-admin/firestore`, y sin esto le
// llega el REAL: el Firestore de mentira de este archivo no reconoce sus
// sentinels, guarda basura en vez de aplicarlos, y el test falla —o peor, pasa—
// por un motivo que no tiene que ver con lo que quiere probar.
//
// Getters y no valores: los factories se evalúan por demanda, así que esto no
// depende del orden entre los dos `jest.mock`.
//
// Lo fija `firebase-admin-mock-surface.test.ts`.
jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

jest.mock("../subscriptions/sync-entitlements", () => ({
  syncTrainerEntitlements: jest.fn(),
}));

import * as admin from "firebase-admin";
import { syncTrainerEntitlements } from "../subscriptions/sync-entitlements";
import {
  subscriptionChanged,
  sweepEntitlementsHandler,
} from "../subscriptions/entitlement-triggers";

const mockSync = syncTrainerEntitlements as jest.MockedFunction<
  typeof syncTrainerEntitlements
>;

describe("subscriptionChanged — guarda anti-loop", () => {
  const sub = { tier: "plan1", status: "active" };

  it("una escritura de weightedLoad NO cuenta como cambio", () => {
    // ESTE es el test que importa. syncTrainerEntitlements escribe
    // weightedLoad en users/{uid}, o sea el MISMO doc que dispara el trigger.
    // Si esto devolviera true, cada corrida se auto-dispara para siempre.
    expect(
      subscriptionChanged(
        { subscription: sub, weightedLoad: 3 },
        { subscription: sub, weightedLoad: 2 },
      ),
    ).toBe(false);
  });

  it("cambiar el status SI cuenta", () => {
    expect(
      subscriptionChanged(
        { subscription: { tier: "plan1", status: "active" } },
        { subscription: { tier: "plan1", status: "cancelled" } },
      ),
    ).toBe(true);
  });

  it("aparecer o desaparecer la suscripcion cuenta", () => {
    expect(subscriptionChanged({}, { subscription: sub })).toBe(true);
    expect(subscriptionChanged({ subscription: sub }, {})).toBe(true);
  });

  it("sin suscripcion de ningun lado no cuenta", () => {
    expect(subscriptionChanged({ displayName: "a" }, { displayName: "b" }))
      .toBe(false);
  });

  it("un doc borrado no revienta", () => {
    expect(subscriptionChanged({ subscription: sub }, undefined)).toBe(true);
    expect(subscriptionChanged(undefined, undefined)).toBe(false);
  });
});

describe("sweepEntitlementsHandler", () => {
  function installUsers(ids: string[]) {
    (admin.firestore as unknown as jest.Mock).mockReturnValue({
      collection: () => ({
        where: () => ({
          get: async () => ({
            size: ids.length,
            docs: ids.map((id) => ({ id })),
          }),
        }),
      }),
    });
  }

  beforeEach(() => mockSync.mockReset());

  it("recorre todos los PF y cuenta los que cambiaron", async () => {
    installUsers(["t1", "t2", "t3"]);
    mockSync
      .mockResolvedValueOnce({ trainerId: "t1", limit: 2, blocked: ["L1"], unblocked: [], weightedLoad: 2, blockedAthleteIds: ["a1"] })
      .mockResolvedValueOnce({ trainerId: "t2", limit: 7, blocked: [], unblocked: [], weightedLoad: 3, blockedAthleteIds: [] })
      .mockResolvedValueOnce({ trainerId: "t3", limit: 2, blocked: [], unblocked: ["L9"], weightedLoad: 2, blockedAthleteIds: [] });

    const r = await sweepEntitlementsHandler({} as admin.app.App, 1000);

    expect(r).toEqual({ scanned: 3, changed: 2 });
    expect(mockSync).toHaveBeenCalledTimes(3);
  });

  it("un PF con datos rotos NO frena el barrido de los demas", async () => {
    installUsers(["roto", "sano"]);
    mockSync
      .mockRejectedValueOnce(new Error("doc corrupto"))
      .mockResolvedValueOnce({ trainerId: "sano", limit: 2, blocked: ["L1"], unblocked: [], weightedLoad: 2, blockedAthleteIds: ["a1"] });

    const r = await sweepEntitlementsHandler({} as admin.app.App, 1000);

    expect(r).toEqual({ scanned: 2, changed: 1 });
  });
});
