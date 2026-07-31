import * as admin from "firebase-admin";
import { reassignFcmTokenHandler } from "../notifications/reassign-fcm-token";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "reassign-fcm-token-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

const db = (): admin.firestore.Firestore => admin.firestore(testApp);
const user = (uid: string): admin.firestore.DocumentReference =>
  db().collection("users").doc(uid);

async function cleanup(...uids: string[]): Promise<void> {
  await Promise.all(uids.map((uid) => user(uid).delete().catch(() => undefined)));
}

describe("reassignFcmTokenHandler — integration", () => {
  afterEach(async () => cleanup("fcm-user-a", "fcm-user-b", "fcm-user-c"));

  it("moves a token from A when it appears on B", async () => {
    await user("fcm-user-a").set({ fcmTokens: ["shared-token"] });
    await user("fcm-user-b").set({ fcmTokens: ["shared-token"] });

    await reassignFcmTokenHandler(
      testApp,
      "fcm-user-b",
      { fcmTokens: [] },
      { fcmTokens: ["shared-token"] },
    );

    const [a, b] = await Promise.all([
      user("fcm-user-a").get(),
      user("fcm-user-b").get(),
    ]);
    expect(a.data()?.fcmTokens).toEqual([]);
    expect(b.data()?.fcmTokens).toEqual(["shared-token"]);
  });

  it("does not touch other users for a globally new token", async () => {
    await user("fcm-user-a").set({ fcmTokens: ["token-a"], marker: 1 });
    await user("fcm-user-b").set({ fcmTokens: ["brand-new-token"] });
    await user("fcm-user-c").set({ fcmTokens: ["token-c"], marker: 3 });

    await reassignFcmTokenHandler(
      testApp,
      "fcm-user-b",
      { fcmTokens: [] },
      { fcmTokens: ["brand-new-token"] },
    );

    const [a, c] = await Promise.all([
      user("fcm-user-a").get(),
      user("fcm-user-c").get(),
    ]);
    expect(a.data()).toEqual({ fcmTokens: ["token-a"], marker: 1 });
    expect(c.data()).toEqual({ fcmTokens: ["token-c"], marker: 3 });
  });
});
