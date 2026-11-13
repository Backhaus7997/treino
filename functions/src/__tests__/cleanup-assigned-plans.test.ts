/**
 * Integration tests for cleanupAssignedPlansOnUnlink.
 * Run against the Firebase Local Emulator (Firestore).
 *
 * Covers: assigned plans for the unlinked pair are ARCHIVED (not deleted), while
 * templates, other athletes' plans, and user-created routines survive; plus the
 * handler guards (terminated triggers, account-deleted / no-op / non-terminated
 * skip).
 *
 * #1723: `archiveOrphanAssignedPlanHandler` archiva el plan que se asigna a un
 * par SIN vínculo vivo (el hueco que deja el trigger de arriba, que sólo corre
 * en la transición a `terminated`).
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
  TRAINER_ACCOUNT_DELETED_REASON,
  terminateLinksAsTrainer,
} from "../cascade/trainer-data";
import {
  OrphanPlanResult,
  archiveAssignedPlansForPair,
  archiveOrphanAssignedPlanHandler,
  archiveOrphanAssignedPlanOnCreate,
  cleanupAssignedPlansOnUnlinkHandler,
} from "../cleanup-assigned-plans";
import { DUPLICATE_REQUEST_REASON } from "../subscriptions/cancel-duplicate-pending-links";

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

  // #1333 / SC-PSD-11 — el PF borra su cuenta. Las rutinas asignadas SE QUEDAN
  // con el alumno y siguen usables: archivarlas las esconde (`listAssignedTo`
  // filtra por estado), que es justo lo que el dueño NO quiere.
  it("SC-PSD-11: skips when reason is trainer-account-deleted (plans stay usable)", async () => {
    const { count } = await cleanupAssignedPlansOnUnlinkHandler(
      testApp,
      link("active"),
      link("terminated", { reason: TRAINER_ACCOUNT_DELETED_REASON }),
    );
    expect(count).toBe(0);
    expect(await exists(ASSIGNED_TA)).toBe(true);
    expect(await statusOf(ASSIGNED_TA)).not.toBe("archived");
  });

  it("SC-PSD-11: any OTHER reason still archives (the guard is not a blanket skip)", async () => {
    for (const reason of ["declined", "cancelled-by-athlete", "algo-que-no-existe"]) {
      await seedRoutines();
      const { count } = await cleanupAssignedPlansOnUnlinkHandler(
        testApp,
        link("active"),
        link("terminated", { reason }),
      );
      expect(count).toBe(1);
      expect(await statusOf(ASSIGNED_TA)).toBe("archived");
    }
  });

  // #1812 — `acceptTrainerLink` cancela las otras solicitudes pending del par al aceptar una: el
  // par queda con un vínculo VIVO y archivarle los planes sería quitárselos a un alumno activo.
  it("#1812: skips a duplicate request cancelled on accept; WITHOUT the marker the same write archives", async () => {
    const cancelada = { terminationReason: "cancelled-by-athlete" };
    const marcada = link("terminated", { ...cancelada, reason: DUPLICATE_REQUEST_REASON });

    expect((await cleanupAssignedPlansOnUnlinkHandler(testApp, link("pending"), marcada)).count).toBe(0);
    expect(await statusOf(ASSIGNED_TA)).not.toBe("archived");

    const sinMarcador = link("terminated", cancelada);
    expect((await cleanupAssignedPlansOnUnlinkHandler(testApp, link("pending"), sinMarcador)).count).toBe(1);
    expect(await statusOf(ASSIGNED_TA)).toBe("archived");
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

// ── #1723: el plan que se asigna a un par sin vínculo vivo ──────────────────

describe("archiveOrphanAssignedPlanHandler (#1723)", () => {
  // Uids propios: otras suites comparten el emulador y `trainer_links`.
  const PF = "orphan-pf";
  const ALUMNO = "orphan-alumno";
  const OTRO_ALUMNO = "orphan-otro-alumno";
  const OTRO_PF = "orphan-otro-pf";
  const PLAN = "orphan-plan";
  const LINK = "orphan-link";

  type Doc = Record<string, unknown>;

  const plan = (extra: Doc = {}): Doc => ({
    name: "Plan asignado tarde",
    source: "trainer-assigned",
    assignedBy: PF,
    assignedTo: ALUMNO,
    visibility: "private",
    status: "active",
    ...extra,
  });
  const pairLink = (status: string, extra: Doc = {}): Doc => ({
    trainerId: PF,
    athleteId: ALUMNO,
    status,
    ...extra,
  });

  // Devuelve el payload tal cual lo vería el evento; a Firestore no se le manda
  // un `undefined` (el SDK lo rechaza): una clave ausente es la misma historia.
  const seedPlan = async (extra: Doc = {}): Promise<Doc> => {
    const data = plan(extra);
    const stored = Object.fromEntries(Object.entries(data).filter(([, v]) => v !== undefined));
    await db().collection("routines").doc(PLAN).set(stored);
    return data;
  };
  const seedLink = (id: string, data: Doc) =>
    db().collection("trainer_links").doc(id).set(data);
  const planSnap = () => db().collection("routines").doc(PLAN).get();
  const planStatus = async () => (await planSnap()).get("status");
  // Si el handler escribiera, aunque fuera el mismo valor, esto cambia.
  const updatedAt = async () => (await planSnap()).updateTime?.toMillis();

  /** Como el trigger: el doc YA existe y el handler recibe lo que se creó. */
  const run = async (extra: Doc = {}): Promise<OrphanPlanResult> =>
    archiveOrphanAssignedPlanHandler(testApp, PLAN, await seedPlan(extra));

  const linkIds = [LINK, `${LINK}-2`];
  async function limpiar(): Promise<void> {
    const batch = db().batch();
    batch.delete(db().collection("routines").doc(PLAN));
    for (const id of linkIds) batch.delete(db().collection("trainer_links").doc(id));
    await batch.commit().catch(() => undefined);
  }
  beforeEach(limpiar);
  afterEach(limpiar);

  it("sin ningún vínculo (un uid que no es alumno del PF): lo archiva y conserva el doc", async () => {
    expect(await run()).toBe("archived");
    const snap = await planSnap();
    // Archiva, no borra: las sesiones ya entrenadas apuntan a este doc.
    expect(snap.exists).toBe(true);
    expect(snap.get("status")).toBe("archived");
    expect(snap.get("name")).toBe("Plan asignado tarde");
  });

  it("con el vínculo ya TERMINADO: lo archiva (el caso de #1723)", async () => {
    await seedLink(LINK, pairLink("terminated", { terminationReason: "athlete-terminated" }));
    expect(await run()).toBe("archived");
    expect(await planStatus()).toBe("archived");
  });

  it("con una solicitud sólo PENDIENTE: lo archiva (pending no es vínculo vivo)", async () => {
    await seedLink(LINK, pairLink("pending"));
    expect(await run()).toBe("archived");
    expect(await planStatus()).toBe("archived");
  });

  it.each(["active", "paused"])("con el vínculo %s: NO lo toca", async (status) => {
    await seedLink(LINK, pairLink(status));
    expect(await run()).toBe("live-link");
    expect(await planStatus()).toBe("active");
  });

  it("un vínculo vivo basta aunque haya otros terminados del mismo par", async () => {
    await seedLink(LINK, pairLink("terminated"));
    await seedLink(`${LINK}-2`, pairLink("active"));
    expect(await run()).toBe("live-link");
    expect(await planStatus()).toBe("active");
  });

  it("el vínculo vivo es del PAR: el de otro alumno, o de otro PF, no cuenta", async () => {
    await seedLink(LINK, { trainerId: PF, athleteId: OTRO_ALUMNO, status: "active" });
    await seedLink(`${LINK}-2`, { trainerId: OTRO_PF, athleteId: ALUMNO, status: "active" });
    expect(await run()).toBe("archived");
    expect(await planStatus()).toBe("archived");
  });

  // #1333 — el PF borró su cuenta: sus planes SE QUEDAN con el alumno y siguen
  // usables. Archivarlos los esconde (`listAssignedTo` filtra por estado).
  it("#1333: un vínculo terminado por trainer-account-deleted NO se archiva", async () => {
    await seedLink(LINK, pairLink("terminated", { reason: TRAINER_ACCOUNT_DELETED_REASON }));
    expect(await run()).toBe("trainer-account-deleted");
    expect(await planStatus()).toBe("active");
  });

  it("#1333: el motivo lo escribe la cascada real del PF, y con ése tampoco se archiva", async () => {
    await seedLink(LINK, pairLink("active"));
    await terminateLinksAsTrainer(testApp, PF);
    const link = await db().collection("trainer_links").doc(LINK).get();
    expect(link.get("reason")).toBe(TRAINER_ACCOUNT_DELETED_REASON);
    expect(await run()).toBe("trainer-account-deleted");
    expect(await planStatus()).toBe("active");
  });

  it("cualquier OTRO motivo de baja sí archiva (la excepción no es un skip general)", async () => {
    for (const reason of ["declined", "cancelled-by-athlete", "algo-que-no-existe"]) {
      await limpiar();
      await seedLink(LINK, pairLink("terminated", { reason }));
      expect(await run()).toBe("archived");
      expect(await planStatus()).toBe("archived");
    }
  });

  it("una plantilla del PF (assignedTo null) no se toca, aunque no haya vínculo", async () => {
    expect(
      await run({ source: "trainer-template", assignedTo: null }),
    ).toBe("skipped");
    expect(await planStatus()).toBe("active");
  });

  it("una rutina propia del alumno (user-created) no se toca", async () => {
    expect(
      await run({ source: "user-created", assignedBy: undefined, assignedTo: undefined, createdBy: ALUMNO }),
    ).toBe("skipped");
    expect(await planStatus()).toBe("active");
  });

  it("un PF que se asigna un plan a sí mismo no tiene par: no se toca", async () => {
    expect(await run({ assignedTo: PF })).toBe("skipped");
    expect(await planStatus()).toBe("active");
  });

  it("un plan que nace ya archivado no se vuelve a escribir", async () => {
    const data = await seedPlan({ status: "archived" });
    const antes = await updatedAt();
    expect(await archiveOrphanAssignedPlanHandler(testApp, PLAN, data)).toBe("skipped");
    expect(await updatedAt()).toBe(antes);
  });

  it("trainer-assigned sin assignedTo usable: 'invalid', y no toca nada", async () => {
    for (const assignedTo of [undefined, "", 7]) {
      expect(await run({ assignedTo })).toBe("invalid");
      expect(await planStatus()).toBe("active");
    }
  });

  it("idempotente: la segunda corrida no escribe (un reintento del trigger)", async () => {
    const data = await seedPlan();
    expect(await archiveOrphanAssignedPlanHandler(testApp, PLAN, data)).toBe("archived");
    const antes = await updatedAt();
    // Mismo payload del evento (dice 'active'): lo que manda es el doc actual.
    expect(await archiveOrphanAssignedPlanHandler(testApp, PLAN, data)).toBe("already-archived");
    expect(await updatedAt()).toBe(antes);
  });

  it("reconcilia: el evento ve un vínculo terminado, pero cuando corre ya se re-armó", async () => {
    // El PF acepta y asigna en el mismo minuto: cuando el handler corre, el
    // vínculo YA está vivo. Lo que manda es el estado actual, no el del evento.
    await seedLink(LINK, pairLink("terminated"));
    const creado = await seedPlan();
    await seedLink(`${LINK}-2`, pairLink("active"));
    expect(await archiveOrphanAssignedPlanHandler(testApp, PLAN, creado)).toBe("live-link");
    expect(await planStatus()).toBe("active");
  });

  it("si el plan se borró antes de correr: 'gone', y no lo vuelve a crear", async () => {
    expect(await archiveOrphanAssignedPlanHandler(testApp, PLAN, plan())).toBe("gone");
    expect((await planSnap()).exists).toBe(false);
  });

  it("el cable: routines/{routineId} en CREATE, southamerica-east1, con retry, y sale por el index", async () => {
    const fn = archiveOrphanAssignedPlanOnCreate;
    expect(fn).toHaveProperty("__endpoint.region", ["southamerica-east1"]);
    expect(fn).toHaveProperty("__endpoint.eventTrigger.retry", true);
    expect(fn).toHaveProperty(
      "__endpoint.eventTrigger.eventType",
      "google.cloud.firestore.document.v1.created",
    );
    expect(fn).toHaveProperty(
      "__endpoint.eventTrigger.eventFilterPathPatterns.document",
      "routines/{routineId}",
    );
    const index = (await import("../index")) as Record<string, unknown>;
    expect(index.archiveOrphanAssignedPlanOnCreate).toBe(fn);
  });
});
