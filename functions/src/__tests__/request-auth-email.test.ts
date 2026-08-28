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
  resetOutcomeFor,
  rewriteActionHost,
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

/** Siembra una cuenta cuyo unico proveedor es Google, sin password hash. */
async function seedFederatedUser(uid: string, email: string): Promise<void> {
  await admin.auth(testApp).deleteUser(uid).catch(() => undefined);
  await admin.auth(testApp).createUser({ uid, email });
  await admin.auth(testApp).updateUser(uid, {
    providerToLink: {
      providerId: "google.com",
      uid: `${uid}-google`,
      email,
    },
  });
  // `createUser` sin password deja providerData con solo el federado — pero se
  // verifica en vez de asumirlo, porque de eso depende todo el bloque.
  const u = await admin.auth(testApp).getUser(uid);
  const ids = u.providerData.map((x) => x.providerId);
  if (ids.includes("password")) {
    throw new Error(`seed roto: la cuenta quedo con password (${ids})`);
  }
}

// ---------------------------------------------------------------------------
// resetOutcomeFor — la decisión que el emulador NO puede validar
//
// Es una función pura y vive fuera del emulador a propósito. Ver el guardián
// del final de este archivo.
// ---------------------------------------------------------------------------
describe("resetOutcomeFor", () => {
  it.each([
    [["password"], "password-reset"],
    [["password", "google.com"], "password-reset"],
    [["google.com", "password"], "password-reset"],
    [["google.com"], "federated-signin-hint"],
    [["apple.com"], "federated-signin-hint"],
    [["google.com", "apple.com"], "federated-signin-hint"],
  ] as const)("%j → %s", (providers, expected) => {
    expect(resetOutcomeFor(providers)).toBe(expected);
  });

  // Una cuenta sin proveedores listados NO es federada, así que mandarle un
  // mail que dice "entrá con Google" sería peor que dejarla en el camino de
  // hoy — que en el peor caso falla en silencio, como ya lo hace.
  it("providerData vacío cae al camino de hoy, no al hint", () => {
    expect(resetOutcomeFor([])).toBe("password-reset");
  });

  // El discriminador es la PRESENCIA de `password`, no la ausencia de
  // federados. Un proveedor nuevo que Firebase agregue mañana cae solo del
  // lado correcto sin tocar esta función.
  it("un proveedor desconocido se trata como federado", () => {
    expect(resetOutcomeFor(["algo-que-no-existe.com"])).toBe(
      "federated-signin-hint",
    );
  });
});

// ---------------------------------------------------------------------------
// rewriteActionHost — el link lleva NUESTRO dominio
//
// Firebase tiene un ajuste para esto ("Customize action URL"), pero en este
// proyecto ese PATCH devuelve 400 EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED con un
// payload válido. Se resuelve en código, que además deja UNA sola fuente de
// verdad: si el host viviera en la consola Y acá, podrían discrepar y el código
// ganaría en silencio.
// ---------------------------------------------------------------------------
describe("rewriteActionHost", () => {
  const FIREBASE_LINK =
    "https://treino-dev.firebaseapp.com/__/auth/action" +
    "?mode=resetPassword&oobCode=ABC123&apiKey=XYZ&lang=es";

  it("cambia el host y deja el resto intacto", () => {
    const out = new URL(rewriteActionHost(FIREBASE_LINK));

    expect(out.host).toBe("auth.gettreino.com");
    expect(out.pathname).toBe("/__/auth/action");
    // El oobCode va firmado: si se tocara, el link se invalida.
    expect(out.searchParams.get("oobCode")).toBe("ABC123");
    expect(out.searchParams.get("apiKey")).toBe("XYZ");
    expect(out.searchParams.get("mode")).toBe("resetPassword");
    expect(out.searchParams.get("lang")).toBe("es");
  });

  it("es idempotente: aplicarlo dos veces da lo mismo", () => {
    const once = rewriteActionHost(FIREBASE_LINK);
    expect(rewriteActionHost(once)).toBe(once);
  });

  // Si algún día la consola SÍ deja fijar el action URL, el link ya viene con
  // el host correcto y esto no hace nada. Convivir sin pisarse es el punto.
  it("no rompe un link que ya viene con nuestro dominio", () => {
    const yaNuestro =
      "https://auth.gettreino.com/__/auth/action?mode=verifyEmail&oobCode=Z";
    expect(rewriteActionHost(yaNuestro)).toBe(yaNuestro);
  });

  it("fuerza https aunque venga en http", () => {
    const inseguro = "http://treino-dev.firebaseapp.com/__/auth/action?oobCode=Q";
    expect(rewriteActionHost(inseguro)).toContain("https://auth.gettreino.com");
    expect(rewriteActionHost(inseguro)).not.toContain("http://");
  });

  // Conservador a propósito: un link de recuperación roto es peor que uno feo,
  // porque el que lo recibe ya no puede entrar a su cuenta.
  it("deja intacto lo que no reconoce", () => {
    for (const raro of [
      "no-es-una-url",
      "",
      "https://treino-dev.firebaseapp.com/otra/cosa",
      "https://ejemplo.test/",
    ]) {
      expect(rewriteActionHost(raro)).toBe(raro);
    }
  });
});

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

    // OJO: acá NO se puede verificar el host reescrito. El emulador de Auth
    // devuelve el link en `/emulator/action`, no en el namespace reservado
    // `/__/auth/action`, así que `rewriteActionHost` lo deja intacto — y eso es
    // lo correcto: reescribirlo apuntaría al dominio real y rompería el testing
    // local. La reescritura se cubre en el describe `rewriteActionHost`, que es
    // puro y no depende del entorno.
    expect(String(doc?.params.actionLink)).toContain("/emulator/action");
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

