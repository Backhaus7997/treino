/**
 * accept-trainer-link.test.ts — onCall wrapper for the accept gate
 * (paywall Fase 7, PR4, slice 2). LOCAL — no emulator.
 *
 * The wrapper is deliberately thin: auth guard, input guard, delegate to
 * `syncTrainerLoad` with `expectedFromStatus: 'pending'`. All the gate
 * arithmetic, the precondition ladder and the `resource-exhausted` payload
 * are the helper's job and are covered by promote-link.test.ts — what these
 * tests pin is that the wrapper WIRES it correctly and never swallows a
 * typed failure into a generic one.
 */

import { HttpsError } from "firebase-functions/v2/https";

jest.mock("../subscriptions/promote-link", () => ({
  syncTrainerLoad: jest.fn(),
}));

jest.mock("../subscriptions/trainer-limit-mail", () => ({
  ...jest.requireActual("../subscriptions/trainer-limit-mail"),
  registrarTopeDeAlumnos: jest.fn(async () => undefined),
}));

jest.mock("firebase-admin", () => ({
  app: jest.fn(() => ({})),
  initializeApp: jest.fn(() => ({})),
}));

jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());

import { syncTrainerLoad } from "../subscriptions/promote-link";
import { registrarTopeDeAlumnos } from "../subscriptions/trainer-limit-mail";
import { runAcceptTrainerLink } from "../subscriptions/accept-trainer-link";

const mockSync = syncTrainerLoad as jest.MockedFunction<typeof syncTrainerLoad>;
const mockRegistrar = registrarTopeDeAlumnos as jest.MockedFunction<
  typeof registrarTopeDeAlumnos
>;

