/**
 * Tests de `mintWatchCredential` — la Cloud Function que le da credencial
 * propia al companion de Apple Watch.
 *
 * Change `watch-standalone-client`, fase F1.
 *
 * POR QUE EXISTE ESTA FUNCION
 * ---------------------------
 * El plan original era que el telefono le pasara SU refresh token al reloj.
 * No se puede: `User.refreshToken` de firebase_auth es vacio en nativo. La
 * documentacion del platform interface lo dice textual — "This property will
 * be an empty string for native platforms (android, iOS & macOS)".
 *
 * Entonces el reloj obtiene credencial PROPIA: esta funcion mintea un custom
 * token, el telefono se lo pasa por WatchConnectivity, y el reloj lo canjea
 * por su idToken + refreshToken. De ahi en adelante renueva solo, sin
 * telefono y sin SDK de Firebase.
 *
 * Ventaja sobre el diseño original: la credencial del reloj es independiente
 * de la del telefono — revocable por separado, y el telefono nunca expone la
 * suya.
 *
 * LA PROPIEDAD DE SEGURIDAD QUE IMPORTA
 * -------------------------------------
 * La funcion mintea SOLO para `request.auth.uid`. No acepta un uid por
 * parametro — si lo aceptara, cualquier usuario autenticado podria fabricarse
 * credenciales de cualquier otro. El test "ignora un uid inyectado en data"
 * es el que protege eso y no se toca sin entender por que esta.
 *
 * Requiere los emuladores de Firestore (8080) y Auth (9099).
 */

import * as admin from "firebase-admin";

process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: admin.app.App;

beforeAll(() => {
  testApp = admin.initializeApp(
    { projectId: "treino-dev" },
    "mint-watch-credential-test",
  );
});

afterAll(async () => {
  await testApp.delete();
});

import { mintWatchCredential, runMintWatchCredential } from "../mint-watch-credential";

import firebaseFunctionsTest from "firebase-functions-test";
type FftInstance = {
  wrap: (fn: unknown) => (data: unknown, ctx?: unknown) => Promise<unknown>;
  cleanup: () => void;
};
const fft = (firebaseFunctionsTest as unknown as () => FftInstance)();
const wrapped = fft.wrap(mintWatchCredential);

const AUTH_HOST = "http://127.0.0.1:9099";

/**
 * Lo que hace el reloj al recibir el custom token: lo canjea por credenciales
 * propias. Es tambien la unica forma honesta de verificar que el token
 * minteado SIRVE — comprobar que es un string no prueba nada.
 */
async function exchangeCustomToken(
  customToken: string,
): Promise<{idToken?: string; refreshToken?: string; status: number}> {
  const res = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-api-key`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({token: customToken, returnSecureToken: true}),
    },
  );
  const body = (await res.json()) as {idToken?: string; refreshToken?: string};
  return {...body, status: res.status};
}

/** Renueva la credencial como lo haria el reloj: HTTP puro, sin SDK. */
async function refreshIdToken(
  refreshToken: string,
): Promise<{userId: string; idToken: string}> {
  const res = await fetch(
    `${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`,
    {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(refreshToken)}`,
    },
  );
  const body = (await res.json()) as {user_id: string; id_token: string};
  return {userId: body.user_id, idToken: body.id_token};
}

describe("mintWatchCredential — estructura", () => {
  it("exporta el callable y el handler puro", () => {
    expect(typeof mintWatchCredential).toBe("function");
    expect(typeof runMintWatchCredential).toBe("function");
  });

  it("esta exportado desde index.ts", async () => {
    const index = await import("../index");
    expect(index).toHaveProperty("mintWatchCredential");
  });
});

describe("mintWatchCredential — la credencial sirve de verdad", () => {
  const callerUid = "atleta-con-reloj";

  it("mintea un token que el reloj puede canjear por credenciales propias", async () => {
    const {customToken} = await runMintWatchCredential(testApp, callerUid);

    const exchanged = await exchangeCustomToken(customToken);

    expect(exchanged.status).toBe(200);
    expect(exchanged.idToken).toBeTruthy();
    // El refreshToken es TODO el punto: sin el, el reloj queda muerto en una
    // hora y deja de ser autonomo.
    expect(exchanged.refreshToken).toBeTruthy();
  });

  it("la credencial canjeada pertenece al usuario que llamo, y renueva sola", async () => {
    const {customToken} = await runMintWatchCredential(testApp, callerUid);
    const exchanged = await exchangeCustomToken(customToken);

    const refreshed = await refreshIdToken(exchanged.refreshToken!);

    // El reloj termina siendo el MISMO usuario que el telefono, no uno nuevo.
    expect(refreshed.userId).toBe(callerUid);
    expect(refreshed.idToken).toBeTruthy();
  });
});

describe("mintWatchCredential — seguridad", () => {
  it("rechaza a un llamador sin autenticar", async () => {
    await expect(wrapped({}, {})).rejects.toThrow(/unauthenticated|Authentication/i);
  });

  // ESTE ES EL TEST QUE IMPORTA. Si la funcion aceptara un uid por parametro,
  // cualquier usuario autenticado podria mintearse credenciales de cualquier
  // otro y leer/escribir su historial entero.
  it("ignora un uid inyectado en data: mintea solo para el caller", async () => {
    const victimaUid = "victima-que-no-autorizo-nada";
    const atacanteUid = "atacante";

    // Callable v2: `wrap` recibe UN objeto request, no (data, context).
    const result = (await wrapped({
      data: {uid: victimaUid, userId: victimaUid, targetUid: victimaUid},
      auth: {uid: atacanteUid},
    })) as {customToken: string};

    const exchanged = await exchangeCustomToken(result.customToken);
    const refreshed = await refreshIdToken(exchanged.refreshToken!);

    expect(refreshed.userId).toBe(atacanteUid);
    expect(refreshed.userId).not.toBe(victimaUid);
  });

  it("el handler puro rechaza un callerId vacio", async () => {
    await expect(runMintWatchCredential(testApp, "")).rejects.toThrow();
  });
});
