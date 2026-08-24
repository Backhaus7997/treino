/**
 * Unit/integration tests for the users cascade module.
 * Run against Firebase Local Emulator (Firestore).
 *
 * SCENARIOS covered:
 *   SCENARIO-536 — Main profile docs deleted on success (REQ-ACCDEL-CF-004)
 *   SCENARIO-537 — trainerPublicProfiles deletion is no-op when absent (REQ-ACCDEL-CF-004)
 *   SCENARIO-643 — wellbeingCheckIns leaves no residue (#643, docs/security.md §2.2)
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "users-cascade-test");
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { deleteUserDocs } from "../../cascade/users";

const db = () => admin.firestore(testApp);

async function seed(uid: string): Promise<void> {
  const batch = db().batch();
  batch.set(db().collection("users").doc(uid), { uid, role: "athlete" });
  batch.set(db().collection("userPublicProfiles").doc(uid), { uid, displayName: "Test User" });
  // Seed 3 sub-collection docs (sessions)
  for (let i = 0; i < 3; i++) {
    batch.set(db().collection("users").doc(uid).collection("sessions").doc(`session-${i}`), { i });
  }
  // Seed the wellbeing check-in sub-collection (#643). Self-reported health is
  // the most sensitive data the app stores, so it gets its own assertion rather
  // than riding along untested on the sessions one.
  for (const id of ["2026-08-24_1787529600000", "2026-08-24_1787540400000"]) {
    batch.set(
      db().collection("users").doc(uid).collection("wellbeingCheckIns").doc(id),
      { date: "2026-08-24", feeling: "bad", hasPain: true, painAreas: ["back"] }
    );
  }
  await batch.commit();
}

async function cleanup(uid: string): Promise<void> {
  await db().collection("audit_log").doc(uid).delete().catch(() => undefined);
  await db().collection("userPublicProfiles").doc(uid).delete().catch(() => undefined);
  await db().collection("trainerPublicProfiles").doc(uid).delete().catch(() => undefined);
  // recursiveDelete covers users + sub-collections
  await db().recursiveDelete(db().collection("users").doc(uid)).catch(() => undefined);
}

describe("SCENARIO-536: main profile docs deleted on success", () => {
  const uid = "users-cascade-536";

  beforeEach(() => seed(uid));
  afterEach(() => cleanup(uid));

  it("SCENARIO-536: users/{uid} is deleted (recursively including sessions)", async () => {
    await deleteUserDocs(testApp, uid);

    const userSnap = await db().collection("users").doc(uid).get();
    expect(userSnap.exists).toBe(false);

    const sessionSnap = await db()
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .doc("session-0")
      .get();
    expect(sessionSnap.exists).toBe(false);
  });

  // #643 — a NEW sub-collection under users/{uid} is only covered because
  // deleteUserDocs uses recursiveDelete on the parent document. That is a
  // property of the Admin SDK call, not of the sub-collection, and nothing
  // else in the suite would notice if someone narrowed the cascade to an
  // explicit list of paths. docs/security.md §2.2.2 is explicit that the
  // pattern to copy asserts the ABSENCE of the residue, not the presence of a
  // collection name in `deletedCollections` — so that is what this does.
  it("SCENARIO-643: wellbeingCheckIns leaves no residue behind", async () => {
    await deleteUserDocs(testApp, uid);

    const remaining = await db()
      .collection("users")
      .doc(uid)
      .collection("wellbeingCheckIns")
      .get();
    expect(remaining.empty).toBe(true);
  });

  it("SCENARIO-536: userPublicProfiles/{uid} is deleted", async () => {
    await deleteUserDocs(testApp, uid);

    const snap = await db().collection("userPublicProfiles").doc(uid).get();
    expect(snap.exists).toBe(false);
  });
});

// #628 — el feedback por ejercicio vive DOS niveles abajo de users/{uid}:
// `users/{uid}/sessions/{sid}/exerciseFeedback/{id}`, y es dato de salud
// (`kind: 'discomfort'` + la URL de la foto de la lesión).
//
// Este test existe porque la pregunta "¿hace falta un paso de cascade propio
// para la subcolección nueva?" NO se contesta leyendo el código: se contesta
// midiendo. `deleteUserDocs` hace `recursiveDelete(users/{uid})` con el Admin
// SDK, que SÍ desciende el árbol entero — subcolecciones de subcolecciones
// incluidas. Con esto verificado, la parte de Firestore de #628 no necesita
// paso nuevo. La de STORAGE sí, y es otra historia: el bucket no tiene
// cascade, así que `sessionFeedback/{uid}/` se barre explícitamente en
// `cascade/storage.ts` (ver `cascade/storage.test.ts`).
//
// Si algún día `deleteUserDocs` cambia a un borrado por colección enumerada,
// este test cae y avisa que el feedback quedó huérfano.
describe("#628: exerciseFeedback under sessions goes with the recursive delete", () => {
  const uid = "users-cascade-628";
  const sessionId = "session-628";

  beforeEach(async () => {
    await seed(uid);
    await db()
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .doc(sessionId)
      .set({ id: sessionId });
    await db()
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .doc(sessionId)
      .collection("exerciseFeedback")
      .doc("fb-1")
      .set({
        exerciseId: "ex-1",
        exerciseName: "Press de banca",
        setNumber: 3,
        kind: "discomfort",
        text: "Me tira el hombro derecho",
        photoUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media&token=z",
        photoPath: `sessionFeedback/${uid}/${sessionId}/fb-1.jpg`,
        createdAt: new Date(),
      });
  });

  afterEach(() => cleanup(uid));

  it("users/{uid}/sessions/{sid}/exerciseFeedback/{id} no longer exists", async () => {
    // Precondición: el documento existe ANTES. Sin esto el test pasaría
    // igual con un seed roto — verde por el motivo equivocado (security.md §1.8).
    const before = await db()
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .doc(sessionId)
      .collection("exerciseFeedback")
      .doc("fb-1")
      .get();
    expect(before.exists).toBe(true);

    await deleteUserDocs(testApp, uid);

    const after = await db()
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .doc(sessionId)
      .collection("exerciseFeedback")
      .doc("fb-1")
      .get();
    expect(after.exists).toBe(false);
  });

  it("leaves nothing at all in the exerciseFeedback sub-collection", async () => {
    await deleteUserDocs(testApp, uid);

    const left = await db()
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .doc(sessionId)
      .collection("exerciseFeedback")
      .get();
    expect(left.empty).toBe(true);
  });
});

describe("SCENARIO-537: trainerPublicProfiles deletion is no-op when absent", () => {
  const uid = "users-cascade-537";

  beforeEach(() => seed(uid));
  afterEach(() => cleanup(uid));

  it("SCENARIO-537: no error when trainerPublicProfiles/{uid} does not exist", async () => {
    // Ensure it does NOT exist
    await db().collection("trainerPublicProfiles").doc(uid).delete().catch(() => undefined);

    await expect(deleteUserDocs(testApp, uid)).resolves.not.toThrow();
  });

  it("SCENARIO-537: trainerPublicProfiles/{uid} is deleted when it exists", async () => {
    await db()
      .collection("trainerPublicProfiles")
      .doc(uid)
      .set({ uid, displayName: "Trainer" });

    await deleteUserDocs(testApp, uid);

    const snap = await db().collection("trainerPublicProfiles").doc(uid).get();
    expect(snap.exists).toBe(false);
  });
});