describe("runAcceptTrainerLink", () => {
  beforeEach(() => {
    mockSync.mockReset();
    mockRegistrar.mockReset();
    mockRegistrar.mockResolvedValue(undefined);
  });

  it("delegates to syncTrainerLoad with expectedFromStatus 'pending'", async () => {
    mockSync.mockResolvedValue({
      trainerId: "trainer-1",
      weightedLoad: 7,
      limit: 7,
      promoted: true,
    });

    const result = await runAcceptTrainerLink({} as never, "trainer-1", "L1");

    expect(mockSync).toHaveBeenCalledWith(expect.anything(), {
      promotion: {
        linkId: "L1",
        callerUid: "trainer-1",
        expectedFromStatus: "pending",
      },
    });
    expect(result).toEqual({ status: "ok", weightedLoad: 7, limit: 7 });
  });

  it("already-active is reported as a no-op, not an error", async () => {
    // The helper treats an already-active link as a success no-op (retry after
    // a client timeout whose commit landed). The wrapper must NOT turn that
    // into a failure, or a retry would surface a spurious error to the PF.
    mockSync.mockResolvedValue({
      trainerId: "trainer-1",
      weightedLoad: 7,
      limit: 7,
      promoted: false,
    });

    await expect(
      runAcceptTrainerLink({} as never, "trainer-1", "L1"),
    ).resolves.toEqual({ status: "noop", weightedLoad: 7, limit: 7 });
  });

  it("propagates the helper's typed HttpsError untouched", async () => {
    // The over-limit payload IS the contract the client parses to open the
    // paywall. Re-wrapping it would erase `details` and break the branch.
    const denial = new HttpsError(
      "resource-exhausted",
      "Weighted-load limit reached.",
      {
        reason: "plan-limit",
        tier: "plan1",
        limit: 7,
        currentLoad: 7,
        projectedLoad: 8,
      },
    );
    mockSync.mockRejectedValue(denial);

    await expect(
      runAcceptTrainerLink({} as never, "trainer-1", "L1"),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "plan-limit", tier: "plan1" },
    });
  });

  it("rejects an empty linkId before touching Firestore", async () => {
    await expect(
      runAcceptTrainerLink({} as never, "trainer-1", ""),
    ).rejects.toMatchObject({ code: "invalid-argument" });
    expect(mockSync).not.toHaveBeenCalled();
  });

  // ── El tope de alumnos: la anotación server-side ────────────────────────
  describe("anotación del tope de alumnos", () => {
    const denialTope = (reason: "plan-limit" | "subscription-inactive") =>
      new HttpsError("resource-exhausted", "Weighted-load limit reached.", {
        reason,
        tier: "plan1",
        limit: 7,
        currentLoad: 7,
        projectedLoad: 8,
      });

    it("⚠️ un rebote por tope (plan-limit) anota students + trainerLimitHitAt", async () => {
      mockSync.mockRejectedValue(denialTope("plan-limit"));

      await expect(
        runAcceptTrainerLink({} as never, "trainer-1", "L1"),
      ).rejects.toMatchObject({ code: "resource-exhausted" });

      expect(mockRegistrar).toHaveBeenCalledTimes(1);
      expect(mockRegistrar).toHaveBeenCalledWith(
        expect.anything(),
        "trainer-1",
        expect.any(Number),
        expect.any(Number),
        "L1",
      );
    });

    it("⚠️ el incremento es projectedLoad - currentLoad de los details (pending → active)", async () => {
      // denialTope("plan-limit"): currentLoad 7, projectedLoad 8 → incremento 1.
      mockSync.mockRejectedValue(denialTope("plan-limit"));

      await expect(
        runAcceptTrainerLink({} as never, "trainer-1", "L1"),
      ).rejects.toMatchObject({ code: "resource-exhausted" });

      expect(mockRegistrar).toHaveBeenCalledWith(
        expect.anything(),
        "trainer-1",
        expect.any(Number),
        1,
        "L1",
      );
    });

    // ── Hallazgo de Codex sobre #1267 (P2 de esta ronda) ──
    it("⚠️ guarda el linkId del vínculo que se intentó activar, no cualquier otro", async () => {
      mockSync.mockRejectedValue(denialTope("plan-limit"));

      await expect(
        runAcceptTrainerLink({} as never, "trainer-1", "otro-link-99"),
      ).rejects.toMatchObject({ code: "resource-exhausted" });

      expect(mockRegistrar).toHaveBeenCalledWith(
        expect.anything(),
        "trainer-1",
        expect.any(Number),
        expect.any(Number),
        "otro-link-99",
      );
    });

    it("⚠️ un rebote por subscription-inactive NO anota — no es un tope, es cobro atrasado", async () => {
      // Hallazgo de Codex sobre #1267 (P1). Hasta acá este test se llamaba
      // "también anota" y esperaba `toHaveBeenCalledTimes(1)` — ESE era el
      // bug: un PF con un plan pago pero la suscripción `pending`/`paused`/
      // vencida (`subscription-inactive`, D-2 en `promote-link.ts`) quedaba
      // anotado como si hubiera chocado el tope de alumnos, y
      // `sendTrainerLimitMailOnHit` le mandaba el mail de upsell — "VER LOS
      // PLANES" a quien ya pagó uno. Ver `esTopeDeAlumnos`.
      mockSync.mockRejectedValue(denialTope("subscription-inactive"));

      await expect(
        runAcceptTrainerLink({} as never, "trainer-1", "L1"),
      ).rejects.toMatchObject({ code: "resource-exhausted" });

      expect(mockRegistrar).not.toHaveBeenCalled();
    });

    it("⚠️ un rechazo por otro motivo (wrong-status) NO anota", async () => {
      mockSync.mockRejectedValue(
        new HttpsError("failed-precondition", "wrong-status"),
      );

      await expect(
        runAcceptTrainerLink({} as never, "trainer-1", "L1"),
      ).rejects.toMatchObject({ code: "failed-precondition" });

      expect(mockRegistrar).not.toHaveBeenCalled();
    });

    it("⚠️ un resource-exhausted SIN el reason del tope (otra causa) NO anota", async () => {
      mockSync.mockRejectedValue(
        new HttpsError("resource-exhausted", "Quota exceeded."),
      );

      await expect(
        runAcceptTrainerLink({} as never, "trainer-1", "L1"),
      ).rejects.toMatchObject({ code: "resource-exhausted" });

      expect(mockRegistrar).not.toHaveBeenCalled();
    });

    it("⚠️ si la anotación falla, el callable igual tira el error original", async () => {
      mockSync.mockRejectedValue(denialTope("plan-limit"));
      mockRegistrar.mockRejectedValueOnce(new Error("firestore se cayó"));

      await expect(
        runAcceptTrainerLink({} as never, "trainer-1", "L1"),
      ).rejects.toMatchObject({
        code: "resource-exhausted",
        details: { reason: "plan-limit" },
      });
    });
  });
});
