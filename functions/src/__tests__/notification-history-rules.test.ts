/**
 * Tests de reglas para el historial privado de notificaciones en
 * `users/{uid}/notifications/{notificationId}` y su cursor de lectura
 * `users/{uid}.notificationsLastSeenAt`.
 *
 * Requiere el emulador de Firestore; el sandbox de implementación no puede
 * ejecutar esta suite porque no puede abrir sockets.
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { setLogLevel } from "firebase/firestore";

// Cada suite usa un projectId propio porque clearFirestore() corre entre tests
// y Jest ejecuta las suites de reglas en paralelo.
const PROJECT_ID = "treino-rules-test-notification-history";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const OWNER = "notification-owner";
const OTHER = "notification-other";
const NOTIFICATION_ID = "notification-existing";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const users = ctx.firestore().collection("users");

    await users.doc(OWNER).set({
      uid: OWNER,
      role: "athlete",
      email: `${OWNER}@example.test`,
      createdAt: new Date(0),
      displayName: "Owner",
      subscription: { tier: "free", status: "active", weightLimit: 2 },
      weightedLoad: 1,
    });
    await users.doc(OTHER).set({
      uid: OTHER,
      role: "athlete",
      email: `${OTHER}@example.test`,
      createdAt: new Date(0),
      displayName: "Other",
    });
    await users
      .doc(OWNER)
      .collection("notifications")
      .doc(NOTIFICATION_ID)
      .set({
        type: "workout_reminder",
        title: "Entrenamiento pendiente",
        createdAt: new Date(),
        read: false,
      });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function notification(uid: string | null, ownerUid = OWNER, id = NOTIFICATION_ID) {
  const ctx = uid === null
    ? testEnv.unauthenticatedContext()
    : testEnv.authenticatedContext(uid);

  return ctx
    .firestore()
    .collection("users")
    .doc(ownerUid)
    .collection("notifications")
    .doc(id);
}

function user(uid: string, ownerUid = OWNER) {
  return testEnv
    .authenticatedContext(uid)
    .firestore()
    .collection("users")
    .doc(ownerUid);
}

describe("historial de notificaciones", () => {
  it("permite al dueño leer una notificación propia", async () => {
    await assertSucceeds(notification(OWNER).get());
  });

  it("rechaza que otro usuario lea una notificación ajena", async () => {
    await assertFails(notification(OTHER).get());
  });

  it("rechaza la lectura sin autenticación", async () => {
    await assertFails(notification(null).get());
  });

  it("rechaza crear una notificación desde el cliente, incluso al dueño", async () => {
    const forged = {
      type: "forged",
      title: "Notificación falsa",
      createdAt: new Date(),
    };

    await assertFails(
      notification(OWNER, OWNER, "forged-by-owner").set(forged),
    );
    await assertFails(
      notification(OTHER, OWNER, "forged-by-other").set(forged),
    );
    await assertFails(
      notification(null, OWNER, "forged-unauthenticated").set(forged),
    );
  });

  it("rechaza actualizar una notificación existente desde el cliente", async () => {
    await assertFails(notification(OWNER).update({ read: true }));
    await assertFails(notification(OTHER).update({ read: true }));
    await assertFails(notification(null).update({ read: true }));
  });

  it("permite al dueño borrar una notificación propia", async () => {
    await assertSucceeds(notification(OWNER).delete());
  });

  it("rechaza que otro usuario borre una notificación ajena", async () => {
    await assertFails(notification(OTHER).delete());
  });
});

describe("users/{uid}.notificationsLastSeenAt", () => {
  it("permite al dueño escribir un timestamp", async () => {
    await assertSucceeds(
      user(OWNER).update({ notificationsLastSeenAt: new Date() }),
    );
  });

  it("rechaza que otro usuario escriba el cursor de lectura ajeno", async () => {
    await assertFails(
      user(OTHER).update({ notificationsLastSeenAt: new Date() }),
    );
  });

  it("rechaza valores que no sean timestamp", async () => {
    await assertFails(
      user(OWNER).update({ notificationsLastSeenAt: "2026-07-31" }),
    );
    await assertFails(user(OWNER).update({ notificationsLastSeenAt: 123456 }));
  });

  it("no permite modificar campos server-only junto con el cursor", async () => {
    await assertFails(
      user(OWNER).update({
        notificationsLastSeenAt: new Date(),
        subscription: { tier: "plan2", status: "active", weightLimit: 15 },
        weightedLoad: 999,
      }),
    );
  });
});
