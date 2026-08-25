/**
 * Unit tests for syncSessionShareHandler — LOCAL, no emulator.
 *
 * The Admin SDK is mocked with an in-memory `session_shares` store (same idiom
 * as entitlement-triggers.test.ts), so every scenario runs on any machine. What
 * the fake buys that a real Firestore cannot: asserting NEGATIVE facts — the
 * exact list of doc operations the handler performed, so "did not write" is
 * pinned as precisely as "wrote". The round-trip against real Firestore lives in
 * the `sync-session-share.emulator.test.ts` sibling (CI only, Java 21+).
 *
 * Every branch of the trigger is pinned here:
 *   - create (before undefined) + active         → grant
 *   - pending → active                           → grant (takes the share over)
 *   - paused  → active (resume)                  → grant
 *   - active  → active, share held by another PF → INERT   ← the robbery
 *   - active  → active, share already ours       → INERT   (no needless write)
 *   - active  → active, share MISSING            → REPAIR  ← the lost grant
 *   - active  → paused / terminated              → revoke
 *   - delete (after undefined)                   → revoke
 *   - before AND after undefined                 → skipped
 *   - share owned by a different trainer         → never removed
 *
 * One sequence pins a KNOWN LIMIT rather than a guarantee: `paused → active` is
 * a trainer-only resume, and it still takes the share back from another trainer
 * who legitimately holds it. That is last-writer-wins over a genuine transition,
 * out of scope here — pinned so that changing it is deliberate.
 *
 * The last block runs SEQUENCES against one persisting store, because
 * `session_shares/{athleteId}` is state SHARED between events and between links:
 * both the robbery and the missing-share hole are properties of an ORDER of
 * writes, not of any single call.
 */

jest.mock("firebase-admin", () => {
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  firestore.FieldValue = {
    serverTimestamp: () => ({ __fakeFieldValue: "serverTimestamp" }),
  };
  return { firestore, app: jest.fn(), initializeApp: jest.fn() };
});

/**
 * The logger is mocked because ONE assertion genuinely needs it: the two exits
 * below the `get()` ("share is already ours" / "share is another trainer's")
 * both end without writing, so store and op log cannot tell them apart — only
 * the log line can. Logs are a deliberate observable here, not incidental:
 * `grantShare` takes a `reason` for exactly the same purpose.
 */
jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { syncSessionShareHandler } from "../sync-session-share";

/** Log assertions are per-test; without this they would see previous tests' calls. */
beforeEach(() => {
  (logger.info as jest.Mock).mockClear();
  (logger.warn as jest.Mock).mockClear();
});

const TRAINER_A = "trainer-A";
const TRAINER_B = "trainer-B";
const ATHLETE = "athlete-X";

const APP = {} as admin.app.App;

type LinkData = Record<string, unknown>;

/** Builds a trainer_links snapshot payload. */
function link(
  status: string,
  trainerId = TRAINER_A,
  extra: Record<string, unknown> = {},
): LinkData {
  return { trainerId, athleteId: ATHLETE, status, ...extra };
}

/**
 * A trainer_links doc that the entitlement sweep has just blocked. Same shape
 * `sync-entitlements.ts` writes: status untouched, paywall fields added.
 */
function blockedBySweep(status: string, trainerId = TRAINER_A): LinkData {
  return link(status, trainerId, {
    entitlement: "blocked",
    blockedAt: { __fakeTimestampMs: 1_700_000_000_000 },
    blockedReason: "over-limit",
  });
}

interface FakeStore {
  /** athleteId → session_shares doc data. */
  docs: Map<string, Record<string, unknown>>;
  /** Every doc operation the handler performed, in order. */
  ops: string[];
}

/**
 * Installs an in-memory Firestore behind `admin.firestore(app)`.
 * `seed` maps athleteId → trainerId for pre-existing share docs.
 */
function installFirestore(seed: Record<string, string> = {}): FakeStore {
  const docs = new Map<string, Record<string, unknown>>();
  for (const [athleteId, trainerId] of Object.entries(seed)) {
    docs.set(athleteId, { trainerId, updatedAt: "seeded" });
  }
  const ops: string[] = [];

  const db = {
    collection(name: string) {
      if (name !== "session_shares") {
        throw new Error(`unexpected collection: ${name}`);
      }
      return {
        doc(id: string) {
          return {
            async set(data: Record<string, unknown>): Promise<void> {
              ops.push(`set:${id}`);
              docs.set(id, data);
            },
            async get(): Promise<{
              exists: boolean;
              data: () => Record<string, unknown> | undefined;
            }> {
              ops.push(`get:${id}`);
              const data = docs.get(id);
              return { exists: data !== undefined, data: () => data };
            },
            async delete(): Promise<void> {
              ops.push(`delete:${id}`);
              docs.delete(id);
            },
          };
        },
      };
    },
  };

  (admin.firestore as unknown as jest.Mock).mockReturnValue(db);
  return { docs, ops };
}

