/**
 * fake-tx-firestore.ts — hand-rolled fake Firestore transaction for LOCAL
 * tests of transactional helpers (paywall Fase 7, PR4, design D-6).
 *
 * NOT a full Firestore emulator substitute — a minimal in-memory double that
 * supports exactly the shape `syncTrainerLoad` (promote-link.ts) and
 * `linkLoadReconcile` (link-load-reconcile.ts) use: `doc().get()`,
 * `where(field, '==', value)` queries, `tx.update()`, `tx.set(..., {merge})`.
 *
 * THE LOAD-BEARING PART: `tx.get()` THROWS if called after any `tx.update()`
 * / `tx.set()` in the same transaction. Firestore's real rule is
 * reads-before-writes (all reads must happen before the first write); this
 * fake enforces that invariant locally so the ordering bug class is caught
 * by a fast unit test instead of only by the `[EMULATOR-CI]` test (which
 * can't run locally — Java 21 isn't available here). The emulator test
 * confirms the same invariant against real Firestore; this fake is the
 * primary, always-runnable net.
 *
 * Install via `(admin.firestore as unknown as jest.Mock).mockReturnValue(db)`
 * after `jest.mock("firebase-admin", () => ({ firestore: jest.fn() }))` —
 * mirrors send-fcm-unit.test.ts's fake-Firestore pattern.
 */

export type FakeCollectionName = "trainer_links" | "users";

export type FakeDoc = Record<string, unknown>;

/** In-memory seed / post-transaction state, keyed by collection then doc id. */
export interface FakeFirestoreState {
  trainer_links: Record<string, FakeDoc>;
  users: Record<string, FakeDoc>;
}

export class FakeDocRef {
  constructor(
    public readonly collectionName: FakeCollectionName,
    public readonly id: string,
  ) {}
}

class FakeQuery {
  constructor(
    public readonly collectionName: FakeCollectionName,
    public readonly field: string,
    public readonly op: "==",
    public readonly value: unknown,
  ) {}
}

class FakeCollectionRef {
  constructor(private readonly collectionName: FakeCollectionName) {}

  doc(id: string): FakeDocRef {
    return new FakeDocRef(this.collectionName, id);
  }

  where(field: string, op: "==", value: unknown): FakeQuery {
    return new FakeQuery(this.collectionName, field, op, value);
  }
}

/**
 * Thrown by `tx.get()` when called after a write — the exact defect class
 * this fake exists to catch locally.
 */
export class ReadAfterWriteError extends Error {
  constructor() {
    super(
      "FakeTx: get() called after a write in the same transaction — " +
        "violates Firestore's reads-before-writes rule.",
    );
  }
}

export class FakeTransaction {
  private wrote = false;

  constructor(private readonly state: FakeFirestoreState) {}

  async get(
    target: FakeDocRef | FakeQuery,
  ): Promise<
    | { exists: boolean; id: string; data: () => FakeDoc | undefined }
    | { docs: { id: string; data: () => FakeDoc }[] }
  > {
    if (this.wrote) throw new ReadAfterWriteError();

    if (target instanceof FakeDocRef) {
      const data = this.state[target.collectionName][target.id];
      return { exists: data !== undefined, id: target.id, data: () => data };
    }

    const docs = Object.entries(this.state[target.collectionName])
      .filter(([, data]) => (data as FakeDoc)[target.field] === target.value)
      .map(([id, data]) => ({ id, data: () => data }));
    return { docs };
  }

  update(ref: FakeDocRef, data: FakeDoc): void {
    this.wrote = true;
    const existing = this.state[ref.collectionName][ref.id];
    if (existing === undefined) {
      throw new Error(`FakeTx: update() on missing doc ${ref.collectionName}/${ref.id}`);
    }
    this.state[ref.collectionName][ref.id] = { ...existing, ...data };
  }

  set(ref: FakeDocRef, data: FakeDoc, opts?: { merge?: boolean }): void {
    this.wrote = true;
    const existing = this.state[ref.collectionName][ref.id];
    this.state[ref.collectionName][ref.id] =
      opts?.merge && existing !== undefined ? { ...existing, ...data } : data;
  }
}

export interface FakeFirestore {
  collection(name: FakeCollectionName): FakeCollectionRef;
  runTransaction<T>(fn: (tx: FakeTransaction) => Promise<T>): Promise<T>;
}

/**
 * Builds a fake Firestore whose `runTransaction` hands the callback a single
 * `FakeTransaction` shared across the call — mirrors real Firestore's
 * single-transaction-object-per-attempt semantics (no retry simulation here;
 * concurrency/retry is covered by the `[EMULATOR-CI]` test).
 */
export function createFakeFirestore(seed: Partial<FakeFirestoreState> = {}): {
  db: FakeFirestore;
  state: FakeFirestoreState;
} {
  const state: FakeFirestoreState = {
    trainer_links: { ...(seed.trainer_links ?? {}) },
    users: { ...(seed.users ?? {}) },
  };

  const db: FakeFirestore = {
    collection: (name) => new FakeCollectionRef(name),
    runTransaction: async (fn) => fn(new FakeTransaction(state)),
  };

  return { db, state };
}
