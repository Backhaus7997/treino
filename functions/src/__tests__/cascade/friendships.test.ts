/**
 * Integration tests del cascade del grafo social (borrado de cuenta).
 * Corre contra el Firebase Local Emulator (Firestore).
 *
 * `follow-model` PR3a: la colección barrida pasa de `friendships` a `follows`
 * (ADR-FOLLOW-002). Se conserva UNA SOLA query gracias a `members`, que es el
 * argumento fuerte a favor de mantener ese campo (LD-01): sin él el barrido
 * pasaría a 2 queries + deduplicación, y el borrado de cuenta es justo donde un
 * doc que se escapa es un problema de compliance, no de UX.
 *
 * SCENARIOS cubiertos:
 *   SCENARIO-538 — los documentos del grafo social se barren (REQ-ACCDEL-CF-005)
 *   SCENARIO-539 — cero documentos es un no-op (REQ-ACCDEL-CF-005)
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "follows-cascade-test");
});

afterAll(async () => {
  await testApp.delete();
});

// Import the module under test — will fail until implementation exists
import { sweepFollows } from "../../cascade/friendships";

const db = () => admin.firestore(testApp);

const edgeId = (follower: string, followee: string) => `${follower}_${followee}`;

function edgeBody(follower: string, followee: string) {
  return {
    id: edgeId(follower, followee),
    followerUid: follower,
    followeeUid: followee,
    status: "accepted",
    members: [follower, followee],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/** Siembra [count] aristas SALIENTES de [uid]. */
async function seedOutgoing(uid: string, count: number): Promise<string[]> {
  const batch = db().batch();
  const ids: string[] = [];
  for (let i = 0; i < count; i++) {
    const other = `other-user-${i}`;
    const id = edgeId(uid, other);
    ids.push(id);
    batch.set(db().collection("follows").doc(id), edgeBody(uid, other));
  }
  await batch.commit();
  return ids;
}

async function cleanup(docIds: string[]): Promise<void> {
  const batch = db().batch();
  for (const id of docIds) {
    batch.delete(db().collection("follows").doc(id));
  }
  await batch.commit().catch(() => undefined);
}

describe("SCENARIO-538: las aristas del usuario se barren", () => {
  const uid = "follows-cascade-538";
  let docIds: string[] = [];

  beforeEach(async () => {
    docIds = await seedOutgoing(uid, 3);
  });
  afterEach(() => cleanup(docIds));

  it("SCENARIO-538: borra las 3 aristas donde el uid es miembro", async () => {
    await sweepFollows(testApp, uid);

    for (const id of docIds) {
      const snap = await db().collection("follows").doc(id).get();
      expect(snap.exists).toBe(false);
    }
  });

  it("SCENARIO-538: barre las DOS direcciones con una sola query", async () => {
    // El modelo dirigido duplica los documentos por par: al borrar una cuenta
    // hay que llevarse tanto a quién seguía como quién lo seguía. `members`
    // contiene los dos uids en las dos direcciones, así que un solo
    // `array-contains` las alcanza a ambas — si el barrido consultara por
    // `followerUid` se dejaría vivos a todos los seguidores del borrado.
    const inbound = edgeId("inbound-follower", uid);
    await db().collection("follows").doc(inbound).set(edgeBody("inbound-follower", uid));

    await sweepFollows(testApp, uid);

    const snap = await db().collection("follows").doc(inbound).get();
    expect(snap.exists).toBe(false);
  });

  it("SCENARIO-538: no borra aristas de terceros", async () => {
    const otherId = edgeId("user-a", "user-b");
    await db().collection("follows").doc(otherId).set(edgeBody("user-a", "user-b"));

    await sweepFollows(testApp, uid);

    const snap = await db().collection("follows").doc(otherId).get();
    expect(snap.exists).toBe(true);
    await db().collection("follows").doc(otherId).delete();
  });
});

describe("SCENARIO-539: cero aristas es un no-op", () => {
  const uid = "follows-cascade-539";

  it("SCENARIO-539: no tira error cuando el usuario no tiene ninguna arista", async () => {
    await expect(sweepFollows(testApp, uid)).resolves.not.toThrow();
  });
});
