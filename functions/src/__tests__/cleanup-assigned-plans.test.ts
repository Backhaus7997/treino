/**
 * Integration tests for cleanupAssignedPlansOnUnlink.
 * Run against the Firebase Local Emulator (Firestore).
 *
 * Covers: assigned plans for the unlinked pair are hard-deleted, while
 * templates, other athletes' plans, and user-created routines survive; plus the
 * handler guards (terminated triggers, account-deleted / no-op / non-terminated
 * skip).
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp({ projectId: "treino-dev" }, "cleanup-plans-test");
});

afterAll(async () => {
  await deleteApp(testApp);
});

import {
  archiveAssignedPlansForPair,
  cleanupAssignedPlansOnUnlinkHandler,
} from "../cleanup-assigned-plans";

const db = () => getFirestore(testApp);

const TRAINER = "trainer-T";
const ATHLETE = "athlete-A";
const OTHER_ATHLETE = "athlete-B";

// Doc ids reused across tests.
const ASSIGNED_TA = "plan-assigned-TA";
const TEMPLATE_T = "plan-template-T";
const ASSIGNED_TB = "plan-assigned-TB";
const USER_A = "plan-user-A";

async function seedRoutines(): Promise<void> {
  const batch = db().batch();
  // Athlete A's assigned plan from trainer T → MUST be deleted on unlink.
  batch.set(db().collection("routines").doc(ASSIGNED_TA), {
    name: "Plan asignado A",
    source: "trainer-assigned",
    assignedBy: TRAINER,
    assignedTo: ATHLETE,
    visibility: "private",
  });
  // Trainer T's reusable template (assignedTo null) → MUST survive, even though
  // it may have been assigned to a single athlete.
  batch.set(db().collection("routines").doc(TEMPLATE_T), {
    name: "Plantilla T",
    source: "trainer-template",
    assignedBy: TRAINER,
    assignedTo: null,
    visibility: "private",
  });
  // Same trainer, DIFFERENT athlete → MUST survive (unlink is pair-scoped).
  batch.set(db().collection("routines").doc(ASSIGNED_TB), {
    name: "Plan asignado B",
    source: "trainer-assigned",
    assignedBy: TRAINER,
    assignedTo: OTHER_ATHLETE,
    visibility: "private",
  });
  // Athlete A's own routine → MUST survive.
  batch.set(db().collection("routines").doc(USER_A), {
    name: "Mi rutina",
    source: "user-created",
    createdBy: ATHLETE,
    visibility: "private",
  });
  await batch.commit();
}

async function cleanupRoutines(): Promise<void> {
  const batch = db().batch();
  for (const id of [ASSIGNED_TA, TEMPLATE_T, ASSIGNED_TB, USER_A]) {
    batch.delete(db().collection("routines").doc(id));
  }
  await batch.commit().catch(() => undefined);
}

async function exists(docId: string): Promise<boolean> {
  const snap = await db().collection("routines").doc(docId).get();
  return snap.exists;
}

async function statusOf(docId: string): Promise<unknown> {
  const snap = await db().collection("routines").doc(docId).get();
  return snap.get("status");
}

function link(status: string, extra: Record<string, unknown> = {}) {
  return { trainerId: TRAINER, athleteId: ATHLETE, status, ...extra };
}

describe("archiveAssignedPlansForPair", () => {
  beforeEach(seedRoutines);
  afterEach(cleanupRoutines);

  it("archives the athlete's assigned plan WITHOUT deleting it", async () => {
    // Éste es el cambio de fondo. Antes hacía `batch.delete()`, y eso rompía
    // la invariante que la app declara: una rutina se archiva para mantener
    // las referencias históricas de sesiones (ADR-USR-04). Borrarla dejaba
    // huérfanas las sesiones ya entrenadas, y si el vínculo se reactivaba el
    // plan no existía más.
    const { count } = await archiveAssignedPlansForPair(testApp, TRAINER, ATHLETE);
    expect(count).toBe(1);
    expect(await exists(ASSIGNED_TA)).toBe(true);
    expect(await statusOf(ASSIGNED_TA)).toBe("archived");
  });

  it("does NOT touch the trainer's template (survives even if assigned)", async () => {
    await archiveAssignedPlansForPair(testApp, TRAINER, ATHLETE);
    expect(await exists(TEMPLATE_T)).toBe(true);
    expect(await statusOf(TEMPLATE_T)).toBeUndefined();
  });

  it("does NOT touch plans assigned to a different athlete", async () => {
    await archiveAssignedPlansForPair(testApp, TRAINER, ATHLETE);
    expect(await exists(ASSIGNED_TB)).toBe(true);
    expect(await statusOf(ASSIGNED_TB)).toBeUndefined();
  });

  it("does NOT touch the athlete's own user-created routines", async () => {
    await archiveAssignedPlansForPair(testApp, TRAINER, ATHLETE);
    expect(await exists(USER_A)).toBe(true);
    expect(await statusOf(USER_A)).toBeUndefined();
  });

  it("is a no-op when there are no assigned plans for the pair", async () => {
    const { count } = await archiveAssignedPlansForPair(testApp, TRAINER, "ghost");
    expect(count).toBe(0);
  });

  it("correr dos veces no vuelve a escribir: la segunda cuenta 0", async () => {
    // El trigger puede dispararse más de una vez sobre el mismo par (un
    // reintento, dos writes que dejan el link en `terminated`). Re-escribir
    // `archived` sobre `archived` cuesta una escritura y no cambia nada.
    const primera = await archiveAssignedPlansForPair(testApp, TRAINER, ATHLETE);
    expect(primera.count).toBe(1);

    const segunda = await archiveAssignedPlansForPair(testApp, TRAINER, ATHLETE);
    expect(segunda.count).toBe(0);
    expect(await statusOf(ASSIGNED_TA)).toBe("archived");
  });
});

describe("cleanupAssignedPlansOnUnlinkHandler guards", () => {
  beforeEach(seedRoutines);
  afterEach(cleanupRoutines);

  it("archives assigned plans when the link becomes terminated", async () => {
    // El plan SOBREVIVE al corte del vínculo, archivado. Antes este test
    // pedía `exists === false`: el trigger borraba en duro y se llevaba
    // puestas las sesiones que el alumno ya había entrenado contra ese doc.
    const { count } = await cleanupAssignedPlansOnUnlinkHandler(
      testApp,
      link("active"),
      link("terminated"),
    );
    expect(count).toBe(1);
    expect(await exists(ASSIGNED_TA)).toBe(true);
    expect(await statusOf(ASSIGNED_TA)).toBe("archived");
  });

  it("skips when reason is account-deleted (cascade owns that flow)", async () => {
    const { count } = await cleanupAssignedPlansOnUnlinkHandler(
      testApp,
      link("active"),
      link("terminated", { reason: "account-deleted" }),
    );
    expect(count).toBe(0);
    expect(await exists(ASSIGNED_TA)).toBe(true);
  });

  it("skips a no-op write (status unchanged)", async () => {
    const { count } = await cleanupAssignedPlansOnUnlinkHandler(
      testApp,
      link("terminated"),
      link("terminated"),
    );
    expect(count).toBe(0);
    expect(await exists(ASSIGNED_TA)).toBe(true);
  });

  it("skips when the new status is not terminated", async () => {
    const { count } = await cleanupAssignedPlansOnUnlinkHandler(
      testApp,
      link("pending"),
      link("active"),
    );
    expect(count).toBe(0);
    expect(await exists(ASSIGNED_TA)).toBe(true);
  });

  it("skips a delete event (after missing)", async () => {
    const { count } = await cleanupAssignedPlansOnUnlinkHandler(
      testApp,
      link("active"),
      undefined,
    );
    expect(count).toBe(0);
    expect(await exists(ASSIGNED_TA)).toBe(true);
  });
});
