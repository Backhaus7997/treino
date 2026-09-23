/**
 * cancel-onboarding.test.ts — «Cancelar cuenta» del alta no deja nada atras.
 *
 * EMULADOR (Firestore + Storage). Corre como el job `functions-test` del CI:
 *
 *   firebase emulators:exec --only firestore,auth,storage --project treino-dev \
 *     "npm --prefix functions test -- --runInBand cancel-onboarding"
 *
 * Lo que protege:
 *
 *   1. Que cancelar borre `users/{uid}`, `userPublicProfiles/{uid}` y el
 *      avatar. Antes quedaban para siempre, con el mail de alguien que pidio no
 *      tener cuenta: el cliente llamaba a `UserRepository.delete`, que tira
 *      siempre, y se tragaba el error.
 *   2. Que SOLO actue sobre un alta sin completar. Con `displayName` puesto o
 *      con `role: trainer` rechaza y no toca nada: se llega con un dialogo de
 *      confirmacion, no con la re-autenticacion de `deleteAccount`.
 *   3. Que el uid salga del token y no del body.
 */

// `??=` y no `=`: si el 8080 lo tiene el emulador de otra sesion, se corre con
// puertos alternos y `emulators:exec` los exporta; pisarlos mandaria estos
// tests al emulador ajeno.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
process.env.GCLOUD_PROJECT ??= "treino-dev";

// Passthrough, como en delete-account.smoke.test.ts: por default borra de
// verdad contra el emulador, y un test puede hacerlo fallar una vez para
// simular Storage caido.
jest.mock("../cascade/storage", () => {
  const actual = jest.requireActual("../cascade/storage");
  return { ...actual, deleteAvatar: jest.fn(actual.deleteAvatar) };
});

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import type { CallableRequest } from "firebase-functions/v2/https";
import { wrapV2 } from "firebase-functions-test/lib/v2";

import * as storageCascade from "../cascade/storage";
import {
  cancelOnboarding,
  runCancelOnboarding,
} from "../profile/cancel-onboarding";

const USERS = "users";
const PUBLIC = "userPublicProfiles";

let app: App;

beforeAll(() => {
  // La app DEFAULT a proposito: el callable la resuelve con `getApp()`, asi
  // que los tests del handler y los de la logica miran el mismo emulador.
  app = initializeApp({
    projectId: "treino-dev",
    storageBucket: "treino-dev.appspot.com",
  });
});

afterAll(async () => {
  await deleteApp(app);
});

/**
 * Lo que deja el login antes de ProfileSetup: el dual-write de
 * `createIfAbsent`, con el token de FCM que el arranque de la app ya pudo
 * escribir.
 */
async function sembrarAlta(
  uid: string,
  extra: Record<string, unknown> = {},
): Promise<void> {
  const db = getFirestore(app);
  await db
    .collection(USERS)
    .doc(uid)
    .set({
      uid,
      email: `${uid}@ejemplo.com`,
      displayName: null,
      role: "athlete",
      createdAt: new Date(),
      updatedAt: new Date(),
      fcmTokens: ["token-del-arranque"],
      ...extra,
    });
  await db.collection(PUBLIC).doc(uid).set({
    uid,
    displayName: null,
    displayNameLowercase: null,
    avatarUrl: null,
    gymId: null,
  });
}

async function existe(coleccion: string, uid: string): Promise<boolean> {
  return (await getFirestore(app).collection(coleccion).doc(uid).get()).exists;
}

const avatar = (uid: string) =>
  getStorage(app).bucket().file(`avatars/${uid}.jpg`);

async function limpiar(uid: string): Promise<void> {
  const db = getFirestore(app);
  await db.recursiveDelete(db.collection(USERS).doc(uid));
  await db.collection(PUBLIC).doc(uid).delete();
  await avatar(uid)
    .delete()
    .catch(() => undefined);
}

