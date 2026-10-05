/**
 * delete-account-trainer.test.ts — el cableado del borrado de cuenta del
 * ENTRENADOR en `runDeleteAccount` (#1333).
 *
 * EMULADOR (Firestore + Auth + Storage).
 *
 *   SC-PSD-01/02  el PF ya no es rechazado y los alumnos activos no bloquean
 *   SC-PSD-03     reintento tras haber borrado `users/{uid}`: la cascada barre igual
 *   SC-PSD-23     el cancel de MP sigue fail-closed para el PF
 *   SC-PSD-25     regresion: un atleta se borra igual que antes
 *   orden de pasos, `trainer-<paso>` en errors[] y status partial
 *   V3            customExercises + videos del PF salen por los pasos ya existentes
 */

/* eslint-disable max-len */
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
process.env.GCLOUD_PROJECT ??= "treino-dev";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

// Passthrough por defecto; los tests de errores parciales lo pisan con
// mockRejectedValueOnce.
jest.mock("../cascade/trainer-data", () => {
  const actual = jest.requireActual("../cascade/trainer-data");
  return {
    ...actual,
    terminateLinksAsTrainer: jest.fn(actual.terminateLinksAsTrainer),
    cancelFutureAppointmentsAsTrainer: jest.fn(actual.cancelFutureAppointmentsAsTrainer),
    deleteTrainerOwnedData: jest.fn(actual.deleteTrainerOwnedData),
    deleteTrainerTemplates: jest.fn(actual.deleteTrainerTemplates),
  };
});
jest.mock("../cascade/storage", () => {
  const actual = jest.requireActual("../cascade/storage");
  return { ...actual, deleteTrainerStorage: jest.fn(actual.deleteTrainerStorage) };
});

import * as trainerData from "../cascade/trainer-data";
import * as storageCascade from "../cascade/storage";
import { DeleteAccountDeps, runDeleteAccount } from "../delete-account";

const PF = "psd-del-pf";
const ATH = "psd-del-athlete";
const STUDENT = "psd-del-student";

let app: App;
beforeAll(() => {
  app = initializeApp(
    { projectId: "treino-dev", storageBucket: "treino-dev.appspot.com" },
    "delete-account-trainer-test"
  );
});
afterAll(async () => {
  await deleteApp(app);
});

const db = () => getFirestore(app);
const exists = async (col: string, id: string) =>
  (await db().collection(col).doc(id).get()).exists;
const authExists = (uid: string) =>
  getAuth(app).getUser(uid).then(() => true, () => false);
const fileExists = async (n: string) =>
  (await getStorage(app).bucket().file(n).exists())[0];

const NO_MP: DeleteAccountDeps = {
  nowMs: Date.now(),
  getMpClient: () => {
    throw new Error("no deberia armarse");
  },
};

async function seedTrainer(opts: { withUser: boolean } = { withUser: true }) {
  if (opts.withUser) {
    await getAuth(app).createUser({ uid: PF, email: `${PF}@test.com` });
    await db().collection("users").doc(PF).set({ uid: PF, role: "trainer" });
    await db().collection("users").doc(PF).collection("customExercises").doc("ce1").set({ name: "Mi ejercicio" });
  }
  const future = Timestamp.fromMillis(Date.now() + 3 * 86400000);
  const b = db().batch();
  b.set(db().collection("trainer_links").doc("psd-del-l1"), { trainerId: PF, athleteId: STUDENT, status: "active" });
  b.set(db().collection("appointments").doc("psd-del-a1"), { trainerId: PF, athleteId: STUDENT, status: "confirmed", startsAt: future });
  b.set(db().collection("athlete_notes").doc("psd-del-n1"), { trainerId: PF, athleteId: STUDENT });
  b.set(db().collection("payments").doc("psd-del-p1"), { trainerId: PF, athleteId: STUDENT });
  b.set(db().collection("routines").doc("psd-del-tpl"), { assignedBy: PF, source: "trainer-template" });
  b.set(db().collection("routines").doc("psd-del-assigned"), { assignedBy: PF, assignedTo: STUDENT, source: "trainer-assigned" });
  b.set(db().collection("trainerPublicProfiles").doc(PF), { uid: PF });
  await b.commit();
  const bucket = getStorage(app).bucket();
  await bucket.file(`athleteFiles/${PF}_${STUDENT}/f.pdf`).save(Buffer.from("x"));
  await bucket.file(`customExerciseVideos/${PF}/v.mp4`).save(Buffer.from("x"));
}

