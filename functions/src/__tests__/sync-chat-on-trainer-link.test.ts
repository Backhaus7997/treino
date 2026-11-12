/** Tests de `syncChatOnTrainerLink` (#1697), contra el emulador. El handler RELEE los vínculos
 * del par: `transition()` siembra el estado ACTUAL (como un trigger, post-commit) y le pasa before/after. */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import {
  SyncChatResult,
  syncChatOnTrainerLink,
  syncChatOnTrainerLinkHandler as run,
} from "../chat/sync-chat-on-trainer-link";
import { terminateLinksAsTrainer } from "../cascade/trainer-data";
import { terminateTrainerLinks } from "../cascade/trainer-links";

// `??=`: `emulators:exec` ya exporta esto; pisarlo manda los tests al emulador de OTRO worktree.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "treino-dev";

let testApp: App;
beforeAll(() => {
  testApp = initializeApp({ projectId: "treino-dev" }, "sync-chat-on-trainer-link-test");
});
afterAll(async () => {
  await cleanup();
  await deleteApp(testApp);
});
const db = () => getFirestore(testApp);

// El PF va DESPUÉS del alumno: un id `${trainer}_${athlete}` sin ordenar fallaría.
const TRAINER = "zz-scl-trainer";
const ATHLETE = "aa-scl-athlete";
const [L1, L2, L3, L4, L5] = ["l1", "l2", "l3", "l4", "l5"].map((n) => `scl-link-${n}`);
const ATHLETE_REASON = "athlete-terminated";
const CHAT = [TRAINER, ATHLETE].sort().join("_");
const NAIVE_CHAT = `${TRAINER}_${ATHLETE}`;

type Doc = Record<string, unknown>;
const link = (status: string, extra: Doc = {}): Doc => ({
  trainerId: TRAINER,
  athleteId: ATHLETE,
  status,
  ...extra,
});

const seedChat = (fields: Doc = {}) =>
  db().collection("chats").doc(CHAT).set({
    chatId: CHAT,
    members: [TRAINER, ATHLETE].sort(),
    createdAt: FieldValue.serverTimestamp(),
    ...fields,
  });
const readChat = async () => (await db().collection("chats").doc(CHAT).get()).data();
const seedLink = (id: string, data: Doc) => db().collection("trainer_links").doc(id).set(data);
const isClosed = async () => (await readChat())?.closedAt instanceof Timestamp;
const isOpen = async () => (await readChat())?.closedAt === undefined;

/** El write YA ocurrió (el trigger dispara post-commit); el handler recibe before/after. */
async function transition(id: string, before?: Doc, after?: Doc): Promise<SyncChatResult> {
  const ref = db().collection("trainer_links").doc(id);
  if (after) await ref.set(after);
  else await ref.delete();
  return run(testApp, id, before, after);
}

async function cleanup(): Promise<void> {
  const b = db().batch();
  for (const id of [CHAT, NAIVE_CHAT]) b.delete(db().collection("chats").doc(id));
  for (const id of [L1, L2, L3, L4, L5]) b.delete(db().collection("trainer_links").doc(id));
  await b.commit().catch(() => undefined);
}
beforeEach(cleanup);

describe("vivo → no vivo: cierra", () => {
  it.each([
    ["active → terminated por el PF (sin terminationReason)", link("active"), link("terminated")],
    ["active → terminated por el alumno", link("active"), link("terminated", { terminationReason: ATHLETE_REASON })],
    ["paused → terminated", link("paused"), link("terminated")],
    ["un vínculo vivo que se BORRA", link("active"), undefined],
  ])("%s", async (_name, before, after) => {
    await seedChat({ linkId: L1, kind: "inquiry", lastMessageText: "hola" });

    expect(await transition(L1, before, after)).toBe("closed");

    // `serverTimestamp()` resuelto a Timestamp, y el resto del doc intacto.
    expect(await isClosed()).toBe(true);
    expect(await readChat()).toMatchObject({ linkId: L1, kind: "inquiry", lastMessageText: "hola" });
  });
});

describe("lo que NO cierra", () => {
  it.each([
    ["rechazo (pending → terminated)", link("pending"), link("terminated", { terminationReason: "declined" })],
    ["cancelación (pending → terminated)", link("pending"),
      link("terminated", { terminationReason: "cancelled-by-athlete" })],
    ["purge del rechazo (delete)", link("terminated", { terminationReason: "declined" }), undefined],
    ["active → paused (un hold)", link("active"), link("paused")],
    ["write sin cambio de status (entitlements)", link("active"), link("active", { entitlement: "blocked" })],
  ])("%s", async (_name, before, after) => {
    await seedChat({ kind: "inquiry" });
    expect(await transition(L1, before, after)).toBe("skipped");
    expect(await isOpen()).toBe(true);
  });

  it.each(["active", "paused"])("otro vínculo %s del mismo par lo mantiene abierto", async (status) => {
    await seedChat();
    await seedLink(L2, link(status));
    expect(await transition(L1, link("active"), link("terminated"))).toBe("unchanged");
    expect(await isOpen()).toBe(true);
  });

  it("control negativo: vivos de OTRO par, y viejos terminated/pending del par, no cuentan", async () => {
    await seedChat();
    await seedLink(L2, { trainerId: "yy-other-trainer", athleteId: ATHLETE, status: "active" });
    await seedLink(L3, { trainerId: TRAINER, athleteId: "bb-other-athlete", status: "active" });
    await seedLink(L4, link("terminated"));
    await seedLink(L5, link("pending"));
    expect(await transition(L1, link("active"), link("terminated"))).toBe("closed");
  });
});

