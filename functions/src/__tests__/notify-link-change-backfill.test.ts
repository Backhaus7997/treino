/**
 * Tests del BACKFILL de `linkId` en chats preexistentes (notifyOnLinkChange).
 *
 * POR QUE EXISTE ESTE ARCHIVO. `senderMayPost` (firestore.rules) deja postear
 * si el DOC DEL CHAT tiene `linkId`, o si es una consulta, o si hay follow
 * aceptado. El cliente estampa `linkId` SÓLO al crear el chat. Un par que se
 * escribió primero como chat social y se vinculó DESPUES nunca lo recibe, y el
 * alumno vinculado a su PF queda viendo "Para escribirle, esta persona tiene
 * que seguirte". Completarlo desde el cliente tampoco se puede: `chats/update`
 * tiene `linkId` PINEADO INMUTABLE. Hace falta el Admin SDK.
 *
 * LA INVARIANTE QUE ESTE ARCHIVO DEFIENDE. `chatCreateOk` define qué es un
 * `linkId` válido en un chat: el link existe, su `status` está en
 * ['active','paused'], y trainerId y athleteId son los dos miembros. El
 * backfill no puede romperla, y de ahí salen los controles negativos: estampar
 * en `pending` le daría escritura al alumno ANTES de que el PF acepte, que es
 * justo el gate que el vínculo representa.
 *
 * Corre contra el emulador de Firestore, igual que notify-link-change.test.ts.
 */

import * as admin from "firebase-admin";
import { notifyOnLinkChangeHandler } from "../notifications/notify-link-change";

// `??=` y no `=`: `emulators:exec` YA exporta estas variables apuntando a los
// puertos que levantó. Pisarlas con 8080/9099 a ciegas manda los tests al
// emulador de OTRO worktree si ese tiene los puertos default tomados — este
// repo corre con ~30 worktrees a la vez y eso pasa seguido. El default queda
// para cuando alguien corre jest suelto contra un emulador default.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.GCLOUD_PROJECT ??= "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "notify-link-change-backfill-test",
  );
});

afterAll(async () => {
  // El borrado del chat va ANTES de tirar la app: `admin.firestore(testApp)`
  // sobre una app destruida tira "app deleted" y ensucia el resultado.
  await db()
    .collection("chats")
    .doc(chatIdFor(TRAINER, ATHLETE))
    .delete()
    .catch(() => undefined);
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

function makeMockMessaging(): admin.messaging.Messaging {
  return {
    sendEachForMulticast: jest.fn(
      async (msg: admin.messaging.MulticastMessage) => ({
        successCount: msg.tokens.length,
        failureCount: 0,
        responses: msg.tokens.map(() => ({ success: true, messageId: "id" })),
      }),
    ),
  } as unknown as admin.messaging.Messaging;
}

/// Mismo criterio que `ChatRepository.chatIdFor`: uids ORDENADOS y unidos con
/// '_', para que los dos miembros resuelvan al mismo doc.
function chatIdFor(a: string, b: string): string {
  return [a, b].sort().join("_");
}

// El trainer va DESPUES del athlete alfabéticamente a propósito: si el backfill
// armara el id como `${trainerId}_${athleteId}` en vez de ordenarlo, estos
// tests fallarían en vez de pasar por casualidad.
const TRAINER = "zz-trainer";
const ATHLETE = "aa-athlete";
const LINK_ID = "link-backfill-1";

async function seedChat(fields: Record<string, unknown>): Promise<string> {
  const id = chatIdFor(TRAINER, ATHLETE);
  await db()
    .collection("chats")
    .doc(id)
    .set({
      chatId: id,
      members: [ATHLETE, TRAINER].sort(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      ...fields,
    });
  return id;
}

async function readChat(): Promise<Record<string, unknown> | undefined> {
  const snap = await db()
    .collection("chats")
    .doc(chatIdFor(TRAINER, ATHLETE))
    .get();
  return snap.exists ? (snap.data() as Record<string, unknown>) : undefined;
}

async function runHandler(
  beforeStatus: string | undefined,
  afterStatus: string,
): Promise<void> {
  await notifyOnLinkChangeHandler(
    testApp,
    LINK_ID,
    beforeStatus === undefined ? undefined : { status: beforeStatus },
    { status: afterStatus, trainerId: TRAINER, athleteId: ATHLETE },
    makeMockMessaging(),
  );
}

beforeEach(async () => {
  await db()
    .collection("chats")
    .doc(chatIdFor(TRAINER, ATHLETE))
    .delete()
    .catch(() => undefined);
});

describe("backfill de linkId en chats preexistentes", () => {
  it("pending → active: el chat social preexistente recibe linkId", async () => {
    await seedChat({});
    await runHandler("pending", "active");
    expect((await readChat())?.linkId).toBe(LINK_ID);
  });

  it("active → paused también estampa: pausar es un hold, no un corte", async () => {
    await seedChat({});
    await runHandler("active", "paused");
    expect((await readChat())?.linkId).toBe(LINK_ID);
  });

  it("idempotente: un linkId ya puesto NO se pisa", async () => {
    await seedChat({ linkId: "link-anterior" });
    await runHandler("pending", "active");
    expect((await readChat())?.linkId).toBe("link-anterior");
  });

  it("si el chat no existe no lo crea ni explota", async () => {
    await runHandler("pending", "active");
    expect(await readChat()).toBeUndefined();
  });

  it("→ pending NO estampa: el PF todavía no aceptó", async () => {
    await seedChat({});
    await runHandler(undefined, "pending");
    expect((await readChat())?.linkId).toBeUndefined();
  });

  it("→ terminated NO estampa", async () => {
    await seedChat({});
    await runHandler("active", "terminated");
    expect((await readChat())?.linkId).toBeUndefined();
  });

  it("el doc id sale de los uids ORDENADOS, no de trainer-primero", async () => {
    await seedChat({});
    await runHandler("pending", "active");

    // El id ingenuo `${trainerId}_${athleteId}` no debe haberse tocado.
    const naive = await db()
      .collection("chats")
      .doc(`${TRAINER}_${ATHLETE}`)
      .get();
    expect(naive.exists).toBe(false);
    expect((await readChat())?.linkId).toBe(LINK_ID);
  });

  it("no toca members ni kind al estampar", async () => {
    await seedChat({ kind: "inquiry" });
    await runHandler("pending", "active");
    const chat = await readChat();
    expect(chat?.linkId).toBe(LINK_ID);
    expect(chat?.kind).toBe("inquiry");
    expect(chat?.members).toEqual([ATHLETE, TRAINER].sort());
  });
});
