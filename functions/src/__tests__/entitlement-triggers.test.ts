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
      .mockResolvedValueOnce({ trainerId: "t1", limit: 2, blocked: ["L1"], unblocked: [], weightedLoad: 2 })
      .mockResolvedValueOnce({ trainerId: "t2", limit: 7, blocked: [], unblocked: [], weightedLoad: 3 })
      .mockResolvedValueOnce({ trainerId: "t3", limit: 2, blocked: [], unblocked: ["L9"], weightedLoad: 2 });

    const r = await sweepEntitlementsHandler({} as admin.app.App, 1000);

    expect(r).toEqual({ scanned: 3, changed: 2 });
    expect(mockSync).toHaveBeenCalledTimes(3);
  });

  it("un PF con datos rotos NO frena el barrido de los demas", async () => {
    installUsers(["roto", "sano"]);
    mockSync
      .mockRejectedValueOnce(new Error("doc corrupto"))
      .mockResolvedValueOnce({ trainerId: "sano", limit: 2, blocked: ["L1"], unblocked: [], weightedLoad: 2 });

    const r = await sweepEntitlementsHandler({} as admin.app.App, 1000);

    expect(r).toEqual({ scanned: 2, changed: 1 });
  });
});
