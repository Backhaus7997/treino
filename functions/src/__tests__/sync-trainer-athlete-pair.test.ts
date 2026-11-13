/** Tests de `syncTrainerAthletePair` (#1806), contra el emulador. El handler RELEE los vínculos
 * del par: `transition()` siembra el estado ACTUAL (como un trigger, post-commit) y le pasa before/after. */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import {
  SyncPairResult,
  reducePairStatus,
  syncTrainerAthletePair,
  syncTrainerAthletePairHandler as run,
} from "../sync-trainer-athlete-pair";
import { terminateLinksAsTrainer } from "../cascade/trainer-data";
import { terminateTrainerLinks } from "../cascade/trainer-links";

// `??=`: `emulators:exec` ya exporta esto; pisarlo manda los tests al emulador de OTRO worktree.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "treino-dev";

let testApp: App;
beforeAll(() => {
  testApp = initializeApp({ projectId: "treino-dev" }, "sync-trainer-athlete-pair-test");
});
afterAll(async () => {
  await cleanup();
  await deleteApp(testApp);
});
const db = () => getFirestore(testApp);

// El PF va DESPUÉS del alumno en orden alfabético: un id ordenado (el del chat) fallaría.
const TRAINER = "zz-stap-trainer";
const ATHLETE = "aa-stap-athlete";
const [L1, L2, L3, L4, L5] = ["l1", "l2", "l3", "l4", "l5"].map((n) => `stap-link-${n}`);
const PAIR = `${TRAINER}_${ATHLETE}`;
const SORTED = [TRAINER, ATHLETE].sort().join("_");

type Doc = Record<string, unknown>;
const link = (status: string, extra: Doc = {}): Doc => ({
  trainerId: TRAINER,
  athleteId: ATHLETE,
  status,
  ...extra,
});

const pairRef = () => db().collection("trainer_athlete_pairs").doc(PAIR);
const readPair = async () => (await pairRef().get()).data();
const seedLink = (id: string, data: Doc) => db().collection("trainer_links").doc(id).set(data);

/** El write YA ocurrió (el trigger dispara post-commit); el handler recibe before/after. */
async function transition(id: string, before?: Doc, after?: Doc): Promise<SyncPairResult> {
  const ref = db().collection("trainer_links").doc(id);
  if (after) await ref.set(after);
  else await ref.delete();
  return run(testApp, id, before, after);
}

async function cleanup(): Promise<void> {
  const b = db().batch();
  for (const id of [PAIR, SORTED]) b.delete(db().collection("trainer_athlete_pairs").doc(id));
  for (const id of [L1, L2, L3, L4, L5]) b.delete(db().collection("trainer_links").doc(id));
  await b.commit().catch(() => undefined);
}
beforeEach(cleanup);

describe("reducePairStatus: el mejor status del par", () => {
  it.each([
    [[], null],
    [["terminated", "active"], "active"],
    [["terminated", "paused", "pending"], "paused"],
    [["terminated", "pending"], "pending"],
    [["terminated"], "terminated"],
    [["raro", undefined], "terminated"],
  ])("%j → %s", (statuses, expected) => {
    expect(reducePairStatus(statuses)).toBe(expected);
  });
});

describe("escribe el par con lo que dicen TODOS sus vínculos", () => {
  it.each([
    ["solicitud nueva (create pending)", undefined, link("pending"), "pending", false],
    ["pending → active (aceptó)", link("pending"), link("active"), "active", true],
    ["create ya active (Admin SDK)", undefined, link("active"), "active", true],
    ["active → paused (un hold sigue vivo)", link("active"), link("paused"), "paused", true],
    ["paused → active", link("paused"), link("active"), "active", true],
    ["active → terminated por el PF", link("active"), link("terminated"), "terminated", false],
    ["active → terminated por el alumno", link("active"),
      link("terminated", { terminationReason: "athlete-terminated" }), "terminated", false],
    ["paused → terminated", link("paused"), link("terminated"), "terminated", false],
    ["rechazo (pending → terminated)", link("pending"),
      link("terminated", { terminationReason: "declined" }), "terminated", false],
  ])("%s", async (_name, before, after, status, live) => {
    expect(await transition(L1, before, after)).toBe("written");

    const pair = await readPair();
    expect(pair).toMatchObject({ trainerId: TRAINER, athleteId: ATHLETE, status, live });
    expect(pair?.updatedAt).toBeInstanceOf(Timestamp);
    // Id PF-primero, no el ordenado del chat.
    expect((await db().collection("trainer_athlete_pairs").doc(SORTED).get()).exists).toBe(false);
  });

  it.each(["active", "paused"])("otro vínculo %s del par lo mantiene vivo cuando termina uno", async (s) => {
    await pairRef().set({ trainerId: TRAINER, athleteId: ATHLETE, live: true, status: s });
    await seedLink(L2, link(s));
    expect(await transition(L1, link("active"), link("terminated"))).toBe("unchanged");
    expect(await readPair()).toMatchObject({ live: true, status: s });
  });

  it("control negativo: vivos de OTRO par no cuentan", async () => {
    await seedLink(L2, { trainerId: "yy-other-trainer", athleteId: ATHLETE, status: "active" });
    await seedLink(L3, { trainerId: TRAINER, athleteId: "bb-other-athlete", status: "active" });
    await seedLink(L4, link("terminated"));
    await seedLink(L5, link("pending"));
    expect(await transition(L1, link("active"), link("terminated"))).toBe("written");
    expect(await readPair()).toMatchObject({ live: false, status: "pending" });
  });

  it("un par con doc desfasado se corrige (status, live o uids distintos)", async () => {
    await pairRef().set({ trainerId: "otro", athleteId: ATHLETE, live: false, status: "active" });
    expect(await transition(L1, link("pending"), link("active"))).toBe("written");
    expect(await readPair()).toMatchObject({ trainerId: TRAINER, live: true, status: "active" });
  });
});