/** Clears the op log so the NEXT step of a sequence can be asserted in isolation. */
function nextStep(store: FakeStore): void {
  store.ops.length = 0;
}

/** Who the share currently points at, `undefined` when there is no share doc. */
function shareOwner(store: FakeStore): string | undefined {
  return store.docs.get(ATHLETE)?.trainerId as string | undefined;
}

// ---------------------------------------------------------------------------
// Grant — the status actually became `active`
// ---------------------------------------------------------------------------

describe("status becomes active → share granted", () => {
  it("grants on create (before undefined)", async () => {
    const store = installFirestore();

    await syncSessionShareHandler(APP, undefined, link("active"));

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`set:${ATHLETE}`]);
  });

  it("grants on pending → active (accept)", async () => {
    const store = installFirestore();

    await syncSessionShareHandler(APP, link("pending"), link("active"));

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`set:${ATHLETE}`]);
  });

  it("grants on paused → active (resume)", async () => {
    const store = installFirestore();

    await syncSessionShareHandler(APP, link("paused"), link("active"));

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`set:${ATHLETE}`]);
  });

  it("takes the share over from another trainer on a real promotion", async () => {
    // A real transition into `active` writes WITHOUT reading first — no
    // ownership check applies. Legitimate for THIS case (pending → active: the
    // athlete created the request, firestore.rules ~487). NOT symmetrical for
    // paused → active, which no athlete takes part in — pinned as a known limit
    // in the sequences block below.
    const store = installFirestore({ [ATHLETE]: TRAINER_B });

    await syncSessionShareHandler(APP, link("pending"), link("active"));

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`set:${ATHLETE}`]);
  });
});

// ---------------------------------------------------------------------------
// The bug: a write that does NOT change the status must not STEAL the share.
// But it must still REBUILD one that is missing — the guard is by content.
// ---------------------------------------------------------------------------

describe("active → active (no transition) → guarded by content", () => {
  it("an entitlement write on an already-active link does NOT steal the share", async () => {
    // THIS is the test that matters. sync-entitlements.ts tx.updates
    // entitlement/blockedAt/blockedReason on links that stay `active`, which
    // fires this trigger. Without the guard the handler re-stamps the share and
    // steals it from the athlete's other trainer. It reads to find that out, so
    // one get() is expected — but never a write.
    const store = installFirestore({ [ATHLETE]: TRAINER_B });

    await syncSessionShareHandler(
      APP,
      link("active"),
      blockedBySweep("active"),
    );

    expect(shareOwner(store)).toBe(TRAINER_B);
    expect(store.ops).toEqual([`get:${ATHLETE}`]);
  });

  it("rebuilds a MISSING share while the link is still active", async () => {
    // The counterpart the status guard would have destroyed. A grant `set()`
    // that fails is never retried (no `retry: true` anywhere in this module), so
    // this repair is the only path back from a lost grant — and what is lost is
    // the trainer's read access to sessions, setLogs and measurements.
    const store = installFirestore();

    await syncSessionShareHandler(APP, link("active"), link("active"));

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`get:${ATHLETE}`, `set:${ATHLETE}`]);
  });

  it("rebuilds a share doc that exists but carries no trainerId", async () => {
    // Useless to every trainer — the rules compare
    // `session_shares/{uid}.data.trainerId == request.auth.uid`. Nobody claims
    // it, so it is not a steal to fix it.
    const store = installFirestore();
    store.docs.set(ATHLETE, { updatedAt: "seeded" });

    await syncSessionShareHandler(APP, link("active"), link("active"));

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`get:${ATHLETE}`, `set:${ATHLETE}`]);
  });

  it("does not rewrite a share that already points at this trainer", async () => {
    // Nothing to fix: re-setting it would only churn `updatedAt` and burn a
    // write on every sweep pass.
    //
    // WHY THE LOG ASSERTION. State alone does NOT pin this branch: delete the
    // `existingTrainerId === trainerId` check and this case falls through to
    // the "belongs to a different trainer" exit, which also returns without
    // writing — same store, same ops, green test. The two exits differ only in
    // the log line, so that is what discriminates them. Verified by removing
    // the branch: without these two expectations the suite stays green, with
    // them it goes red.
    const store = installFirestore({ [ATHLETE]: TRAINER_A });

    await syncSessionShareHandler(APP, link("active"), link("active"));

    expect(store.docs.get(ATHLETE)?.updatedAt).toBe("seeded");
    expect(store.ops).toEqual([`get:${ATHLETE}`]);
    expect(logger.info).toHaveBeenCalledWith(
      "syncSessionShare: share already correct, skipping",
      { trainerId: TRAINER_A, athleteId: ATHLETE },
    );
    expect(logger.info).not.toHaveBeenCalledWith(
      expect.stringContaining("belongs to a different trainer"),
      expect.anything(),
    );
  });

  it("rebuilds the share of a trainer whose own link the sweep just blocked", async () => {
    // `entitlement: 'blocked'` is NOT a revocation: the sweep leaves `status`
    // alone and `entitlement` gates no read clause in firestore.rules. The link
    // is still active, so the athlete's share still belongs to this trainer.
    const store = installFirestore();

    await syncSessionShareHandler(
      APP,
      link("active"),
      blockedBySweep("active"),
    );

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`get:${ATHLETE}`, `set:${ATHLETE}`]);
  });
});

