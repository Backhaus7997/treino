/**
 * delete-account-alta-cancelada.test.ts — «Cancelar cuenta» del alta no deja
 * nada atras.
 *
 * EMULADOR (Firestore + Auth + Storage). Corre como el job `functions-test`:
 *
 *   firebase emulators:exec --only firestore,auth,storage --project treino-dev \
 *     "npm --prefix functions test -- --runInBand delete-account-alta-cancelada"
 *
 * Cancelar el alta en el paso 0 de ProfileSetup va por `deleteAccount`
 * (`AuthService.cancelOnboarding`). Antes iba por `UserRepository.delete`, que
 * tira siempre: el cliente se tragaba el error, borraba solo la cuenta de Auth,
 * y `users/{uid}` + `userPublicProfiles/{uid}` quedaban para siempre, con el
 * mail de alguien que pidio no tener cuenta.
 *
 * Este archivo mide ESE punto de partida —lo que deja el login antes de
 * ProfileSetup— contra la cascada: que no quede ni el perfil, ni el publico,
 * ni el avatar, ni la cuenta de Auth.
 */

// `??=` y no `=`: si el 8080 lo tiene el emulador de otra sesion, se corre con
// puertos alternos y `emulators:exec` los exporta; pisarlos mandaria este test
// al emulador ajeno.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
process.env.GCLOUD_PROJECT ??= "treino-dev";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import type { CallableRequest } from "firebase-functions/v2/https";
import { wrapV2 } from "firebase-functions-test/lib/v2";

import { deleteAccountHandler } from "../delete-account";
import { DeleteAccountRequest, DeleteAccountResponse } from "../types";

const UID = "alta-cancelada";

let app: App;

beforeAll(() => {
  // La app DEFAULT a proposito: el handler la resuelve con `getApp()`.
  app = initializeApp({
    projectId: "treino-dev",
    storageBucket: "treino-dev.appspot.com",
  });
});

afterAll(async () => {
  await deleteApp(app);
});

const doc = (coleccion: string) =>
  getFirestore(app).collection(coleccion).doc(UID);

const avatar = () => getStorage(app).bucket().file(`avatars/${UID}.jpg`);

const hayCuentaDeAuth = () =>
  getAuth(app)
    .getUser(UID)
    .then(
      () => true,
      () => false,
    );

/**
 * Lo que deja el login antes de ProfileSetup: la cuenta de Auth, el dual-write
 * de `createIfAbsent` con el token de FCM que el arranque ya pudo escribir, y
 * el avatar de un submit anterior que subio la foto y despues fallo.
 */
async function sembrarAlta(): Promise<void> {
  await getAuth(app).createUser({ uid: UID, email: `${UID}@ejemplo.com` });
  await doc("users").set({
    uid: UID,
    email: `${UID}@ejemplo.com`,
    displayName: null,
    role: "athlete",
    createdAt: new Date(),
    updatedAt: new Date(),
    fcmTokens: ["token-del-arranque"],
  });
  await doc("userPublicProfiles").set({
    uid: UID,
    displayName: null,
    displayNameLowercase: null,
    avatarUrl: null,
    gymId: null,
  });
  await avatar().save(Buffer.from("foto"), { contentType: "image/jpeg" });
}

async function limpiar(): Promise<void> {
  await getAuth(app)
    .deleteUser(UID)
    .catch(() => undefined);
  await getFirestore(app).recursiveDelete(doc("users"));
  await doc("userPublicProfiles").delete();
  await doc("audit_log").delete();
  await avatar()
    .delete()
    .catch(() => undefined);
}

/** Lo que manda `AccountDeletionService.call`: el uid propio, en el body y en el token. */
function pedido(): CallableRequest<DeleteAccountRequest> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const token = { uid: UID, token: { firebase: { sign_in_provider: "google.com" } } } as any;
  return {
    data: { uid: UID },
    auth: token,
    rawRequest: {} as CallableRequest["rawRequest"],
    instanceIdToken: undefined,
    acceptsStreaming: false,
    app: undefined,
  };
}

describe("cancelar el alta por deleteAccount no deja nada", () => {
  beforeEach(sembrarAlta);
  afterEach(limpiar);

  it("se van users, userPublicProfiles, el avatar y la cuenta de Auth", async () => {
    // El fixture tiene que dejar lo que deja el login: sin esto, un borrado
    // que no borra nada tambien «terminaria sin documentos».
    expect((await doc("users").get()).exists).toBe(true);
    expect((await doc("userPublicProfiles").get()).exists).toBe(true);
    expect((await avatar().exists())[0]).toBe(true);
    expect(await hayCuentaDeAuth()).toBe(true);

    const respuesta = (await wrapV2(deleteAccountHandler)(
      pedido(),
    )) as DeleteAccountResponse;

    // `users-auth` es la señal con la que el cliente decide que la cuenta se
    // fue y cierra la sesion; sin ella, reintenta.
    expect(respuesta.errors).toEqual([]);
    expect(respuesta.deletedCollections).toContain("users-auth");
    expect((await doc("users").get()).exists).toBe(false);
    expect((await doc("userPublicProfiles").get()).exists).toBe(false);
    expect((await avatar().exists())[0]).toBe(false);
    expect(await hayCuentaDeAuth()).toBe(false);
  });
});