afterEach(async () => {
  jest.clearAllMocks();
  const bucket = getStorage(app).bucket();
  await Promise.all([
    getAuth(app).deleteUser(PF).catch(() => undefined),
    getAuth(app).deleteUser(ATH).catch(() => undefined),
    db().recursiveDelete(db().collection("users").doc(PF)).catch(() => undefined),
    db().recursiveDelete(db().collection("users").doc(ATH)).catch(() => undefined),
    ...[
      ["trainer_links", "psd-del-l1"], ["appointments", "psd-del-a1"],
      ["athlete_notes", "psd-del-n1"], ["payments", "psd-del-p1"],
      ["routines", "psd-del-tpl"], ["routines", "psd-del-assigned"],
      ["trainerPublicProfiles", PF], ["userPublicProfiles", PF], ["userPublicProfiles", ATH],
      ["audit_log", PF], ["audit_log", ATH], ["mp_plans", "psd-del-plan"],
    ].map(([c, id]) => db().collection(c).doc(id).delete().catch(() => undefined)),
    bucket.file(`athleteFiles/${PF}_${STUDENT}/f.pdf`).delete().catch(() => undefined),
    bucket.file(`customExerciseVideos/${PF}/v.mp4`).delete().catch(() => undefined),
  ]);
});

describe("SC-PSD-01/02: el PF borra su cuenta", () => {
  it("no es rechazado aunque tenga alumnos activos, y la cascada completa corre", async () => {
    await seedTrainer();

    const r = await runDeleteAccount(app, PF, "password", NO_MP);

    expect(r.status).toBe("success");
    expect(r.errors).toEqual([]);
    for (const label of [
      "trainer-links", "trainer-appointments", "trainer-storage",
      "trainer-data", "trainer-templates",
    ]) {
      expect(r.deletedCollections).toContain(label);
    }
    expect(await exists("users", PF)).toBe(false);
    expect(await authExists(PF)).toBe(false);

    // T1: el vinculo queda terminado con el motivo nuevo (no se borra)
    const link = (await db().collection("trainer_links").doc("psd-del-l1").get()).data()!;
    expect(link.status).toBe("terminated");
    expect(link.reason).toBe(trainerData.TRAINER_ACCOUNT_DELETED_REASON);
    // T2
    expect((await db().collection("appointments").doc("psd-del-a1").get()).data()!.status).toBe("cancelled");
    // T4 + retencion de pagos
    expect(await exists("athlete_notes", "psd-del-n1")).toBe(false);
    expect(await exists("payments", "psd-del-p1")).toBe(true);
    // T5: la plantilla se va, el plan asignado se queda con el alumno
    expect(await exists("routines", "psd-del-tpl")).toBe(false);
    expect(await exists("routines", "psd-del-assigned")).toBe(true);
    // T3
    expect(await fileExists(`athleteFiles/${PF}_${STUDENT}/f.pdf`)).toBe(false);
    // perfil publico
    expect(await exists("trainerPublicProfiles", PF)).toBe(false);
  });

  it("V3: customExercises del PF y sus videos salen por los pasos ya existentes", async () => {
    await seedTrainer();
    await runDeleteAccount(app, PF, "password", NO_MP);
    const ce = await db().collection("users").doc(PF).collection("customExercises").get();
    expect(ce.size).toBe(0);
    expect(await fileExists(`customExerciseVideos/${PF}/v.mp4`)).toBe(false);
  });

  it("los pasos del PF corren en el orden del diseno, intercalados con los del atleta", async () => {
    await seedTrainer();
    const r = await runDeleteAccount(app, PF, "password", NO_MP);
    const order = [
      "follows", "posts", "trainer_links", "trainer-links", "appointments",
      "trainer-appointments", "storage", "storage-athlete", "trainer-storage",
      "athlete-data", "trainer-data", "routines", "trainer-templates",
      "users", "users-auth",
    ];
    const idx = order.map((l) => r.deletedCollections.indexOf(l));
    expect(idx.every((i) => i >= 0)).toBe(true);
    expect([...idx].sort((a, b) => a - b)).toEqual(idx);
  });
});