// ---------------------------------------------------------------------------
// Revoke — status left `active`, or the doc is gone
// ---------------------------------------------------------------------------

describe("status leaves active → share revoked", () => {
  it("revokes on active → paused", async () => {
    const store = installFirestore({ [ATHLETE]: TRAINER_A });

    await syncSessionShareHandler(APP, link("active"), link("paused"));

    expect(store.docs.has(ATHLETE)).toBe(false);
    expect(store.ops).toEqual([`get:${ATHLETE}`, `delete:${ATHLETE}`]);
  });

  it("revokes on active → terminated", async () => {
    const store = installFirestore({ [ATHLETE]: TRAINER_A });

    await syncSessionShareHandler(APP, link("active"), link("terminated"));

    expect(store.docs.has(ATHLETE)).toBe(false);
  });

  it("revokes on delete (after undefined)", async () => {
    const store = installFirestore({ [ATHLETE]: TRAINER_A });

    await syncSessionShareHandler(APP, link("active"), undefined);

    expect(store.docs.has(ATHLETE)).toBe(false);
    expect(store.ops).toEqual([`get:${ATHLETE}`, `delete:${ATHLETE}`]);
  });

  it("still cleans up an orphan share on a non-active no-op write", async () => {
    // The revoke path does not check for a transition, on purpose: a share that
    // outlived its link is stale by definition. Safe because the grant path now
    // rebuilds — see the same-trainer sequence below.
    const store = installFirestore({ [ATHLETE]: TRAINER_A });

    await syncSessionShareHandler(APP, link("paused"), link("paused"));

    expect(store.docs.has(ATHLETE)).toBe(false);
  });

  it("does nothing when there is no share to remove", async () => {
    const store = installFirestore();

    await syncSessionShareHandler(APP, link("active"), link("terminated"));

    expect(store.ops).toEqual([`get:${ATHLETE}`]);
  });
});

// ---------------------------------------------------------------------------
// The share belongs to a DIFFERENT trainer → never removed
// ---------------------------------------------------------------------------

describe("share owned by another trainer → never removed", () => {
  it("leaves it alone when this link is terminated", async () => {
    const store = installFirestore({ [ATHLETE]: TRAINER_B });

    await syncSessionShareHandler(
      APP,
      link("active", TRAINER_A),
      link("terminated", TRAINER_A),
    );

    expect(shareOwner(store)).toBe(TRAINER_B);
    expect(store.ops).toEqual([`get:${ATHLETE}`]);
  });

  it("leaves it alone when this link is deleted", async () => {
    const store = installFirestore({ [ATHLETE]: TRAINER_B });

    await syncSessionShareHandler(APP, link("active", TRAINER_A), undefined);

    expect(shareOwner(store)).toBe(TRAINER_B);
    expect(store.ops).toEqual([`get:${ATHLETE}`]);
  });
});

// ---------------------------------------------------------------------------
// Malformed events
// ---------------------------------------------------------------------------