// ---------------------------------------------------------------------------
// La rama federada, extremo a extremo contra el emulador
// ---------------------------------------------------------------------------
describe("cuenta sin contraseña: manda el hint, no un link de reseteo", () => {
  const uid = "auth-mail-federada";
  const email = "federada@example.com";
  const hintId = dedupeKey(
    "federated-signin-hint",
    `${uid}_${throttleWindow(NOW)}`,
    uid,
  );

  beforeEach(() => seedFederatedUser(uid, email));

  afterEach(async () => {
    await purgeQueueFor(uid);
    await admin.auth(testApp).deleteUser(uid).catch(() => undefined);
  });

  it("encola `federated-signin-hint` y NO `password-reset`", async () => {
    await runRequestPasswordReset(testApp, email, NOW);

    const doc = await readQueueDoc(hintId);
    expect(doc?.kind).toBe("federated-signin-hint");
    expect(await queueCountFor(uid)).toBe(1);
  });

  // Sin contraseña que restablecer no hay link que mandar. Si esto se rompe,
  // le estariamos mandando a un usuario de Google un link que no le sirve.
  it("el doc NO lleva actionLink", async () => {
    await runRequestPasswordReset(testApp, email, NOW);

    const doc = await readQueueDoc(hintId);
    expect(doc?.params?.actionLink).toBeUndefined();
  });

  it("es transaccional: no lleva prefKey", async () => {
    await runRequestPasswordReset(testApp, email, NOW);
    expect((await readQueueDoc(hintId))?.prefKey).toBeUndefined();
  });

  // REQ-AUTH-011 sobre la rama nueva: la respuesta tiene que ser identica a la
  // de una cuenta con contraseña y a la de una que no existe. Si esta rama
  // devolviera algo distinto, seria un oraculo de proveedores.
  it("devuelve exactamente la misma respuesta que las otras dos ramas", async () => {
    const federada = await runRequestPasswordReset(testApp, email, NOW);
    const inexistente = await runRequestPasswordReset(
      testApp,
      "no-existe-nadie@example.com",
      NOW,
    );

    expect(federada).toEqual({ status: "ok" });
    expect(federada).toEqual(inexistente);
  });
});

// ---------------------------------------------------------------------------
// GUARDIAN — el emulador MIENTE sobre este caso
//
// No prueba nuestro codigo: prueba una propiedad del EMULADOR, y existe para
// que nadie borre `resetOutcomeFor` pensando que sobra.
//
// El emulador de Auth no gatea por proveedor. En su fuente
// (firebase-tools, `emulator/auth/operations.js`), la rama PASSWORD_RESET solo
// hace `getUserByEmail` y afirma `EMAIL_NOT_FOUND` — no mira `providerUserInfo`
// ni `passwordHash`. Asi que sobre una cuenta solo-Google genera link igual.
//
// Corolario: cualquier test que "compruebe" contra el emulador que el reseteo
// funciona para cuentas federadas da verde SIN HABER MEDIDO NADA. Por eso la
// decision vive en una funcion pura y no en un assert de integracion.
// ---------------------------------------------------------------------------
describe("el emulador no es oráculo para el caso federado", () => {
  const uid = "auth-mail-emu-miente";
  const email = "emu-miente@example.com";

  beforeEach(() => seedFederatedUser(uid, email));
  afterEach(() => admin.auth(testApp).deleteUser(uid).catch(() => undefined));

  it("genera link para una cuenta SIN contraseña — por eso no alcanza", async () => {
    const link = await admin.auth(testApp).generatePasswordResetLink(email);

    // Si esto algun dia se pone ROJO, es una buena noticia: el emulador
    // empezo a gatear por proveedor y se volvio fiel. Recien ahi tendria
    // sentido discutir si `resetOutcomeFor` sigue haciendo falta.
    expect(link).toContain("oobCode=");
  });
});
