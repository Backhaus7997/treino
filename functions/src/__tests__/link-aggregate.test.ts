/**
 * Integration tests for linkAggregate's `recomputeAthleteCount` (#1333).
 * Run against the Firebase Local Emulator (Firestore).
 *
 * SC-PSD-22 — sin resurreccion fantasma: durante el borrado de cuenta del PF,
 * este recalculo puede LEER el perfil publico antes del paso `deleteUserDocs` y
 * ESCRIBIR despues. Con `set(merge)` eso recrea `trainerPublicProfiles/{uid}`
 * como un doc con solo `athleteCount`. Con `update()` falla con NOT_FOUND, que
 * el catch existente se traga.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { DocumentReference, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp({ projectId: "treino-dev" }, "link-aggregate-test");
});

afterAll(async () => {
  await deleteApp(testApp);
});

import { recomputeAthleteCount } from "../link-aggregate";

const db = () => getFirestore(testApp);
const TRAINER = "psd-linkagg-trainer";

async function cleanup(): Promise<void> {
  await db().collection("trainerPublicProfiles").doc(TRAINER).delete().catch(() => undefined);
  await Promise.all(
    ["psd-la-1", "psd-la-2"].map((id) =>
      db().collection("trainer_links").doc(id).delete().catch(() => undefined)),
  );
}

beforeEach(async () => {
  await cleanup();
  await db().collection("trainer_links").doc("psd-la-1").set(
    { trainerId: TRAINER, athleteId: "a1", status: "active" },
  );
  await db().collection("trainer_links").doc("psd-la-2").set(
    { trainerId: TRAINER, athleteId: "a2", status: "terminated" },
  );
});
afterEach(async () => {
  jest.restoreAllMocks();
  await cleanup();
});

describe("recomputeAthleteCount", () => {
  it("updates athleteCount on an existing profile and keeps its identity fields", async () => {
    await db().collection("trainerPublicProfiles").doc(TRAINER).set({ displayName: "PF", athleteCount: 0 });
    await recomputeAthleteCount(testApp, TRAINER);
    const d = (await db().collection("trainerPublicProfiles").doc(TRAINER).get()).data()!;
    expect(d.athleteCount).toBe(1);
    expect(d.displayName).toBe("PF");
  });

  it("does not create a profile that never existed", async () => {
    await recomputeAthleteCount(testApp, TRAINER);
    expect((await db().collection("trainerPublicProfiles").doc(TRAINER).get()).exists).toBe(false);
  });

  it("SC-PSD-22: a profile deleted BETWEEN the exists-check and the write is not resurrected", async () => {
    await db().collection("trainerPublicProfiles").doc(TRAINER).set({ displayName: "PF", athleteCount: 0 });

    // Simula `deleteUserDocs` corriendo justo despues de la lectura del trigger.
    const realGet = DocumentReference.prototype.get;
    jest.spyOn(DocumentReference.prototype, "get").mockImplementation(async function (this: DocumentReference) {
      const snap = await realGet.call(this);
      if (this.path === `trainerPublicProfiles/${TRAINER}`) await this.delete();
      return snap;
    });

    await expect(recomputeAthleteCount(testApp, TRAINER)).resolves.toBeUndefined();

    jest.restoreAllMocks();
    expect((await db().collection("trainerPublicProfiles").doc(TRAINER).get()).exists).toBe(false);
  });

  it("the NOT_FOUND race logs at warn, not error (expected outcome of the cascade)", async () => {
    await db().collection("trainerPublicProfiles").doc(TRAINER).set({ displayName: "PF", athleteCount: 0 });
    const warnSpy = jest.spyOn(logger, "warn").mockImplementation(() => undefined);
    const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);

    const realGet = DocumentReference.prototype.get;
    jest.spyOn(DocumentReference.prototype, "get").mockImplementation(async function (this: DocumentReference) {
      const snap = await realGet.call(this);
      if (this.path === `trainerPublicProfiles/${TRAINER}`) await this.delete();
      return snap;
    });

    await recomputeAthleteCount(testApp, TRAINER);

    expect(errorSpy).not.toHaveBeenCalled();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("disappeared"),
      expect.objectContaining({ trainerId: TRAINER }),
    );
  });

  it("any other write failure still logs at error", async () => {
    await db().collection("trainerPublicProfiles").doc(TRAINER).set({ displayName: "PF", athleteCount: 0 });
    const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);
    jest.spyOn(DocumentReference.prototype, "update").mockRejectedValue(
      Object.assign(new Error("boom"), { code: 14 }),
    );

    await recomputeAthleteCount(testApp, TRAINER);

    expect(errorSpy).toHaveBeenCalledTimes(1);
  });
});