describe("malformed events", () => {
  it("skips when before AND after are both missing", async () => {
    const store = installFirestore({ [ATHLETE]: TRAINER_A });

    await expect(
      syncSessionShareHandler(APP, undefined, undefined),
    ).resolves.toBeUndefined();

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([]);
  });

  it("skips when trainerId is missing", async () => {
    const store = installFirestore();

    await syncSessionShareHandler(APP, undefined, {
      athleteId: ATHLETE,
      status: "active",
    });

    expect(store.ops).toEqual([]);
  });

  it("skips when athleteId is missing", async () => {
    const store = installFirestore();

    await syncSessionShareHandler(APP, undefined, {
      trainerId: TRAINER_A,
      status: "active",
    });

    expect(store.ops).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// SEQUENCES — one store, several events, several links.
//
// Single-call tests cannot see either failure mode: `session_shares/{athleteId}`
// is one doc shared by every link of that athlete, so both the robbery and the
// missing-share hole only exist across an ORDER of writes.
// ---------------------------------------------------------------------------

describe("sequences over a persisting store", () => {
  it("the full robbery: the sweep on PF1's link never moves PF2's share", async () => {
    // The production incident, end to end. One athlete, two trainers, both
    // links active. PF1 goes over its plan limit, the entitlement sweep stamps
    // `entitlement: 'blocked'` on PF1's link — a write that changes no status —
    // and PF2, fully paid up, must not lose the athlete.
    const store = installFirestore();

    // 1. PF1 gets accepted first.
    await syncSessionShareHandler(
      APP,
      link("pending", TRAINER_A),
      link("active", TRAINER_A),
    );
    expect(shareOwner(store)).toBe(TRAINER_A);

    // 2. The athlete then accepts PF2 too. The share legitimately moves.
    await syncSessionShareHandler(
      APP,
      link("pending", TRAINER_B),
      link("active", TRAINER_B),
    );
    expect(shareOwner(store)).toBe(TRAINER_B);

    // 3. The sweep blocks PF1's still-active link. THE ROBBERY GOES HERE.
    nextStep(store);
    await syncSessionShareHandler(
      APP,
      link("active", TRAINER_A),
      blockedBySweep("active", TRAINER_A),
    );

    expect(shareOwner(store)).toBe(TRAINER_B);
    expect(store.ops).toEqual([`get:${ATHLETE}`]);

    // 4. Enforcement re-runs the sweep. Idempotent — still no write.
    nextStep(store);
    await syncSessionShareHandler(
      APP,
      blockedBySweep("active", TRAINER_A),
      blockedBySweep("active", TRAINER_A),
    );

    expect(shareOwner(store)).toBe(TRAINER_B);
    expect(store.ops).toEqual([`get:${ATHLETE}`]);
  });

  it("repairs a share lost after the grant, on the next write to the live link", async () => {
    const store = installFirestore();

    // 1. Link goes active, share granted.
    await syncSessionShareHandler(APP, link("pending"), link("active"));
    expect(shareOwner(store)).toBe(TRAINER_A);

    // 2. The share disappears — a failed grant `set()`, a bad manual cleanup,
    //    an old link of the same pair being terminated (see the sequence below).
    store.docs.delete(ATHLETE);

    // 3. Any later write to the still-active link rebuilds it. Without this the
    //    trainer's read access is gone for good: nothing retries the grant.
    nextStep(store);
    await syncSessionShareHandler(
      APP,
      link("active"),
      blockedBySweep("active"),
    );

    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`get:${ATHLETE}`, `set:${ATHLETE}`]);
  });

  it("terminating an OLD link of the same pair is repaired by the live one", async () => {
    // firestore.rules allows several historical links per trainer/athlete pair
    // (~473). Terminating the old one deletes the share the NEW, active link of
    // the SAME trainer needs — the trainerId check cannot tell them apart. This
    // is the hole that made an unconditional revoke dangerous; the content guard
    // on the grant path is what closes it.
    const store = installFirestore();

    // 1. New link of the pair goes active.
    await syncSessionShareHandler(APP, link("pending"), link("active"));
    expect(shareOwner(store)).toBe(TRAINER_A);

    // 2. The old, duplicate link of the SAME pair is terminated. Same trainerId,
    //    so the ownership check passes and the share is deleted.
    nextStep(store);
    await syncSessionShareHandler(APP, link("active"), link("terminated"));
    expect(shareOwner(store)).toBeUndefined();
    expect(store.ops).toEqual([`get:${ATHLETE}`, `delete:${ATHLETE}`]);

    // 3. The next write on the live link puts it back.
    nextStep(store);
    await syncSessionShareHandler(APP, link("active"), link("active"));
    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`get:${ATHLETE}`, `set:${ATHLETE}`]);
  });

  it("KNOWN LIMIT: PF1 resuming its paused link takes the share back from PF2", async () => {
    // Pinned AS IT IS TODAY, not as it should be. `paused → active` is a resume
    // driven by the TRAINER alone (resumeTrainerLink; promote-link.ts rejects
    // any caller that is not the link's trainer) — the athlete takes no part in
    // it — yet it counts as a real transition and overwrites another trainer's
    // live claim.
    //
    // Out of scope on purpose: this is last-writer-wins over a GENUINE
    // transition, a limit of `session_shares/{athleteId}` holding ONE trainerId.
    // What this version killed is the INVOLUNTARY steal — the no-transition
    // writes of the entitlement sweep. Arbitrating between two live trainers
    // needs a different document shape and is its own change. This test exists
    // so that changing the branch is a decision, not an accident.
    const store = installFirestore();

    // 1. PF1 accepts the athlete's request → PF1 holds the share.
    await syncSessionShareHandler(
      APP,
      link("pending", TRAINER_A),
      link("active", TRAINER_A),
    );
    expect(shareOwner(store)).toBe(TRAINER_A);

    // 2. PF1 pauses the link → share revoked.
    await syncSessionShareHandler(
      APP,
      link("active", TRAINER_A),
      link("paused", TRAINER_A),
    );
    expect(shareOwner(store)).toBeUndefined();

    // 3. PF2 accepts the athlete's request → PF2 holds the share, legitimately.
    await syncSessionShareHandler(
      APP,
      link("pending", TRAINER_B),
      link("active", TRAINER_B),
    );
    expect(shareOwner(store)).toBe(TRAINER_B);

    // 4. PF1 resumes. No athlete action in this step at all, and PF2 — paid up,
    //    link still active — loses sessions, setLogs and measurements.
    nextStep(store);
    await syncSessionShareHandler(
      APP,
      link("paused", TRAINER_A),
      link("active", TRAINER_A),
    );

    expect(shareOwner(store)).toBe(TRAINER_A);
    // No get(): the transition branch writes without looking at who held it.
    expect(store.ops).toEqual([`set:${ATHLETE}`]);
  });

  it("a legitimate change of trainer still moves the share", async () => {
    // The guard must not freeze the share on its first owner: a real transition
    // into `active` overrides whoever holds it.
    const store = installFirestore();

    await syncSessionShareHandler(
      APP,
      link("pending", TRAINER_A),
      link("active", TRAINER_A),
    );
    expect(shareOwner(store)).toBe(TRAINER_A);

    // PF2 gets accepted → PF2 owns the share now.
    nextStep(store);
    await syncSessionShareHandler(
      APP,
      link("pending", TRAINER_B),
      link("active", TRAINER_B),
    );
    expect(shareOwner(store)).toBe(TRAINER_B);
    expect(store.ops).toEqual([`set:${ATHLETE}`]);

    // PF1 is then terminated. Its share is already PF2's → left alone.
    nextStep(store);
    await syncSessionShareHandler(
      APP,
      link("active", TRAINER_A),
      link("terminated", TRAINER_A),
    );
    expect(shareOwner(store)).toBe(TRAINER_B);
    expect(store.ops).toEqual([`get:${ATHLETE}`]);
  });

  it("revoke then re-grant: pause, resume, terminate, re-accept", async () => {
    const store = installFirestore();

    await syncSessionShareHandler(APP, link("pending"), link("active"));
    expect(shareOwner(store)).toBe(TRAINER_A);

    // Trainer pauses the link → share gone.
    await syncSessionShareHandler(APP, link("active"), link("paused"));
    expect(shareOwner(store)).toBeUndefined();

    // A write while paused must not resurrect it.
    nextStep(store);
    await syncSessionShareHandler(APP, link("paused"), link("paused"));
    expect(shareOwner(store)).toBeUndefined();
    expect(store.ops).toEqual([`get:${ATHLETE}`]);

    // Resume → share back.
    await syncSessionShareHandler(APP, link("paused"), link("active"));
    expect(shareOwner(store)).toBe(TRAINER_A);

    // Terminate → gone again.
    await syncSessionShareHandler(APP, link("active"), link("terminated"));
    expect(shareOwner(store)).toBeUndefined();

    // A brand-new link of the pair is accepted → granted from scratch.
    nextStep(store);
    await syncSessionShareHandler(APP, link("pending"), link("active"));
    expect(shareOwner(store)).toBe(TRAINER_A);
    expect(store.ops).toEqual([`set:${ATHLETE}`]);
  });
});
