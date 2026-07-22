/**
 * Integration tests for the athlete-owned data cascade module (QA-CMP-003).
 * Run against the Firebase Local Emulator (Firestore).
 *
 * Verifies that every athlete-owned / athlete-about collection is deleted for
 * the target uid, and that another athlete's data is left untouched.
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "athlete-data-cascade-test"
  );
});

afterAll(async () => {
  await testApp.delete();
});

import { deleteAthleteOwnedData } from "../../cascade/athlete-data";

const db = () => admin.firestore(testApp);

const FIELD_COLLECTIONS = [
  "measurements",
  "performance_tests",
  "athlete_billing",
  "athlete_notes",
  "follow_up_entries",
  "nutrition_plans",
];
const DOC_ID_COLLECTIONS = ["profile_shares", "session_shares"];

async function seedFor(uid: string): Promise<void> {
  const batch = db().batch();
  for (const coll of FIELD_COLLECTIONS) {
    // two docs per collection to exercise the batched query delete
    batch.set(db().collection(coll).doc(`${coll}-${uid}-1`), {
      athleteId: uid,
      trainerId: "trainer-x",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(db().collection(coll).doc(`${coll}-${uid}-2`), {
      athleteId: uid,
      trainerId: "trainer-x",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  for (const coll of DOC_ID_COLLECTIONS) {
    batch.set(db().collection(coll).doc(uid), {
      athleteId: uid,
      sharedWith: "trainer-x",
    });
  }
  await batch.commit();
}

async function countFor(uid: string): Promise<number> {
  let total = 0;
  for (const coll of FIELD_COLLECTIONS) {
    const snap = await db().collection(coll).where("athleteId", "==", uid).get();
    total += snap.size;
  }
  for (const coll of DOC_ID_COLLECTIONS) {
    if ((await db().collection(coll).doc(uid).get()).exists) total += 1;
  }
  return total;
}

describe("deleteAthleteOwnedData — QA-CMP-003", () => {
  const uid = "athlete-cmp";
  const other = "athlete-other";

  afterEach(async () => {
    // Best-effort cleanup of the control athlete.
    await deleteAthleteOwnedData(testApp, other);
  });

  it("deletes every athlete-owned/about collection for the target uid", async () => {
    await seedFor(uid);
    expect(await countFor(uid)).toBe(
      FIELD_COLLECTIONS.length * 2 + DOC_ID_COLLECTIONS.length
    );

    const { deleted } = await deleteAthleteOwnedData(testApp, uid);

    expect(deleted).toBe(
      FIELD_COLLECTIONS.length * 2 + DOC_ID_COLLECTIONS.length
    );
    expect(await countFor(uid)).toBe(0);
  });

  it("leaves another athlete's data untouched", async () => {
    await seedFor(uid);
    await seedFor(other);

    await deleteAthleteOwnedData(testApp, uid);

    expect(await countFor(uid)).toBe(0);
    expect(await countFor(other)).toBe(
      FIELD_COLLECTIONS.length * 2 + DOC_ID_COLLECTIONS.length
    );
  });

  it("is a no-op when the athlete has no data", async () => {
    const { deleted } = await deleteAthleteOwnedData(testApp, "nobody-here");
    expect(deleted).toBe(0);
  });
});
