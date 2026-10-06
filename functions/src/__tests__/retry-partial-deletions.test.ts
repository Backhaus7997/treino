/**
 * retry-partial-deletions.test.ts — el barrido que completa los borrados de
 * cuenta que terminaron `partial` (#1353).
 *
 * EMULADOR (Firestore + Auth + Storage).
 *
 * Lo que importa, en orden:
 *   1. completa lo que quedo colgado (datos de PF y de atleta) y marca success
 *   2. NO toca lo que no es `partial` (success / started / failed)
 *   3. NO vuelve a avisar: un vinculo ya terminado y un turno ya cancelado
 *      quedan byte a byte iguales (los avisos son triggers que reaccionan al
 *      WRITE; sin write no hay aviso)
 *   4. NO toca Mercado Pago ni Auth (salvo que el `partial` original haya sido
 *      justamente por Auth)
 *   5. cuenta intentos y se rinde a los N con `failed` + log de error
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
import { logger } from "firebase-functions";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
  config: () => ({}),
}));
jest.mock("../cascade/trainer-data", () => {
  const actual = jest.requireActual("../cascade/trainer-data");
  return {
    ...actual,
    deleteTrainerOwnedData: jest.fn(actual.deleteTrainerOwnedData),
  };
});
jest.mock("../subscriptions/mp/client", () => ({
  createMpClient: jest.fn(() => {
    throw new Error("el reintento no debe tocar Mercado Pago");
  }),
}));

import * as trainerData from "../cascade/trainer-data";
import { createMpClient } from "../subscriptions/mp/client";
import {
  MAX_RETRY_ATTEMPTS,
  RETRY_BATCH_LIMIT,
  RETRY_SCHEDULE_OPTIONS,
  retryPartialDeletionsHandler,
} from "../retention/retry-partial-deletions";

const PF = "rpd-pf";
const ATH = "rpd-athlete";
const STUDENT = "rpd-student";
const OK = "rpd-ok";
const STARTED = "rpd-started";
const FAILED = "rpd-failed";
const DOCS = [
  ["trainer_links", "rpd-l-open"], ["trainer_links", "rpd-l-done"],
  ["appointments", "rpd-a-open"], ["appointments", "rpd-a-done"],
  ["athlete_notes", "rpd-n1"], ["athlete_notes", "rpd-n-ok"],
  ["measurements", "rpd-m1"],
  ["audit_log", PF], ["audit_log", ATH], ["audit_log", OK],
  ["audit_log", STARTED], ["audit_log", FAILED],
];

let app: App;
beforeAll(() => {
  app = initializeApp(
    { projectId: "treino-dev", storageBucket: "treino-dev.appspot.com" },
    "retry-partial-deletions-test"
  );
});
afterAll(async () => {
  await deleteApp(app);
});

const db = () => getFirestore(app);
const get = async (c: string, id: string) =>
  (await db().collection(c).doc(id).get());
const audit = async (uid: string) => (await get("audit_log", uid)).data()!;
const fileExists = async (n: string) =>
  (await getStorage(app).bucket().file(n).exists())[0];

const partial = (uid: string, extra: Record<string, unknown> = {}) =>
  db().collection("audit_log").doc(uid).set({
    uid, status: "partial", provider: "password",
    errors: ["trainer-data: boom"], deletedCollections: ["posts"], ...extra,
  });

async function seedLeftovers() {
  const future = Timestamp.fromMillis(Date.now() + 3 * 86400000);
  const b = db().batch();
  b.set(db().collection("trainer_links").doc("rpd-l-open"), { trainerId: PF, athleteId: STUDENT, status: "active" });
  b.set(db().collection("trainer_links").doc("rpd-l-done"), {
    trainerId: PF, athleteId: "rpd-other", status: "terminated",
    reason: trainerData.TRAINER_ACCOUNT_DELETED_REASON, terminatedAt: Timestamp.fromMillis(1000),
  });
  b.set(db().collection("appointments").doc("rpd-a-open"), { trainerId: PF, athleteId: STUDENT, status: "confirmed", startsAt: future });
  b.set(db().collection("appointments").doc("rpd-a-done"), {
    trainerId: PF, athleteId: "rpd-other", status: "cancelled", startsAt: future,
    reason: trainerData.TRAINER_ACCOUNT_DELETED_REASON, cancellationLog: [{ byUid: PF, atMs: 1, reason: "x" }],
  });
  b.set(db().collection("athlete_notes").doc("rpd-n1"), { trainerId: PF, athleteId: STUDENT });
  // Datos de un ATLETA colgado: el reintento tambien los barre.
  b.set(db().collection("measurements").doc("rpd-m1"), { athleteId: ATH });
  // Un doc ajeno que NO le pertenece a nadie de los borrados.
  b.set(db().collection("athlete_notes").doc("rpd-n-ok"), { trainerId: "rpd-someone-else", athleteId: STUDENT });
  await b.commit();
  await getStorage(app).bucket().file(`athleteFiles/${PF}_${STUDENT}/f.pdf`).save(Buffer.from("x"));
}

afterEach(async () => {
  jest.clearAllMocks();
  await Promise.all([
    ...DOCS.map(([c, id]) => db().collection(c).doc(id).delete().catch(() => undefined)),
    getStorage(app).bucket().file(`athleteFiles/${PF}_${STUDENT}/f.pdf`).delete().catch(() => undefined),
    getAuth(app).deleteUser(PF).catch(() => undefined),
  ]);
});

describe("completa lo que quedo colgado", () => {
  it("barre datos de PF y de atleta, y marca success", async () => {
    await seedLeftovers();
    await partial(PF);
    await partial(ATH, { errors: ["athlete-data: boom"] });

    const r = await retryPartialDeletionsHandler(app);

    expect(r).toMatchObject({ scanned: 2, succeeded: 2, stillPartial: 0, failed: 0 });
    expect((await audit(ATH)).status).toBe("success");
    expect((await get("athlete_notes", "rpd-n1")).exists).toBe(false);
    expect((await get("measurements", "rpd-m1")).exists).toBe(false);
    expect((await get("trainer_links", "rpd-l-open")).data()!.status).toBe("terminated");
    expect((await get("appointments", "rpd-a-open")).data()!.status).toBe("cancelled");
    expect(await fileExists(`athleteFiles/${PF}_${STUDENT}/f.pdf`)).toBe(false);
    // lo ajeno queda
    expect((await get("athlete_notes", "rpd-n-ok")).exists).toBe(true);

    const a = await audit(PF);
    expect(a.status).toBe("success");
    expect(a.errors).toEqual([]);
    expect(a.retryCount).toBe(1);
    expect(a.retriedAt).toBeDefined();
    expect(a.lastRetryAt).toBeDefined();
  });
});

describe("no vuelve a avisar ni toca lo que ya esta hecho", () => {
  it("un vinculo ya terminado y un turno ya cancelado no se reescriben", async () => {
    await seedLeftovers();
    await partial(PF);
    const link0 = await get("trainer_links", "rpd-l-done");
    const apt0 = await get("appointments", "rpd-a-done");

    await retryPartialDeletionsHandler(app);

    const link1 = await get("trainer_links", "rpd-l-done");
    const apt1 = await get("appointments", "rpd-a-done");
    // Sin write no hay trigger (notify-link-change / notify-appointment).
    expect(link1.updateTime!.isEqual(link0.updateTime!)).toBe(true);
    expect(apt1.updateTime!.isEqual(apt0.updateTime!)).toBe(true);
  });
});

describe("no toca MP ni Auth", () => {
  it("no arma el cliente de MP y no borra a un usuario de Auth vivo", async () => {
    await getAuth(app).createUser({ uid: PF, email: `${PF}@test.com` });
    await partial(PF); // errors: trainer-data (no auth)

    await retryPartialDeletionsHandler(app);

    expect(createMpClient).not.toHaveBeenCalled();
    await expect(getAuth(app).getUser(PF)).resolves.toBeDefined();
  });

  it("si el partial original fue POR Auth, reintenta la baja de Auth", async () => {
    await getAuth(app).createUser({ uid: PF, email: `${PF}@test.com` });
    await partial(PF, { errors: ["auth: boom"] });

    const r = await retryPartialDeletionsHandler(app);

    expect(r.succeeded).toBe(1);
    await expect(getAuth(app).getUser(PF)).rejects.toBeDefined();
    const a = await audit(PF);
    expect(a.status).toBe("success");
    // El partial original no pudo anotar `users-auth`: lo anota el reintento
    // que efectivamente dio de baja la identidad (review de #1355).
    expect(a.deletedCollections).toContain("users-auth");
  });

  it("si el partial NO fue por Auth, no anota users-auth", async () => {
    await partial(PF, { errors: ["routines: boom"] });

    await retryPartialDeletionsHandler(app);

    expect((await audit(PF)).deletedCollections ?? []).not.toContain("users-auth");
  });
});

describe("solo mira los partial", () => {
  it("success, started y failed quedan intactos", async () => {
    await seedLeftovers();
    const base = { provider: "password", errors: [], deletedCollections: [] };
    await db().collection("audit_log").doc(OK).set({ uid: OK, status: "success", ...base });
    await db().collection("audit_log").doc(STARTED).set({ uid: STARTED, status: "started", provider: "password" });
    await db().collection("audit_log").doc(FAILED).set({ uid: FAILED, status: "failed", ...base, retryCount: 5 });
    const before = await Promise.all([OK, STARTED, FAILED].map((u) => get("audit_log", u)));

    const r = await retryPartialDeletionsHandler(app);

    expect(r.scanned).toBe(0);
    const after = await Promise.all([OK, STARTED, FAILED].map((u) => get("audit_log", u)));
    after.forEach((d, i) => {
      expect(d.updateTime!.isEqual(before[i].updateTime!)).toBe(true);
      expect(d.data()).toEqual(before[i].data());
    });
    // y los datos de esos uids/ajenos siguen donde estaban
    expect((await get("athlete_notes", "rpd-n1")).exists).toBe(true);
  });
});

describe("intentos y rendicion", () => {
  const failOnce = () =>
    (trainerData.deleteTrainerOwnedData as jest.Mock).mockRejectedValueOnce(new Error("sigue roto"));

  it("si un paso sigue fallando queda partial, con retryCount y los errores nuevos", async () => {
    await seedLeftovers();
    await partial(PF, { retryCount: 1 });
    failOnce();

    const r = await retryPartialDeletionsHandler(app);

    expect(r).toMatchObject({ scanned: 1, succeeded: 0, stillPartial: 1, failed: 0 });
    const a = await audit(PF);
    expect(a.status).toBe("partial");
    expect(a.retryCount).toBe(2);
    expect(a.errors).toEqual(["trainer-data: sigue roto"]);
    expect(a.lastRetryAt).toBeDefined();
    expect(a.retriedAt).toBeUndefined();
    // los otros pasos siguieron: el vinculo se termino igual
    expect((await get("trainer_links", "rpd-l-open")).data()!.status).toBe("terminated");
  });

  it("al intento N sin exito pasa a failed y loguea error", async () => {
    await seedLeftovers();
    await partial(PF, { retryCount: MAX_RETRY_ATTEMPTS - 1 });
    failOnce();

    const r = await retryPartialDeletionsHandler(app);

    expect(r).toMatchObject({ succeeded: 0, stillPartial: 0, failed: 1 });
    const a = await audit(PF);
    expect(a.status).toBe("failed");
    expect(a.retryCount).toBe(MAX_RETRY_ATTEMPTS);
    expect(logger.error).toHaveBeenCalledWith(
      expect.stringContaining("retryPartialDeletions"),
      expect.objectContaining({ uid: PF })
    );
  });

  it("un partial que ya agoto los intentos pasa a failed sin reintentar", async () => {
    await seedLeftovers();
    await partial(PF, { retryCount: MAX_RETRY_ATTEMPTS });

    const r = await retryPartialDeletionsHandler(app);

    expect(r.failed).toBe(1);
    expect((await audit(PF)).status).toBe("failed");
    expect((await get("athlete_notes", "rpd-n1")).exists).toBe(true);
  });

  it("respeta el limite por corrida", async () => {
    await partial(PF);
    await partial(ATH);

    const r = await retryPartialDeletionsHandler(app, { limit: 1 });

    expect(r.scanned).toBe(1);
  });
});

describe("carrera con un borrado que se vuelve a correr", () => {
  it("si el audit doc cambia entre la lectura y la escritura, no pisa lo nuevo y lo saltea", async () => {
    await partial(PF);
    // Mientras la cascada del barrido corre, la persona vuelve a pedir el
    // borrado: `writeStarted` hace set() y deja el doc fresco en `started`.
    const cascade = jest.fn(async () => {
      await db().collection("audit_log").doc(PF).set({ uid: PF, status: "started", provider: "password" });
      return { deletedCollections: ["posts"], errors: [] };
    });

    const r = await retryPartialDeletionsHandler(app, { cascade });

    expect(r).toMatchObject({ scanned: 1, succeeded: 0, stillPartial: 0, failed: 0, skipped: 1 });
    const a = await audit(PF);
    expect(a.status).toBe("started");
    expect(a.retryCount).toBeUndefined();
    expect(a.errors).toBeUndefined();
    expect(logger.info).toHaveBeenCalledWith(
      expect.stringContaining("retryPartialDeletions"),
      expect.objectContaining({ uid: PF })
    );
  });
});

describe("opciones del schedule", () => {
  it("le da tiempo y memoria a 20 cascadas secuenciales", () => {
    expect(RETRY_SCHEDULE_OPTIONS.timeoutSeconds).toBe(540);
    expect(RETRY_SCHEDULE_OPTIONS.memory).toBe("512MiB");
    expect(RETRY_BATCH_LIMIT).toBeLessThanOrEqual(20);
  });
});

describe("casos de borde del barrido", () => {
  it("auth/user-not-found cuenta como exito al reintentar la baja de Auth", async () => {
    // Sin usuario de Auth: deleteUser tira auth/user-not-found.
    await partial(PF, { errors: ["auth: boom"] });

    const r = await retryPartialDeletionsHandler(app);

    expect(r).toMatchObject({ succeeded: 1, stillPartial: 0 });
    const a = await audit(PF);
    expect(a.status).toBe("success");
    expect(a.errors).toEqual([]);
  });

  it("un uid que explota no frena a los siguientes", async () => {
    await partial(PF);
    await partial(ATH, { errors: ["athlete-data: boom"] });
    const real = jest.requireActual("../cascade/run-data-cascade").runDataCascade;
    const cascade = jest.fn(async (a: App, uid: string) => {
      if (uid === PF) throw new Error("revienta");
      return real(a, uid);
    });

    const r = await retryPartialDeletionsHandler(app, { cascade });

    expect(r.scanned).toBe(2);
    expect(r.succeeded).toBe(1);
    expect((await audit(ATH)).status).toBe("success");
    expect((await audit(PF)).status).toBe("partial");
    expect(logger.error).toHaveBeenCalledWith(
      expect.stringContaining("retryPartialDeletions"),
      expect.objectContaining({ uid: PF })
    );
  });

  it("previous >= maxAttempts (tope inyectado) cierra como failed sin correr la cascada", async () => {
    await partial(PF, { retryCount: 2 });
    const cascade = jest.fn();

    const r = await retryPartialDeletionsHandler(app, { maxAttempts: 2, cascade });

    expect(r.failed).toBe(1);
    expect(cascade).not.toHaveBeenCalled();
    expect((await audit(PF)).status).toBe("failed");
  });
});
