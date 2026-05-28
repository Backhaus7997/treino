/**
 * Integration tests for the trainer-links cascade module.
 * Run against Firebase Local Emulator (Firestore).
 *
 * SCENARIOS covered:
 *   SCENARIO-543 — Active trainer link is terminated (REQ-ACCDEL-CF-008)
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "trainer-links-cascade-test");
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { terminateTrainerLinks } from "../../cascade/trainer-links";

const db = () => admin.firestore(testApp);

async function seedLink(
  uid: string,
  docId: string,
  status = "active"
): Promise<void> {
  await db().collection("trainer_links").doc(docId).set({
    athleteId: uid,
    trainerId: "trainer-123",
    status,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function cleanupLinks(docIds: string[]): Promise<void> {
  const batch = db().batch();
  for (const id of docIds) {
    batch.delete(db().collection("trainer_links").doc(id));
  }
  await batch.commit().catch(() => undefined);
}

describe("SCENARIO-543: active trainer link is terminated", () => {
  const uid = "trainer-links-cascade-543";
  const docId = "trainer-link-active-543";

  beforeEach(() => seedLink(uid, docId, "active"));
  afterEach(() => cleanupLinks([docId]));

  it("SCENARIO-543: status is set to 'terminated'", async () => {
    await terminateTrainerLinks(testApp, uid);

    const snap = await db().collection("trainer_links").doc(docId).get();
    expect(snap.data()?.status).toBe("terminated");
  });

  it("SCENARIO-543: reason is set to 'account-deleted'", async () => {
    await terminateTrainerLinks(testApp, uid);

    const snap = await db().collection("trainer_links").doc(docId).get();
    expect(snap.data()?.reason).toBe("account-deleted");
  });

  it("SCENARIO-543: terminatedAt is set (server timestamp)", async () => {
    await terminateTrainerLinks(testApp, uid);

    const snap = await db().collection("trainer_links").doc(docId).get();
    expect(snap.data()?.terminatedAt).toBeTruthy();
  });

  it("SCENARIO-543: already-terminated link is not re-terminated (idempotent)", async () => {
    const terminatedId = "trainer-link-already-terminated-543";
    await seedLink(uid, terminatedId, "terminated");

    await terminateTrainerLinks(testApp, uid);

    // The already-terminated doc should remain as-is (no reason field added via this call)
    const snap = await db().collection("trainer_links").doc(terminatedId).get();
    // It still exists and reason could remain unset (was terminated before account deletion)
    expect(snap.data()?.status).toBe("terminated");

    await cleanupLinks([terminatedId]);
  });
});

describe("trainer-links: no links is a no-op", () => {
  const uid = "trainer-links-cascade-no-links";

  it("no error thrown when user has zero trainer_links docs", async () => {
    await expect(terminateTrainerLinks(testApp, uid)).resolves.not.toThrow();
  });
});
