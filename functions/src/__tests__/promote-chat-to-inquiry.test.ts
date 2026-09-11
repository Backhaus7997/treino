/**
 * promote-chat-to-inquiry.test.ts — LOCAL, no emulator.
 *
 * Pure-mock unit tests for `runPromoteChatToInquiry` (the transactional
 * handler) and for the guard branches of the `promoteChatToInquiry` onCall
 * wrapper. Mirrors accept-trainer-link.test.ts's style: `firebase-admin/app`
 * and `firebase-admin/firestore` are mocked through the
 * `modular-from-namespaced` doble so production's `getFirestore(app)` call
 * resolves to an in-memory fake instead of touching real Firestore.
 *
 * No existing helper in `__tests__/helpers/` models `chats` /
 * `trainerPublicProfiles` transactions — `fake-tx-firestore.ts` is scoped to
 * `trainer_links` / `users` (paywall Fase 7). Per purge-rejected-link.test.ts's
 * precedent (a production file that also does a bare
 * `getFirestore(app).collection().doc()` without FieldValue/Timestamp), the
 * Firestore double here is a small inline fake built for exactly the shape
 * `runPromoteChatToInquiry` uses: `collection(name).doc(id)`,
 * `runTransaction(fn)`, `tx.get(ref)` / `tx.update(ref, data)`.
 *
 * The wrapper's auth/data guards (cases 14/15) are exercised via
 * `promoteChatToInquiry.run(request)` — the method firebase-functions v2
 * itself documents as "Used for unit testing" (see
 * node_modules/firebase-functions/lib/v2/providers/https.d.ts). It is exactly
 * what `firebase-functions-test`'s `wrapV2()` does internally for a v2
 * callable (`return (req) => cloudFunction.run(req)` —
 * node_modules/firebase-functions-test/lib/v2.js), so no emulator, no
 * `firebase-functions-test` import, and no HTTP layer are involved. Both
 * guarded cases return before `ensureApp()`/`getFirestore()` are ever called.
 */

jest.mock("firebase-admin", () => ({
  firestore: jest.fn(),
}));

// La puerta MODULAR tiene que dar el MISMO doble que la namespaced de arriba
// (ver purge-rejected-link.test.ts / firebase-admin-mock-surface.test.ts):
// producción importa `getFirestore`/`getApp`/`initializeApp` de los subpaths
// modulares, y sin esto se lleva el SDK REAL por la puerta de al lado.
jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());

jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

import { App } from "firebase-admin/app";
import { dobleNamespaced } from "./helpers/modular-from-namespaced";
import {
  promoteChatToInquiry,
  runPromoteChatToInquiry,
} from "../chat/promote-chat-to-inquiry";

const app = {} as App;

// ─── Inline Firestore double ────────────────────────────────────────────────

type Coll = "chats" | "users" | "trainerPublicProfiles";
type DocData = Record<string, unknown>;
type Store = Record<Coll, Record<string, DocData>>;

interface FakeRef {
  readonly collectionName: Coll;
  readonly id: string;
}

function makeSnapshot(store: Store, ref: FakeRef) {
  const data = store[ref.collectionName][ref.id];
  return {
    exists: data !== undefined,
    get: (field: string) => data?.[field],
    data: () => data,
  };
}

function installFirestore(seed: Partial<Store> = {}) {
  const store: Store = {
    chats: { ...(seed.chats ?? {}) },
    users: { ...(seed.users ?? {}) },
    trainerPublicProfiles: { ...(seed.trainerPublicProfiles ?? {}) },
  };

  const docCalls: FakeRef[] = [];

  const tx = {
    get: jest.fn(async (ref: FakeRef) => makeSnapshot(store, ref)),
    update: jest.fn((ref: FakeRef, data: DocData) => {
      const existing = store[ref.collectionName][ref.id];
      store[ref.collectionName][ref.id] = { ...(existing ?? {}), ...data };
    }),
  };

  const db = {
    collection: jest.fn((name: Coll) => ({
      doc: jest.fn((id: string) => {
        const ref: FakeRef = { collectionName: name, id };
        docCalls.push(ref);
        return ref;
      }),
    })),
    runTransaction: jest.fn(async (fn: (tx: unknown) => Promise<unknown>) =>
      fn(tx),
    ),
  };

  (dobleNamespaced().firestore as unknown as jest.Mock).mockReturnValue(db);

  return { db, tx, store, docCalls };
}

function firestoreFactory(): jest.Mock {
  return dobleNamespaced().firestore as unknown as jest.Mock;
}

const callerUid = "athlete-1";
const trainerId = "trainer-1";

function chat(overrides: DocData = {}): DocData {
  return { members: [callerUid, trainerId], ...overrides };
}

beforeEach(() => {
  jest.clearAllMocks();
});

// ─── 1/2 — input validation, before Firestore is ever touched ──────────────

describe("runPromoteChatToInquiry — input validation", () => {
  it("case 1: rejects an empty trainerId with invalid-argument and never touches Firestore", async () => {
    const promise = runPromoteChatToInquiry(app, callerUid, "");
    await expect(promise).rejects.toMatchObject({ code: "invalid-argument" });
    expect(firestoreFactory()).not.toHaveBeenCalled();
  });

  it("case 2: rejects trainerId === callerUid with invalid-argument and never touches Firestore", async () => {
    const promise = runPromoteChatToInquiry(app, callerUid, callerUid);
    await expect(promise).rejects.toMatchObject({ code: "invalid-argument" });
    expect(firestoreFactory()).not.toHaveBeenCalled();
  });
});

// ─── 3/4 — chat existence and real membership check ─────────────────────────

