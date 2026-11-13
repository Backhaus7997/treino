/**
 * Tests de `cancelDuplicatePendingLinks` (#1812), contra el emulador de Firestore, y del
 * accept completo (`runAcceptTrainerLink` con el `syncTrainerLoad` REAL) que lo llama.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import {
  DUPLICATE_REQUEST_REASON,
  cancelDuplicatePendingLinks,
} from "../subscriptions/cancel-duplicate-pending-links";
import { runAcceptTrainerLink } from "../subscriptions/accept-trainer-link";

// `??=`: `emulators:exec` ya exporta esto; pisarlo manda los tests al emulador de OTRO worktree.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ??= "treino-dev";

let testApp: App;
beforeAll(() => {
  testApp = initializeApp({ projectId: "treino-dev" }, "cancel-duplicate-pending-test");
});
afterAll(async () => {
  await deleteApp(testApp);
});
const db = () => getFirestore(testApp);

// Uids propios: otras suites comparten el emulador y `trainer_links`.
const PF = "dup-pf";
const ALUMNO = "dup-alumno";
const IDS = ["keep", "dup1", "dup2", "other"].map((n) => `dup-link-${n}`);
const [KEEP, DUP1, DUP2, OTHER] = IDS;

type Doc = Record<string, unknown>;
const link = (status: string, extra: Doc = {}): Doc => ({ trainerId: PF, athleteId: ALUMNO, status, ...extra });
const activo = (): Doc => link("active", { acceptedAt: Timestamp.now() });
const seed = (id: string, data: Doc) => db().collection("trainer_links").doc(id).set(data);
const read = async (id: string) => (await db().collection("trainer_links").doc(id).get()).data();

async function limpiar(): Promise<void> {
  const batch = db().batch();
  for (const id of IDS) batch.delete(db().collection("trainer_links").doc(id));
  batch.delete(db().collection("users").doc(PF));
  await batch.commit().catch(() => undefined);
}
beforeEach(limpiar);
afterEach(limpiar);

describe("cancelDuplicatePendingLinks", () => {
  it("cancela las demás pending del par, con las convenciones de una cancelación", async () => {
    await seed(KEEP, activo());
    await seed(DUP1, link("pending"));
    await seed(DUP2, link("pending"));

    expect(await cancelDuplicatePendingLinks(testApp, KEEP)).toBe(2);

    for (const id of [DUP1, DUP2]) {
      const d = await read(id);
      // La convención que `purgeRejectedLink` ya borra, y el marcador que los triggers leen.
      expect(d).toMatchObject({
        status: "terminated",
        terminationReason: "cancelled-by-athlete",
        reason: DUPLICATE_REQUEST_REASON,
      });
      expect(d?.terminatedAt).toBeInstanceOf(Timestamp);
      expect(d?.acceptedAt).toBeUndefined();
    }
    expect(await read(KEEP)).toMatchObject({ status: "active" }); // el aceptado, intacto
  });

  it("sólo toca el PAR y sólo las pending: otro alumno, otro PF, paused, active o terminated, no", async () => {
    await seed(KEEP, activo());
    await seed(DUP1, link("pending", { athleteId: "dup-otro-alumno" }));
    await seed(DUP2, link("pending", { trainerId: "dup-otro-pf" }));
    await seed(OTHER, link("terminated", { terminationReason: "declined" }));

    expect(await cancelDuplicatePendingLinks(testApp, KEEP)).toBe(0);
    expect([(await read(DUP1))?.status, (await read(DUP2))?.status]).toEqual(["pending", "pending"]);
    expect(await read(OTHER)).toMatchObject({ status: "terminated", terminationReason: "declined" });
    expect((await read(OTHER))?.reason).toBeUndefined();

    await seed(DUP1, link("paused", { acceptedAt: Timestamp.now() })); // mismo par, pero no es una solicitud
    await seed(DUP2, activo());
    expect(await cancelDuplicatePendingLinks(testApp, KEEP)).toBe(0);
    expect([(await read(DUP1))?.status, (await read(DUP2))?.status]).toEqual(["paused", "active"]);
  });

  it("si el aceptado ya no está active o no existe, no hace nada; un pending con acceptedAt no se toca", async () => {
    await seed(KEEP, link("terminated", { acceptedAt: Timestamp.now() }));
    await seed(DUP1, link("pending"));
    expect(await cancelDuplicatePendingLinks(testApp, KEEP)).toBe(0);
    expect(await cancelDuplicatePendingLinks(testApp, "no-existe")).toBe(0);

    await seed(KEEP, activo());
    await seed(DUP1, link("pending", { acceptedAt: Timestamp.now() })); // defecto de datos: ante la duda, no
    expect(await cancelDuplicatePendingLinks(testApp, KEEP)).toBe(0);
    expect(await read(DUP1)).toMatchObject({ status: "pending" });
  });

  it("idempotente: la segunda corrida no encuentra nada que cancelar", async () => {
    await seed(KEEP, activo());
    await seed(DUP1, link("pending"));

    expect(await cancelDuplicatePendingLinks(testApp, KEEP)).toBe(1);
    expect(await cancelDuplicatePendingLinks(testApp, KEEP)).toBe(0);
  });
});

describe("runAcceptTrainerLink — el accept completo cancela las duplicadas (#1812)", () => {
  // El caso del issue: dos dispositivos del alumno crearon dos solicitudes al mismo PF.
  beforeEach(() => db().collection("users").doc(PF).set({ subscription: { tier: "plan1", status: "active" } }));

  it("aceptar una deja la otra terminada, no pending", async () => {
    await seed(DUP1, link("pending"));
    await seed(DUP2, link("pending"));

    expect((await runAcceptTrainerLink(testApp, PF, DUP1)).status).toBe("ok");

    expect(await read(DUP1)).toMatchObject({ status: "active" });
    expect(await read(DUP2)).toMatchObject({ status: "terminated", reason: DUPLICATE_REQUEST_REASON });
  });

  it("el reintento de un accept (noop) completa una limpieza que había fallado", async () => {
    await seed(DUP1, activo()); // el primer intento promovió y la limpieza no corrió
    await seed(DUP2, link("pending"));

    expect((await runAcceptTrainerLink(testApp, PF, DUP1)).status).toBe("noop");
    expect(await read(DUP2)).toMatchObject({ status: "terminated", reason: DUPLICATE_REQUEST_REASON });
  });

  it("si el accept se rechaza (wrong-status) no cancela nada", async () => {
    await seed(DUP1, link("terminated", { terminationReason: "declined" }));
    await seed(DUP2, link("pending"));

    await expect(runAcceptTrainerLink(testApp, PF, DUP1)).rejects.toMatchObject({ code: "failed-precondition" });
    expect(await read(DUP2)).toMatchObject({ status: "pending" });
  });
});
