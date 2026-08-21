/**
 * resume-trainer-link.test.ts — onCall wrapper for the resume gate
 * (paywall Fase 7, PR4, slice 3). LOCAL — no emulator.
 *
 * `resume` is the gap the whole slice exists for: pausing drops an athlete's
 * weight from 1.0 to 0.5, so a trainer at the limit could pause two, accept a
 * new one, then resume both and land ABOVE the limit without any gate ever
 * seeing it. Gating `accept` alone leaves that door open.
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
import { runResumeTrainerLink } from "../subscriptions/resume-trainer-link";

const mockSync = syncTrainerLoad as jest.MockedFunction<typeof syncTrainerLoad>;

describe("runResumeTrainerLink", () => {
  beforeEach(() => {
    mockSync.mockReset();
  });

  it("delegates with expectedFromStatus 'paused' (NOT 'pending')", async () => {
    mockSync.mockResolvedValue({
      trainerId: "trainer-1",
      weightedLoad: 7,
      limit: 7,
      promoted: true,
    });

    const result = await runResumeTrainerLink({} as never, "trainer-1", "L1");

    expect(mockSync).toHaveBeenCalledWith(expect.anything(), {
      promotion: {
        linkId: "L1",
        callerUid: "trainer-1",
        expectedFromStatus: "paused",
      },
    });
    expect(result).toEqual({ status: "ok", weightedLoad: 7, limit: 7 });
  });

  it("already-active is a no-op, not an error", async () => {
    mockSync.mockResolvedValue({
      trainerId: "trainer-1",
      weightedLoad: 7,
      limit: 7,
      promoted: false,
    });

    await expect(
      runResumeTrainerLink({} as never, "trainer-1", "L1"),
    ).resolves.toEqual({ status: "noop", weightedLoad: 7, limit: 7 });
  });

  it("propagates the over-limit HttpsError untouched", async () => {
    // The 0.5 -> 1.0 case: 7.0 with two paused, resuming one projects 7.5.
    mockSync.mockRejectedValue(
      new HttpsError("resource-exhausted", "Weighted-load limit reached.", {
        reason: "plan-limit",
        tier: "plan1",
        limit: 7,
        currentLoad: 7,
        projectedLoad: 7.5,
      }),
    );

    await expect(
      runResumeTrainerLink({} as never, "trainer-1", "L1"),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "plan-limit", projectedLoad: 7.5 },
    });
  });

  it("rejects an empty linkId before touching Firestore", async () => {
    await expect(
      runResumeTrainerLink({} as never, "trainer-1", ""),
    ).rejects.toMatchObject({ code: "invalid-argument" });
    expect(mockSync).not.toHaveBeenCalled();
  });
});
