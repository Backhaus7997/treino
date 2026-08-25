/**
 * Tests de los callables de email de auth.
 *
 * Corren contra el emulador de Firestore + Auth.
 * FIRESTORE_EMULATOR_HOST=127.0.0.1:8080, FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
 *
 * El bloque que importa es el de ANTI-ENUMERACION (REQ-AUTH-011): la respuesta
 * tiene que ser idéntica exista o no la cuenta. Si alguna vez uno de esos
 * tests se pone rojo, el endpoint se convirtió en un oráculo de cuentas.
 */

import * as admin from "firebase-admin";
import {
  runRequestPasswordReset,
  runRequestEmailVerification,
  throttleWindow,
} from "../auth/request-auth-email";
import { dedupeKey } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION, MailQueueDoc } from "../mail/types";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp({ projectId: "treino-dev" }, "auth-email-test");
});

afterAll(async () => {
  await testApp.delete();
});

const db = () => admin.firestore(testApp);

// Reloj fijo para que la ventana de throttling sea determinista.
const NOW = Date.UTC(2026, 7, 21, 12, 0, 0);

async function readQueueDoc(id: string): Promise<MailQueueDoc | undefined> {
  const snap = await db().collection(MAIL_QUEUE_COLLECTION).doc(id).get();
  return snap.data() as MailQueueDoc | undefined;
}

async function purgeQueueFor(uid: string): Promise<void> {
  const snap = await db()
    .collection(MAIL_QUEUE_COLLECTION)
    .where("toUid", "==", uid)
    .get();
  for (const d of snap.docs) await d.ref.delete();
}

async function queueCountFor(uid: string): Promise<number> {
  const snap = await db()
    .collection(MAIL_QUEUE_COLLECTION)
    .where("toUid", "==", uid)
    .get();
  return snap.size;
}

/**
 * Crea el usuario de prueba, borrando primero cualquier resto.
 *
 * Deliberadamente NO se traga el error de `createUser`. Un `.catch(() => {})`
 * ahí convierte un setup fallido en un test que corre contra el estado del
 * test anterior y afirma cosas sobre un usuario que no es el que cree: falla
 * bajo carga y pasa aislado, que es la peor combinación posible.
 */
async function seedUser(opts: {
  uid: string;
  email: string;
  emailVerified?: boolean;
}): Promise<void> {
  await admin.auth(testApp).deleteUser(opts.uid).catch(() => undefined);
  await admin.auth(testApp).createUser({
    uid: opts.uid,
    email: opts.email,
    emailVerified: opts.emailVerified ?? false,
  });
}

// ---------------------------------------------------------------------------
// Anti-enumeración — REQ-AUTH-011
// ---------------------------------------------------------------------------
describe("REQ-AUTH-011: requestPasswordReset nunca revela si la cuenta existe", () => {
  const uid = "auth-mail-known";
  const email = "conocido@example.com";

  beforeEach(async () => {
    await seedUser({ uid, email });
  });

  afterEach(async () => {
    await purgeQueueFor(uid);
    await admin.auth(testApp).deleteUser(uid).catch(() => undefined);
  });

  it("devuelve la MISMA respuesta para una cuenta que existe y una que no", async () => {
    const existe = await runRequestPasswordReset(testApp, email, NOW);
    const noExiste = await runRequestPasswordReset(
      testApp,
      "fantasma@example.com",
      NOW,
    );

    expect(existe).toEqual({ status: "ok" });
    expect(noExiste).toEqual({ status: "ok" });
    expect(existe).toEqual(noExiste);
  });

  it("no tira para una dirección desconocida", async () => {
    await expect(
      runRequestPasswordReset(testApp, "fantasma@example.com", NOW),
    ).resolves.toEqual({ status: "ok" });
  });

  it("no tira para entradas basura", async () => {
    for (const basura of [undefined, null, 42, "", "  ", "sin-arroba", {}]) {
      await expect(
        runRequestPasswordReset(testApp, basura, NOW),
      ).resolves.toEqual({ status: "ok" });
    }
  });

  it("una dirección desconocida no encola NADA", async () => {
    const antes = (await db().collection(MAIL_QUEUE_COLLECTION).get()).size;
    await runRequestPasswordReset(testApp, "fantasma@example.com", NOW);
    const despues = (await db().collection(MAIL_QUEUE_COLLECTION).get()).size;

    expect(despues).toBe(antes);
  });
});