describe("runPromoteChatToInquiry — chat existence and membership", () => {
  it("case 3: rejects with not-found when the chat document does not exist", async () => {
    installFirestore({});
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("case 4: rejects with permission-denied when caller is not in members (two OTHER uids)", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    installFirestore({
      chats: { [chatId]: chat({ members: ["someone-else-1", "someone-else-2"] }) },
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).rejects.toMatchObject({ code: "permission-denied" });
  });
});

// ─── 5/6/7 — already-promoted noop and wrong-kind precondition ─────────────

describe("runPromoteChatToInquiry — noop and wrong-kind precondition", () => {
  it("case 5: returns {status:'noop'} when linkId is already present, and never calls tx.update", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    const { tx } = installFirestore({
      chats: { [chatId]: chat({ linkId: "L1" }) },
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).resolves.toEqual({ status: "noop" });
    expect(tx.update).not.toHaveBeenCalled();
  });

  it("case 6: returns {status:'noop'} when kind is already 'inquiry', and never calls tx.update", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    const { tx } = installFirestore({
      chats: { [chatId]: chat({ kind: "inquiry" }) },
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).resolves.toEqual({ status: "noop" });
    expect(tx.update).not.toHaveBeenCalled();
  });

  it("case 7: rejects with failed-precondition when kind is neither absent nor 'inquiry' (e.g. 'coach')", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    installFirestore({
      chats: { [chatId]: chat({ kind: "coach" }) },
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });
});

// ─── 8/9/10 — trainer eligibility ladder ────────────────────────────────────

describe("runPromoteChatToInquiry — trainer eligibility", () => {
  it("case 8: rejects with failed-precondition when users/{trainerId}.role isn't 'trainer', and never calls tx.update", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    const { tx } = installFirestore({
      chats: { [chatId]: chat() },
      users: { [trainerId]: { role: "athlete" } },
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).rejects.toMatchObject({ code: "failed-precondition" });
    expect(tx.update).not.toHaveBeenCalled();
  });

  it("case 9: rejects with failed-precondition when trainerPublicProfiles/{trainerId} does not exist", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    installFirestore({
      chats: { [chatId]: chat() },
      users: { [trainerId]: { role: "trainer" } },
      trainerPublicProfiles: {},
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("case 10: rejects with failed-precondition when acceptsInquiries === false", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    installFirestore({
      chats: { [chatId]: chat() },
      users: { [trainerId]: { role: "trainer" } },
      trainerPublicProfiles: { [trainerId]: { acceptsInquiries: false } },
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });
});

// ─── 11/12 — happy path, including the acceptsInquiries default ────────────

describe("runPromoteChatToInquiry — happy path", () => {
  it("case 11: returns {status:'ok'} and stamps EXACTLY {kind:'inquiry'} via tx.update", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    const { tx } = installFirestore({
      chats: { [chatId]: chat() },
      users: { [trainerId]: { role: "trainer" } },
      trainerPublicProfiles: { [trainerId]: { acceptsInquiries: true } },
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).resolves.toEqual({ status: "ok" });
    expect(tx.update).toHaveBeenCalledTimes(1);
    expect(tx.update).toHaveBeenCalledWith(
      expect.objectContaining({ collectionName: "chats", id: chatId }),
      { kind: "inquiry" },
    );
  });

  it("case 12: succeeds when acceptsInquiries is ABSENT (default is 'accept', mirrors chat.get('acceptsInquiries', true) in rules)", async () => {
    const chatId = [callerUid, trainerId].sort().join("_");
    const { tx } = installFirestore({
      chats: { [chatId]: chat() },
      users: { [trainerId]: { role: "trainer" } },
      trainerPublicProfiles: { [trainerId]: {} },
    });
    await expect(
      runPromoteChatToInquiry(app, callerUid, trainerId),
    ).resolves.toEqual({ status: "ok" });
    expect(tx.update).toHaveBeenCalledWith(expect.anything(), { kind: "inquiry" });
  });
});

// ─── 13 — chat id is DERIVED via sort().join('_'), not naive concatenation ──

describe("runPromoteChatToInquiry — chat id derivation", () => {
  it("case 13a: reads doc id sort().join('_') when callerUid is alphabetically AFTER trainerId", async () => {
    const { docCalls } = installFirestore({});
    await expect(
      runPromoteChatToInquiry(app, "zoe", "amir"),
    ).rejects.toMatchObject({ code: "not-found" });
    expect(docCalls).toContainEqual({ collectionName: "chats", id: "amir_zoe" });
  });

  it("case 13b: reads doc id sort().join('_') when callerUid is alphabetically BEFORE trainerId", async () => {
    const { docCalls } = installFirestore({});
    await expect(
      runPromoteChatToInquiry(app, "amir", "zoe"),
    ).rejects.toMatchObject({ code: "not-found" });
    expect(docCalls).toContainEqual({ collectionName: "chats", id: "amir_zoe" });
  });
});

// ─── 14/15 — onCall wrapper guards, via .run() (no emulator, no HTTP layer) ─

describe("promoteChatToInquiry — onCall wrapper guards", () => {
  it("case 14: rejects with unauthenticated when request.auth is absent", async () => {
    const request = {
      data: { trainerId },
    } as unknown as Parameters<typeof promoteChatToInquiry.run>[0];

    await expect(promoteChatToInquiry.run(request)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });

  it("case 15: rejects with invalid-argument when trainerId is missing from data", async () => {
    const request = {
      auth: { uid: callerUid },
      data: {},
    } as unknown as Parameters<typeof promoteChatToInquiry.run>[0];

    await expect(promoteChatToInquiry.run(request)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });
});