describe("SC-PSD-03: reintento con users/{uid} ya borrado", () => {
  it("la cascada barre los datos trainer-keyed pendientes sin depender del rol", async () => {
    // Estado de un intento previo que borro users/{uid} y Auth pero dejo datos.
    await seedTrainer({ withUser: false });

    const r = await runDeleteAccount(app, PF, "password", NO_MP);

    expect(r.status).toBe("success");
    expect((await db().collection("trainer_links").doc("psd-del-l1").get()).data()!.status).toBe("terminated");
    expect(await exists("athlete_notes", "psd-del-n1")).toBe(false);
    expect(await exists("routines", "psd-del-tpl")).toBe(false);
    expect(await exists("routines", "psd-del-assigned")).toBe(true);
    expect(await fileExists(`athleteFiles/${PF}_${STUDENT}/f.pdf`)).toBe(false);
  });
});

describe("errores parciales: trainer-<paso>", () => {
  it.each([
    ["trainer-links", () => trainerData.terminateLinksAsTrainer],
    ["trainer-appointments", () => trainerData.cancelFutureAppointmentsAsTrainer],
    ["trainer-storage", () => storageCascade.deleteTrainerStorage],
    ["trainer-data", () => trainerData.deleteTrainerOwnedData],
    ["trainer-templates", () => trainerData.deleteTrainerTemplates],
  ])("%s falla: status partial, el resto sigue y Auth se borra", async (label, getFn) => {
    await seedTrainer();
    (getFn() as jest.Mock).mockRejectedValueOnce(new Error("boom"));

    const r = await runDeleteAccount(app, PF, "password", NO_MP);

    expect(r.status).toBe("partial");
    expect(r.errors).toEqual([`${label}: boom`]);
    expect(r.deletedCollections).not.toContain(label);
    expect(r.deletedCollections).toContain("users-auth");
    const audit = (await db().collection("audit_log").doc(PF).get()).data()!;
    expect(audit.status).toBe("partial");
    expect(audit.errors).toEqual(r.errors);
  });
});

describe("SC-PSD-23: MP fail-closed para el PF", () => {
  it("si MP no contesta no se toca nada, tampoco los datos del PF", async () => {
    await seedTrainer();
    await db().collection("mp_plans").doc("psd-del-plan").set({ producto: "trainer", uid: PF, cycle: "monthly" });
    const deps: DeleteAccountDeps = {
      nowMs: Date.now(),
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      getMpClient: () => ({
        searchPreapprovalsByPlan: async () => {
          throw new Error("MP 503");
        },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      }) as any,
    };

    await expect(runDeleteAccount(app, PF, "password", deps)).rejects.toMatchObject({
      code: "unavailable",
    });

    expect(await exists("users", PF)).toBe(true);
    expect(await authExists(PF)).toBe(true);
    expect((await db().collection("trainer_links").doc("psd-del-l1").get()).data()!.status).toBe("active");
    expect(await exists("athlete_notes", "psd-del-n1")).toBe(true);
    expect(trainerData.terminateLinksAsTrainer).not.toHaveBeenCalled();
  });
});

describe("SC-PSD-25: regresion del atleta", () => {
  it("el atleta se borra igual; sus links terminan con account-deleted y la cascada del PF no toca nada ajeno", async () => {
    await getAuth(app).createUser({ uid: ATH, email: `${ATH}@test.com` });
    await db().collection("users").doc(ATH).set({ uid: ATH, role: "athlete" });
    await db().collection("trainer_links").doc("psd-del-l1").set({ trainerId: "psd-del-other-pf", athleteId: ATH, status: "active" });
    await db().collection("athlete_notes").doc("psd-del-n1").set({ trainerId: "psd-del-other-pf", athleteId: ATH });
    await db().collection("routines").doc("psd-del-assigned").set({ assignedBy: "psd-del-other-pf", assignedTo: ATH, source: "trainer-assigned" });
    await db().collection("routines").doc("psd-del-tpl").set({ assignedBy: "psd-del-other-pf", source: "trainer-template" });

    const r = await runDeleteAccount(app, ATH, "password", NO_MP);

    expect(r.status).toBe("success");
    const link = (await db().collection("trainer_links").doc("psd-del-l1").get()).data()!;
    expect(link.reason).toBe("account-deleted");
    expect(await exists("athlete_notes", "psd-del-n1")).toBe(false); // por athleteId (existente)
    expect(await exists("routines", "psd-del-assigned")).toBe(false); // por assignedTo (existente)
    expect(await exists("routines", "psd-del-tpl")).toBe(true); // plantilla ajena intacta
    expect(await authExists(ATH)).toBe(false);
  });
});
