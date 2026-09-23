/**
 * Un `createIfAbsent` que llega TARDE no puede pisar un alta ya guardada.
 *
 * `UserRepository.createIfAbsent` lee y después escribe: si `users/{uid}` no
 * existe, manda en un batch el `toJson()` de un perfil VACÍO (displayName,
 * gymId, termsAcceptedAt… en null) más el subset público. Desde sep-2026 lo
 * llaman el login, el submit del alta Y un reintento que corre durante el
 * alta (`perfilAseguradoProvider`). Un intento que leyó «no existe» justo
 * antes del submit puede escribir DESPUÉS de él.
 *
 * Lo que lo frena es una sola cosa: el pin de `createdAt` en el update de
 * `users/{uid}`. Cada intento trae su propio `createdAt`, así que sobre un doc
 * ya creado el batch es un UPDATE que cambia `createdAt`, se rechaza, y cae
 * entero (el público incluido). Medido contra el emulador antes de apoyarse en
 * esto: con el MISMO `createdAt` que el doc existente, el batch PASABA y dejaba
 * displayName, gymId y termsAcceptedAt en null.
 *
 * Si este archivo se pone rojo porque alguien aflojó el pin de `createdAt`, el
 * reintento del alta pasa a poder borrar perfiles recién creados. No lo
 * arreglen acá: hagan `createIfAbsent` atómico primero.
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
  setDoc,
  writeBatch,
  Timestamp,
  setLogLevel,
} from "firebase/firestore";

const PROJECT_ID = "treino-rules-test-alta-no-se-pisa";
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

const asUser = (uid: string) => testEnv.authenticatedContext(uid).firestore();

/**
 * Lo que manda `createIfAbsent`: el `toJson()` de un perfil recién creado
 * (`user_profile.g.dart`), sin la clave `bornAt` (`_altaPayload`).
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

/** El batch de `createIfAbsent`, tal cual. */
async function createIfAbsentTardio(createdAt: Timestamp) {
  const db = asUser(UID);
  const b = writeBatch(db);
  b.set(doc(db, "users", UID), perfilVacio(createdAt), { merge: true });
  b.set(
    doc(db, "userPublicProfiles", UID),
    {
      uid: UID,
      displayName: null,
      displayNameLowercase: null,
      avatarUrl: null,
      gymId: null,
    },
    { merge: true },
  );
  await b.commit();
}

describe("createIfAbsent tardío — no pisa el alta", () => {
  // Control: sin él, el assertFails de abajo podría estar midiendo un batch
  // roto en vez del pin.
  it("sin doc previo → permitido (es el alta normal)", async () => {
    await assertSucceeds(createIfAbsentTardio(Timestamp.now()));
  });

  it("con el alta ya guardada → RECHAZADO, y el perfil queda intacto", async () => {
    const alta = Timestamp.fromDate(new Date(Date.now() - 60_000));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", UID), {
        ...perfilVacio(alta),
        displayName: "carlos",
        gymId: "ChIJ_gym",
        termsAcceptedAt: alta,
        acceptedTermsVersion: 3,
      });
      await setDoc(doc(ctx.firestore(), "userPublicProfiles", UID), {
        uid: UID,
        displayName: "carlos",
        displayNameLowercase: "carlos",
        gymId: "ChIJ_gym",
        gymName: "Gym",
      });
    });

    await assertFails(createIfAbsentTardio(Timestamp.now()));

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const users = (await getDoc(doc(ctx.firestore(), "users", UID))).data();
      const pub = (
        await getDoc(doc(ctx.firestore(), "userPublicProfiles", UID))
      ).data();
      expect(users?.displayName).toBe("carlos");
      expect(users?.gymId).toBe("ChIJ_gym");
      expect(users?.termsAcceptedAt).toBeDefined();
      expect(users?.termsAcceptedAt).not.toBeNull();
      expect(pub?.displayName).toBe("carlos");
    });
  });
});