function pedido(uidDelToken: string | null, data: unknown = {}): CallableRequest {
  // Un token de verdad trae mucho mas; al callable solo le importa el uid.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const token = { uid: uidDelToken, token: {} } as any;
  return {
    data,
    auth: uidDelToken ? token : undefined,
    rawRequest: {} as CallableRequest["rawRequest"],
    instanceIdToken: undefined,
    acceptsStreaming: false,
    app: undefined,
  };
}

describe("cancelar un alta sin completar no deja nada", () => {
  const uid = "cancel-onboarding-alta";

  beforeEach(() => sembrarAlta(uid));
  afterEach(() => limpiar(uid));

  it("borra users/{uid} y userPublicProfiles/{uid}", async () => {
    // El fixture tiene que dejar lo que deja el login: sin esto, un borrado
    // que no borra nada tambien «terminaria sin documentos».
    expect(await existe(USERS, uid)).toBe(true);
    expect(await existe(PUBLIC, uid)).toBe(true);

    await runCancelOnboarding(app, uid);

    expect(await existe(USERS, uid)).toBe(false);
    expect(await existe(PUBLIC, uid)).toBe(false);
  });

  it("borra el avatar que dejo un submit anterior que fallo", async () => {
    await avatar(uid).save(Buffer.from("foto"), { contentType: "image/jpeg" });
    expect((await avatar(uid).exists())[0]).toBe(true);

    await runCancelOnboarding(app, uid);

    expect((await avatar(uid).exists())[0]).toBe(false);
  });

  it("es idempotente: el reintento despues de un Auth que fallo no rompe", async () => {
    await runCancelOnboarding(app, uid);

    await expect(runCancelOnboarding(app, uid)).resolves.toBeUndefined();
    expect(await existe(USERS, uid)).toBe(false);
  });

  it("si Storage falla, igual borra los docs y lo avisa con internal", async () => {
    // Tragarse el error aca es el mismo bug que este callable cierra: el
    // cliente reporta el fallo como non-fatal solo si le llega.
    jest
      .mocked(storageCascade.deleteAvatar)
      .mockRejectedValueOnce(new Error("storage caido"));

    await expect(runCancelOnboarding(app, uid)).rejects.toMatchObject({
      code: "internal",
    });

    expect(await existe(USERS, uid)).toBe(false);
    expect(await existe(PUBLIC, uid)).toBe(false);
  });
});

describe("solo actua sobre un alta sin completar", () => {
  const uid = "cancel-onboarding-guard";

  afterEach(() => limpiar(uid));

  it("con el alta completa (displayName puesto) rechaza y no borra nada", async () => {
    await sembrarAlta(uid, { displayName: "Ana" });

    await expect(runCancelOnboarding(app, uid)).rejects.toMatchObject({
      code: "failed-precondition",
    });

    expect(await existe(USERS, uid)).toBe(true);
    expect(await existe(PUBLIC, uid)).toBe(true);
  });

  it("a un entrenador lo rechaza y no le borra nada", async () => {
    await sembrarAlta(uid, { role: "trainer" });

    await expect(runCancelOnboarding(app, uid)).rejects.toMatchObject({
      code: "permission-denied",
    });

    expect(await existe(USERS, uid)).toBe(true);
    expect(await existe(PUBLIC, uid)).toBe(true);
  });
});

describe("el callable", () => {
  const llamar = wrapV2(cancelOnboarding);
  const propio = "cancel-onboarding-propio";
  const ajeno = "cancel-onboarding-ajeno";

  afterEach(async () => {
    await limpiar(propio);
    await limpiar(ajeno);
  });

  it("sin sesion rechaza con unauthenticated", async () => {
    await expect(llamar(pedido(null))).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });

  it("borra lo del uid del TOKEN aunque el body nombre a otro", async () => {
    await sembrarAlta(propio);
    await sembrarAlta(ajeno);

    await expect(llamar(pedido(propio, { uid: ajeno }))).resolves.toEqual({
      ok: true,
    });

    expect(await existe(USERS, propio)).toBe(false);
    expect(await existe(PUBLIC, propio)).toBe(false);
    expect(await existe(USERS, ajeno)).toBe(true);
    expect(await existe(PUBLIC, ajeno)).toBe(true);
  });
});
