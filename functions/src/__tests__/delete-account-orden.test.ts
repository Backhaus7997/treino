/**
 * delete-account-orden.test.ts — candado del ORDEN de `runDeleteAccount` tras
 * extraer `runDataCascade` (#1353).
 *
 * EMULADOR (Auth). El orden importa: Mercado Pago (fail-closed) va ANTES de la
 * primera escritura/paso de datos, y la baja de Auth va DESPUES del ultimo, para
 * que un reintento tras un fallo a mitad siga encontrando la cuenta.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
process.env.GCLOUD_PROJECT ??= "treino-dev";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";

const calls: string[] = [];

jest.mock("../cascade/subscriptions", () => ({
  cancelarSuscripcionesAntesDeEliminar: jest.fn(async () => {
    calls.push("mp");
    return 0;
  }),
}));
jest.mock("../cascade/audit-log", () => ({
  writeStarted: jest.fn(async () => {
    calls.push("started");
  }),
  writeFinal: jest.fn(async () => {
    calls.push("final");
  }),
}));

import { runDeleteAccount } from "../delete-account";
import * as cascadeMod from "../cascade/run-data-cascade";

const EXPECTED_LABELS = [
  "follows", "posts", "trainer_links", "trainer-links", "appointments",
  "trainer-appointments", "storage", "storage-athlete", "trainer-storage",
  "athlete-data", "trainer-data", "routines", "trainer-templates",
  "users", "userPublicProfiles",
];

let app: App;
beforeAll(() => {
  app = initializeApp(
    { projectId: "treino-dev", storageBucket: "treino-dev.appspot.com" },
    "delete-account-orden-test"
  );
});
afterAll(async () => {
  await deleteApp(app);
});
beforeEach(() => {
  calls.length = 0;
});

describe("orden de runDeleteAccount", () => {
  it("los pasos de datos salen en el orden y con las etiquetas de siempre", async () => {
    const r = await cascadeMod.runDataCascade(app, "orden-uid-labels");

    expect(r.errors).toEqual([]);
    expect(r.deletedCollections).toEqual(EXPECTED_LABELS);
  });

  it("MP se cancela antes del primer paso y Auth se borra despues del ultimo", async () => {
    const uid = "orden-uid-1";
    await getAuth(app).createUser({ uid, email: `${uid}@test.com` });
    const spy = jest
      .spyOn(cascadeMod, "runDataCascade")
      .mockImplementation(async () => {
        calls.push("cascade");
        return { deletedCollections: ["posts"], errors: [] };
      });
    const delUser = jest
      .spyOn(getAuth(app), "deleteUser")
      .mockImplementation(async () => {
        calls.push("auth");
      });

    const res = await runDeleteAccount(app, uid, "password", {
      getMpClient: jest.fn() as never,
      nowMs: 0,
    });

    spy.mockRestore();
    delUser.mockRestore();
    await getAuth(app).deleteUser(uid).catch(() => undefined);
    expect(calls).toEqual(["mp", "started", "cascade", "auth", "final"]);
    expect(res.status).toBe("success");
    expect(res.deletedCollections).toEqual(["posts", "users-auth"]);
  });
});
