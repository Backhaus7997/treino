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

jest.mock("firebase-admin", () => ({
  app: jest.fn(() => ({})),
  initializeApp: jest.fn(() => ({})),
}));

import { syncTrainerLoad } from "../subscriptions/promote-link";
import { runAcceptTrainerLink } from "../subscriptions/accept-trainer-link";

const mockSync = syncTrainerLoad as jest.MockedFunction<typeof syncTrainerLoad>;

describe("runAcceptTrainerLink", () => {
  beforeEach(() => {
    mockSync.mockReset();
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
});
