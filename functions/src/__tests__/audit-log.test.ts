/**
 * Unit tests for audit-log helper module.
 * SCENARIO: REQ-ACCDEL-CF-011 — audit log written with correct shape.
 *
 * These tests run against the Firestore emulator.
 * Set FIRESTORE_EMULATOR_HOST before running.
 */

import * as admin from "firebase-admin";

// Point Admin SDK to the emulator
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

// Initialize a dedicated app for tests to avoid conflicts
let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    {
      projectId: "treino-dev",
    },
    "audit-log-test"
  );
});

afterAll(async () => {
  await testApp.delete();
});

// Import after env vars are set
import { writeStarted, writeFinal } from "../cascade/audit-log";
import { AuditLogEntry } from "../types";

const db = () => admin.firestore(testApp);

async function clearAuditLog(uid: string): Promise<void> {
  await db().collection("audit_log").doc(uid).delete();
}

describe("audit-log — writeStarted", () => {
  const uid = "test-audit-write-started";

  beforeEach(() => clearAuditLog(uid));

  it("writes status: started with required fields", async () => {
    const appForTest = testApp;
    await writeStarted(appForTest, uid, "password");

    const snap = await db().collection("audit_log").doc(uid).get();
    expect(snap.exists).toBe(true);

    const data = snap.data() as AuditLogEntry;
    expect(data.status).toBe("started");
    expect(data.provider).toBe("password");
    expect(data.startedAt).toBeTruthy(); // server timestamp resolves to Timestamp
    expect(data.uid).toBe(uid);
  });

  it("overwrites an existing audit_log entry (idempotent on re-call)", async () => {
    const appForTest = testApp;
    await writeStarted(appForTest, uid, "google.com");
    await writeStarted(appForTest, uid, "apple.com");

    const snap = await db().collection("audit_log").doc(uid).get();
    const data = snap.data() as AuditLogEntry;
    expect(data.provider).toBe("apple.com");
    expect(data.status).toBe("started");
  });
});

describe("audit-log — writeFinal", () => {
  const uid = "test-audit-write-final";

  beforeEach(() => clearAuditLog(uid));

  it("updates status to success with completedAt and deletedCollections", async () => {
    const appForTest = testApp;
    // Seed a started entry first
    await db().collection("audit_log").doc(uid).set({
      status: "started",
      provider: "password",
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      uid,
    });

    await writeFinal(appForTest, uid, "success", ["users-auth"], []);

    const snap = await db().collection("audit_log").doc(uid).get();
    const data = snap.data() as AuditLogEntry;
    expect(data.status).toBe("success");
    expect(data.completedAt).toBeTruthy();
    expect(data.deletedCollections).toEqual(["users-auth"]);
    expect(data.errors).toEqual([]);
  });

  it("updates status to failed with error info", async () => {
    const appForTest = testApp;
    await db().collection("audit_log").doc(uid).set({
      status: "started",
      provider: "password",
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      uid,
    });

    await writeFinal(appForTest, uid, "failed", [], ["Storage deletion failed"]);

    const snap = await db().collection("audit_log").doc(uid).get();
    const data = snap.data() as AuditLogEntry;
    expect(data.status).toBe("failed");
    expect(data.errors).toContain("Storage deletion failed");
    expect(data.deletedCollections).toEqual([]);
  });

  it("handles partial status with mixed results", async () => {
    const appForTest = testApp;
    await db().collection("audit_log").doc(uid).set({
      status: "started",
      provider: "google.com",
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      uid,
    });

    await writeFinal(
      appForTest,
      uid,
      "partial",
      ["users-auth", "friendships"],
      ["storage: file not found"]
    );

    const snap = await db().collection("audit_log").doc(uid).get();
    const data = snap.data() as AuditLogEntry;
    expect(data.status).toBe("partial");
    expect(data.deletedCollections).toHaveLength(2);
    expect(data.errors).toHaveLength(1);
  });
});