describe("lo que no escribe", () => {
  it("un update sin cambio de status (barrido de entitlements) sale SIN leer", async () => {
    await seedLink(L1, link("active"));
    expect(await run(testApp, L1, link("active"), link("active", { entitlement: "blocked" }))).toBe("skipped");
    expect((await pairRef().get()).exists).toBe(false); // no lo crea: eso es del backfill
  });

  it("un doc sin uids no explota", async () => {
    expect(await run(testApp, L1, { status: "pending" }, { status: "active" })).toBe("invalid");
    expect(await run(testApp, L1, undefined, { trainerId: TRAINER, status: "active" })).toBe("invalid");
  });

  it("reentregar el evento no re-escribe (updatedAt queda igual)", async () => {
    expect(await transition(L1, link("pending"), link("active"))).toBe("written");
    const stamped = (await readPair())?.updatedAt as Timestamp;
    expect(await run(testApp, L1, link("pending"), link("active"))).toBe("unchanged");
    expect(((await readPair())?.updatedAt as Timestamp).isEqual(stamped)).toBe(true);
  });
});

describe("borrados", () => {
  it("la purga del ÚLTIMO vínculo del par borra el doc", async () => {
    await pairRef().set({ trainerId: TRAINER, athleteId: ATHLETE, live: false, status: "terminated" });
    expect(await transition(L1, link("terminated", { terminationReason: "declined" }), undefined)).toBe("deleted");
    expect((await pairRef().get()).exists).toBe(false);
  });

  it("la purga de un rechazo viejo NO toca un par vivo", async () => {
    await pairRef().set({ trainerId: TRAINER, athleteId: ATHLETE, live: true, status: "active" });
    await seedLink(L2, link("active"));
    expect(await transition(L1, link("terminated", { terminationReason: "declined" }), undefined)).toBe("unchanged");
    expect(await readPair()).toMatchObject({ live: true, status: "active" });
  });

  it("borrar un vínculo vivo con otro terminado del par apaga el par", async () => {
    await pairRef().set({ trainerId: TRAINER, athleteId: ATHLETE, live: true, status: "active" });
    await seedLink(L2, link("terminated"));
    expect(await transition(L1, link("active"), undefined)).toBe("written");
    expect(await readPair()).toMatchObject({ live: false, status: "terminated" });
  });

  it("sin doc ni vínculos, borrar no hace nada", async () => {
    expect(await transition(L1, link("terminated"), undefined)).toBe("unchanged");
    expect((await pairRef().get()).exists).toBe(false);
  });
});

describe("reentregas y concurrencia", () => {
  it("un `pending → active` reentregado DESPUÉS de terminar NO prende el par", async () => {
    await pairRef().set({ trainerId: TRAINER, athleteId: ATHLETE, live: false, status: "terminated" });
    await seedLink(L1, link("terminated"));
    expect(await run(testApp, L1, link("pending"), link("active"))).toBe("unchanged");
    expect(await readPair()).toMatchObject({ live: false, status: "terminated" });
  });

  it("un `active → terminated` reentregado DESPUÉS de un re-vínculo NO apaga el par", async () => {
    await pairRef().set({ trainerId: TRAINER, athleteId: ATHLETE, live: true, status: "active" });
    await seedLink(L1, link("terminated"));
    await seedLink(L2, link("active"));
    expect(await run(testApp, L1, link("active"), link("terminated"))).toBe("unchanged");
    expect(await readPair()).toMatchObject({ live: true });
  });

  it("una terminación y un re-vínculo concurrentes convergen a VIVO", async () => {
    await pairRef().set({ trainerId: TRAINER, athleteId: ATHLETE, live: true, status: "active" });
    await seedLink(L1, link("terminated"));
    await seedLink(L2, link("active"));
    await Promise.all([
      run(testApp, L1, link("active"), link("terminated")),
      run(testApp, L2, link("pending"), link("active")),
    ]);
    expect(await readPair()).toMatchObject({ live: true, status: "active" });
  });
});

it.each([
  ["el alumno", "active", "account-deleted", () => terminateTrainerLinks(testApp, ATHLETE)],
  ["el PF", "paused", "trainer-account-deleted", () => terminateLinksAsTrainer(testApp, TRAINER)],
])("borrado de cuenta de %s: apaga el par, con lo que escribe la cascada REAL", async (_w, status, reason, cascade) => {
  await pairRef().set({ trainerId: TRAINER, athleteId: ATHLETE, live: true, status });
  await seedLink(L1, link(status));
  const ref = db().collection("trainer_links").doc(L1);
  const before = (await ref.get()).data() as Doc;

  await cascade();
  const after = (await ref.get()).data() as Doc;
  expect(after).toMatchObject({ status: "terminated", reason });

  expect(await run(testApp, L1, before, after)).toBe("written");
  expect(await readPair()).toMatchObject({ live: false, status: "terminated" });
});

it("el cable: trainer_links/{linkId}, southamerica-east1, retry, y sale por el index", async () => {
  const fn = syncTrainerAthletePair;
  expect(fn).toHaveProperty("__endpoint.region", ["southamerica-east1"]);
  expect(fn).toHaveProperty("__endpoint.eventTrigger.retry", true);
  expect(fn).toHaveProperty("__endpoint.eventTrigger.eventFilterPathPatterns.document", "trainer_links/{linkId}");
  expect(((await import("../index")) as Doc).syncTrainerAthletePair).toBe(fn);
});