// ---------------------------------------------------------------------------
// Camino feliz
// ---------------------------------------------------------------------------
describe("requestPasswordReset: cuenta que existe", () => {
  const uid = "auth-mail-happy";
  const email = "feliz@example.com";
  const id = dedupeKey("password-reset", `${uid}_${throttleWindow(NOW)}`, uid);

  beforeEach(async () => {
    await seedUser({ uid, email });
  });

  afterEach(async () => {
    await purgeQueueFor(uid);
    await admin.auth(testApp).deleteUser(uid).catch(() => undefined);
  });

  it("encola el mail con el link de un solo uso", async () => {
    await runRequestPasswordReset(testApp, email, NOW);

    const doc = await readQueueDoc(id);
    expect(doc?.kind).toBe("password-reset");
    expect(doc?.toUid).toBe(uid);
    expect(doc?.status).toBe("pending");
    // El link lo minta el Admin SDK y lleva el oobCode.
    expect(String(doc?.params.actionLink)).toContain("oobCode=");
  });

  it("normaliza mayúsculas y espacios de la dirección", async () => {
    await runRequestPasswordReset(testApp, "  FELIZ@Example.COM  ", NOW);

    expect(await readQueueDoc(id)).toBeDefined();
  });

  it("es transaccional: no lleva prefKey", async () => {
    await runRequestPasswordReset(testApp, email, NOW);

    // Recuperar la cuenta no puede depender de una preferencia: quien no puede
    // entrar tampoco puede entrar a cambiarla.
    expect((await readQueueDoc(id))?.prefKey).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Throttling por ventana
// ---------------------------------------------------------------------------
describe("requestPasswordReset: limita la tasa por ventana", () => {
  const uid = "auth-mail-throttle";
  const email = "throttle@example.com";

  beforeEach(async () => {
    await seedUser({ uid, email });
  });

  afterEach(async () => {
    await purgeQueueFor(uid);
    await admin.auth(testApp).deleteUser(uid).catch(() => undefined);
  });

  it("diez pedidos en la misma ventana producen UN solo mail", async () => {
    for (let i = 0; i < 10; i++) {
      await runRequestPasswordReset(testApp, email, NOW);
    }

    expect(await queueCountFor(uid)).toBe(1);
  });

  it("un pedido en la ventana siguiente SÍ manda de nuevo", async () => {
    await runRequestPasswordReset(testApp, email, NOW);
    // +90s cae en otra ventana (THROTTLE_WINDOW_MIN = 1).
    await runRequestPasswordReset(testApp, email, NOW + 90 * 1000);

    // Quien de verdad no puede entrar tiene que poder reintentar.
    expect(await queueCountFor(uid)).toBe(2);
  });

  // La ventana del servidor tiene que seguir alineada con el cooldown del
  // botón "Reenviar" de forgot_password_screen.dart (_resendCooldown = 60s).
  // Si esta ventana creciera, ese botón mostraría confirmación y el mail se
  // descartaría en silencio por deduplicación.
  it("la ventana dura un minuto, alineada con el cooldown del cliente", () => {
    expect(throttleWindow(NOW)).toBe(throttleWindow(NOW + 30 * 1000));
    expect(throttleWindow(NOW)).not.toBe(throttleWindow(NOW + 61 * 1000));
  });
});

// ---------------------------------------------------------------------------
// Verificación de email
// ---------------------------------------------------------------------------
describe("requestEmailVerification", () => {
  // Un uid POR TEST, no uno compartido. Estos dos casos se distinguen solo por
  // `emailVerified`, asi que si el borrado del test anterior no propago a
  // tiempo, el segundo correria contra el usuario del primero y afirmaria algo
  // sobre un estado que no es el que sembro.
  const verifyId = (uid: string): string =>
    dedupeKey("email-verification", `${uid}_${throttleWindow(NOW)}`, uid);

  const uids = ["auth-mail-verify-pending", "auth-mail-verify-done"];

  afterEach(async () => {
    for (const uid of uids) {
      await purgeQueueFor(uid);
      await admin.auth(testApp).deleteUser(uid).catch(() => undefined);
    }
  });

  it("encola el mail para un usuario sin verificar", async () => {
    const uid = uids[0];
    await seedUser({
      uid,
      email: "verificar-pendiente@example.com",
      emailVerified: false,
    });

    await runRequestEmailVerification(testApp, uid, NOW);

    const doc = await readQueueDoc(verifyId(uid));
    expect(doc?.kind).toBe("email-verification");
    expect(String(doc?.params.actionLink)).toContain("oobCode=");
  });

  it("no encola nada si el email YA está verificado", async () => {
    const uid = uids[1];
    await seedUser({
      uid,
      email: "verificar-hecho@example.com",
      emailVerified: true,
    });

    await runRequestEmailVerification(testApp, uid, NOW);

    expect(await queueCountFor(uid)).toBe(0);
  });

  it("no tira para un uid inexistente", async () => {
    await expect(
      runRequestEmailVerification(testApp, "no-existe-este-uid", NOW),
    ).resolves.toEqual({ status: "ok" });
  });
});