describe("no vivo → vivo: el re-vínculo reabre", () => {
  it.each([
    ["pending → active", link("pending"), link("active")],
    ["pending → paused", link("pending"), link("paused")],
    ["create ya active (Admin SDK)", undefined, link("active")],
  ])("%s", async (_name, before, after) => {
    await seedChat({ closedAt: Timestamp.now() });
    expect(await transition(L1, before, after)).toBe("reopened");
    expect("closedAt" in ((await readChat()) as Doc)).toBe(false); // borrado, no null
  });

  it("sobre un chat ya abierto no escribe", async () => {
    await seedChat();
    expect(await transition(L1, link("pending"), link("active"))).toBe("unchanged");
  });
});

it("si el par no tiene chat no lo crea (ni al terminar ni al vincular); un doc sin uids no explota", async () => {
  expect(await transition(L1, link("active"), link("terminated"))).toBe("no-chat");
  expect(await transition(L1, link("pending"), link("active"))).toBe("no-chat");
  expect(await run(testApp, L1, { status: "active" }, { status: "terminated" })).toBe("invalid");
  for (const id of [CHAT, NAIVE_CHAT]) {
    expect((await db().collection("chats").doc(id).get()).exists).toBe(false);
  }
});

describe("idempotencia, reentregas y concurrencia", () => {
  it("reentregar el evento no re-estampa closedAt", async () => {
    await seedChat();
    expect(await transition(L1, link("active"), link("terminated"))).toBe("closed");
    const stamped = (await readChat())?.closedAt as Timestamp;

    expect(await run(testApp, L1, link("active"), link("terminated"))).toBe("unchanged");
    expect(((await readChat())?.closedAt as Timestamp).isEqual(stamped)).toBe(true);
  });

  it("un `pending → active` reentregado DESPUÉS de terminar NO reabre", async () => {
    await seedChat({ closedAt: Timestamp.now() });
    await seedLink(L1, link("terminated"));
    expect(await run(testApp, L1, link("pending"), link("active"))).toBe("unchanged");
    expect(await isClosed()).toBe(true);
  });

  it("un `active → terminated` reentregado DESPUÉS de un re-vínculo NO cierra", async () => {
    await seedChat();
    await seedLink(L1, link("terminated"));
    await seedLink(L2, link("active"));
    expect(await run(testApp, L1, link("active"), link("terminated"))).toBe("unchanged");
    expect(await isOpen()).toBe(true);
  });

  it("dos terminaciones concurrentes convergen a UN cierre", async () => {
    await seedChat();
    await seedLink(L1, link("terminated"));
    await seedLink(L2, link("terminated"));
    const results = await Promise.all([
      run(testApp, L1, link("active"), link("terminated")),
      run(testApp, L2, link("active"), link("terminated")),
    ]);
    expect([...results].sort()).toEqual(["closed", "unchanged"]);
    expect(await isClosed()).toBe(true);
  });

  it("una terminación y un re-vínculo concurrentes convergen a ABIERTO", async () => {
    await seedChat({ closedAt: Timestamp.now() });
    await seedLink(L1, link("terminated"));
    await seedLink(L2, link("active"));
    await Promise.all([
      run(testApp, L1, link("active"), link("terminated")),
      run(testApp, L2, link("pending"), link("active")),
    ]);
    expect(await isOpen()).toBe(true);
  });
});

it.each([
  ["el alumno", "active", "account-deleted", () => terminateTrainerLinks(testApp, ATHLETE)],
  ["el PF", "paused", "trainer-account-deleted", () => terminateLinksAsTrainer(testApp, TRAINER)],
])("borrado de cuenta de %s: cierra, con lo que la cascada REAL escribe", async (_who, status, reason, cascade) => {
  await seedChat();
  await seedLink(L1, link(status));
  const ref = db().collection("trainer_links").doc(L1);
  const before = (await ref.get()).data() as Doc;

  await cascade();
  const after = (await ref.get()).data() as Doc;
  expect(after).toMatchObject({ status: "terminated", reason });

  expect(await run(testApp, L1, before, after)).toBe("closed");
  expect(await isClosed()).toBe(true);
});

it("el cable: trainer_links/{linkId}, southamerica-east1, retry, y sale por el index", async () => {
  const fn = syncChatOnTrainerLink;
  expect(fn).toHaveProperty("__endpoint.region", ["southamerica-east1"]);
  expect(fn).toHaveProperty("__endpoint.eventTrigger.retry", true);
  expect(fn).toHaveProperty("__endpoint.eventTrigger.eventFilterPathPatterns.document", "trainer_links/{linkId}");
  expect(((await import("../index")) as Doc).syncChatOnTrainerLink).toBe(fn);
});
