/**
 * Un alta POR MAIL nace con el consentimiento puesto, o no nace
 * (`altaPorMailTraeConsentimiento` en firestore.rules).
 *
 * La carrera, medida en producción (oct-2026): apenas
 * `createUserWithEmailAndPassword` vuelve, `perfilAseguradoProvider` dispara
 * un `createIfAbsent` (perfil vacío, sin consentimiento) MIENTRAS
 * `AuthService.signUpWithEmail` está en su `getOrCreate`. Si gana el
 * `createIfAbsent`, la escritura del registro —un `set` sin merge, con otro
 * `createdAt`— llega como UPDATE, el pin de `createdAt` la rechaza y el
 * registro borra la cuenta de Auth. O, si aterriza antes de la lectura del
 * `getOrCreate`, la cuenta queda creada sin consentimiento y sin error.
 *
 * La regla le saca la carrera al `createIfAbsent`: para una cuenta con
 * contraseña sin verificar, el create sin consentimiento se deniega, y el
 * único que puede crear el doc es el registro.
 *
 * Este archivo tiene que matchear `[-]rules\.test\.ts$` (package.json
 * `test:rules`) o no corre en CI.
 *
 * Correr contra el emulador (requiere Java 21):
 *   npm --prefix functions run test:rules:emulator
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  writeBatch,
  Timestamp,
  setLogLevel,
} from "firebase/firestore";

const PROJECT_ID = "treino-rules-test-alta-por-mail";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const UID = "athlete-uid";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

type Proveedor = "password" | "google.com" | "apple.com";

/** El token de una cuenta recién logueada con [proveedor]. */
const como = (proveedor: Proveedor, {verificado = false} = {}) =>
  testEnv
    .authenticatedContext(UID, {
      email: "a@example.com",
      email_verified: verificado,
      firebase: {sign_in_provider: proveedor},
    })
    .firestore();

/**
 * El `toJson()` de un perfil recién creado (`user_profile.g.dart`), sin la
 * clave `bornAt` (`_altaPayload`). Sin consentimiento: es lo que manda
 * `createIfAbsent`.
 */
function perfilVacio(createdAt: Timestamp) {
  return {
    uid: UID,
    email: "a@example.com",
    displayName: null,
    role: "athlete",
    createdAt,
    updatedAt: createdAt,
    gymId: null,
    bodyWeightKg: null,
    heightCm: null,
    gender: null,
    experienceLevel: null,
    avatarUrl: null,
    termsAcceptedAt: null,
    acceptedTermsVersion: null,
    acceptedPrivacyVersion: null,
    subscription: null,
    weightedLoad: null,
    trainerLocations: [],
    trainerGeohashes: [],
    trainerOffersOnline: false,
    acceptsInquiries: true,
    onboardingSeen: {},
  };
}

/** Lo que manda `getOrCreate` desde `signUpWithEmail`: con consentimiento. */
function perfilDelRegistro(createdAt: Timestamp) {
  return {
    ...perfilVacio(createdAt),
    termsAcceptedAt: createdAt,
    acceptedTermsVersion: 3,
    acceptedPrivacyVersion: 3,
  };
}

const publico = {
  uid: UID,
  displayName: null,
  displayNameLowercase: null,
  avatarUrl: null,
  gymId: null,
};

/** El batch de `createIfAbsent`, tal cual: merge en los dos docs. */
async function createIfAbsent(
  db: ReturnType<typeof como>,
  createdAt = Timestamp.now(),
) {
  const b = writeBatch(db);
  b.set(doc(db, "users", UID), perfilVacio(createdAt), {merge: true});
  b.set(doc(db, "userPublicProfiles", UID), publico, {merge: true});
  await b.commit();
}

/** El batch de `getOrCreate`: `set` SIN merge en `users`. */
async function registro(
  db: ReturnType<typeof como>,
  createdAt = Timestamp.now(),
) {
  const b = writeBatch(db);
  b.set(doc(db, "users", UID), perfilDelRegistro(createdAt));
  b.set(doc(db, "userPublicProfiles", UID), publico, {merge: true});
  await b.commit();
}

async function leer() {
  let users: Record<string, unknown> | undefined;
  let pub: Record<string, unknown> | undefined;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    users = (await getDoc(doc(ctx.firestore(), "users", UID))).data();
    pub = (await getDoc(doc(ctx.firestore(), "userPublicProfiles", UID)))
      .data();
  });
  return {users, pub};
}

describe("alta con contraseña sin verificar — el consentimiento es obligatorio", () => {
  it("createIfAbsent (sin consentimiento) → DENEGADO, y no deja ni el público", async () => {
    await assertFails(createIfAbsent(como("password")));

    const {users, pub} = await leer();
    expect(users).toBeUndefined();
    expect(pub).toBeUndefined();
  });

  it("el registro (con consentimiento) → permitido", async () => {
    await assertSucceeds(registro(como("password")));
  });

  it("consentimiento a medias (sin la versión de privacidad) → denegado", async () => {
    const db = como("password");
    const ahora = Timestamp.now();
    await assertFails(
      writeBatch(db)
        .set(doc(db, "users", UID), {
          ...perfilDelRegistro(ahora),
          acceptedPrivacyVersion: null,
        })
        .commit(),
    );
  });

  it("la carrera de producción: el createIfAbsent pierde y el registro crea el doc con consentimiento", async () => {
    const db = como("password");

    // Primero aterriza el createIfAbsent del alta…
    await assertFails(createIfAbsent(db));
    // …y el registro, que antes llegaba como UPDATE y lo rechazaba el pin de
    // `createdAt`, ahora es el create.
    await assertSucceeds(registro(db));

    const {users, pub} = await leer();
    expect(users?.termsAcceptedAt).toBeInstanceOf(Timestamp);
    expect(users?.acceptedTermsVersion).toBe(3);
    expect(pub?.uid).toBe(UID);

    // Y un createIfAbsent tardío sigue sin poder pisarlo.
    await assertFails(createIfAbsent(db));
  });
});

describe("las que NO cambian", () => {
  it("Google sin consentimiento → permitido (lo estampa el checkbox del alta)", async () => {
    await assertSucceeds(createIfAbsent(como("google.com", {verificado: true})));
  });

  it("Apple sin consentimiento → permitido", async () => {
    await assertSucceeds(createIfAbsent(como("apple.com", {verificado: true})));
  });

  it("Apple sin mail verificado (relay oculto) → permitido igual", async () => {
    await assertSucceeds(createIfAbsent(como("apple.com")));
  });

  it("backfill del login: cuenta con contraseña VERIFICADA y sin doc → permitido", async () => {
    await assertSucceeds(createIfAbsent(como("password", {verificado: true})));
  });
});
