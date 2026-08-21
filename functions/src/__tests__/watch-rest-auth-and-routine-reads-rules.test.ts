/**
 * Tests de la cadena de credencial y de lectura de rutinas del reloj
 * (change `watch-standalone-client`, fase F1).
 *
 * POR QUE ESTE TEST EXISTE
 * ------------------------
 * F0 probó que las Security Rules cubren las ESCRITURAS REST del reloj
 * (ver `watch-rest-session-writes-rules.test.ts`). F1 agrega las dos piezas
 * que faltan para que el reloj sea autónomo:
 *
 * 1. Que pueda RENOVAR su credencial sin el SDK de Firebase. Firebase en
 *    watchOS es community-supported y Firestore ni siquiera figura entre sus
 *    productos soportados, así que depender del SDK era un riesgo. Este test
 *    demuestra que alcanza con HTTP: el teléfono le pasa el refresh token una
 *    vez (Locked Decision #2) y el reloj lo canjea por ID tokens frescos
 *    contra `securetoken.googleapis.com` por su cuenta, para siempre.
 *
 *    Consecuencia de diseño: **el target watchOS no necesita NINGUNA
 *    dependencia de Firebase**. Solo red.
 *
 * 2. Que pueda LEER la rutina del atleta, y que las rules discriminen quién
 *    puede ver qué — una rutina privada es legible por su atleta asignado
 *    pero no por un tercero.
 *
 * POR QUE HTTP CRUDO Y NO @firebase/rules-unit-testing
 * ----------------------------------------------------
 * Esa librería ejercita las rules a través del SDK de Firestore, que no
 * recorre el camino REST. Acá el riesgo a cubrir es específicamente ese
 * camino, que es el único que el reloj va a poder usar.
 *
 * El seed usa `Authorization: Bearer owner`, el superusuario del emulador,
 * porque crear una rutina respetando las rules exige un `source`/`assignedBy`
 * de PF o el flujo self-authored — ruido que no aporta a lo que se prueba acá.
 *
 * Requiere los emuladores de Firestore (8080) y Auth (9099).
 */

// Este archivo es un MODULO, no un script.
//
// Sin un `import`/`export` de nivel superior, TypeScript lo trata como script y
// mete sus `const` de arriba en el scope GLOBAL. Estos tests del reloj declaran
// las mismas cuatro constantes de emulador —PROJECT_ID, AUTH_HOST,
// FIRESTORE_HOST, DOCS— y una `interface EmulatorUser`, asi que chocaban entre
// si: "Cannot redeclare block-scoped variable".
//
// Estuvo roto desde el 2026-08-04 y no lo vio nadie porque la rama del
// companion nunca se pusheo: CI no corrio sobre ella ni una vez. Lo encontro el
// primer PR.
//
// Todos los demas tests de `functions/src/__tests__/` son modulos por tener
// imports propios; estos dos hacen los pedidos con `fetch` global y no
// importaban nada.
export {};

const PROJECT_ID =
  process.env.GCLOUD_PROJECT ?? process.env.FIREBASE_PROJECT ?? "treino-dev";

const AUTH_HOST = "http://127.0.0.1:9099";
const FIRESTORE_HOST = "http://127.0.0.1:8080";
const DOCS = `${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

interface EmulatorUser {
  idToken: string;
  refreshToken: string;
  uid: string;
}

async function signUpUser(label: string): Promise<EmulatorUser> {
  const res = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        email: `watch-f1-${label}-${Date.now()}@treino.test`,
        password: "Emulator1234!",
        returnSecureToken: true,
      }),
    },
  );
  if (!res.ok) {
    throw new Error(
      `El emulador de Auth rechazo el signUp (${res.status}). ` +
      "¿Esta levantado en 9099?",
    );
  }
  const body = (await res.json()) as {
    idToken: string;
    refreshToken: string;
    localId: string;
  };
  return {
    idToken: body.idToken,
    refreshToken: body.refreshToken,
    uid: body.localId,
  };
}

/**
 * Lo que hace el reloj cuando su ID token vence: canjea el refresh token que
 * el teléfono le entregó una sola vez por uno nuevo. Sin SDK, solo HTTP.
 */
async function refreshIdToken(
  refreshToken: string,
): Promise<{idToken: string; uid: string; expiresIn: string}> {
  const res = await fetch(
    `${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`,
    {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(refreshToken)}`,
    },
  );
  if (!res.ok) {
    throw new Error(`El refresh de token fallo (${res.status}).`);
  }
  const body = (await res.json()) as {
    id_token: string;
    user_id: string;
    expires_in: string;
  };
  return {idToken: body.id_token, uid: body.user_id, expiresIn: body.expires_in};
}

/** Siembra un documento saltando las rules, con el superusuario del emulador. */
async function seedDoc(documentPath: string, fields: object): Promise<void> {
  const res = await fetch(`${DOCS}/${documentPath}`, {
    method: "PATCH",
    headers: {
      "Authorization": "Bearer owner",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(fields),
  });
  if (!res.ok) {
    throw new Error(`El seed de ${documentPath} fallo (${res.status}).`);
  }
}

/** GET sobre un documento. Devuelve el status crudo: 200 pasa, 403 deniega. */
async function restRead(
  documentPath: string,
  idToken?: string,
): Promise<number> {
  const headers: Record<string, string> = {};
  if (idToken !== undefined) headers["Authorization"] = `Bearer ${idToken}`;
  const res = await fetch(`${DOCS}/${documentPath}`, {method: "GET", headers});
  return res.status;
}

async function restWrite(
  documentPath: string,
  fields: object,
  idToken: string,
): Promise<number> {
  const res = await fetch(`${DOCS}/${documentPath}`, {
    method: "PATCH",
    headers: {
      "Authorization": `Bearer ${idToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(fields),
  });
  return res.status;
}

describe("watch credential refresh — sin SDK de Firebase", () => {
  let athlete: EmulatorUser;

  beforeAll(async () => {
    athlete = await signUpUser("refresh");
  });

  it("canjea el refresh token por un ID token fresco usando solo HTTP", async () => {
    const refreshed = await refreshIdToken(athlete.refreshToken);

    expect(refreshed.idToken).toBeTruthy();
    // El token renovado pertenece al MISMO usuario: el reloj no cambia de
    // identidad al renovar.
    expect(refreshed.uid).toBe(athlete.uid);
    expect(Number(refreshed.expiresIn)).toBeGreaterThan(0);
  });

  it("el token renovado sirve para escribir en Firestore", async () => {
    const refreshed = await refreshIdToken(athlete.refreshToken);

    const status = await restWrite(
      `users/${athlete.uid}/sessions/watch-after-refresh`,
      {fields: {routineId: {stringValue: "routine-1"}}},
      refreshed.idToken,
    );

    expect(status).toBe(200);
  });

  it("un refresh token invalido no otorga credencial", async () => {
    await expect(refreshIdToken("basura-que-no-es-un-refresh-token"))
      .rejects.toThrow();
  });
});

describe("watch routine reads — firestore.rules", () => {
  let athlete: EmulatorUser;
  let stranger: EmulatorUser;
  let privatePath: string;

  const publicPath = "routines/watch-f1-public-routine";

  beforeAll(async () => {
    athlete = await signUpUser("reader");
    stranger = await signUpUser("stranger");
    privatePath = `routines/watch-f1-private-${athlete.uid}`;

    await seedDoc(privatePath, {
      fields: {
        name: {stringValue: "Push A"},
        visibility: {stringValue: "private"},
        assignedTo: {stringValue: athlete.uid},
        source: {stringValue: "trainer-assigned"},
      },
    });
    await seedDoc(publicPath, {
      fields: {
        name: {stringValue: "Catalogo"},
        visibility: {stringValue: "public"},
      },
    });
  });

  it("el atleta asignado lee su rutina privada", async () => {
    expect(await restRead(privatePath, athlete.idToken)).toBe(200);
  });

  it("un tercero NO lee la rutina privada de otro", async () => {
    expect(await restRead(privatePath, stranger.idToken)).toBe(403);
  });

  it("sin token no se lee ninguna rutina", async () => {
    expect(await restRead(privatePath)).toBe(403);
  });

  it("cualquier usuario autenticado lee una rutina publica", async () => {
    expect(await restRead(publicPath, stranger.idToken)).toBe(200);
  });

  // Comportamiento deliberado de firestore.rules, no un accidente: el guard
  // `resource == null` hace que un doc INEXISTENTE devuelva "no existe" en vez
  // de "prohibido". Sin ese short-circuit, leer una rutina borrada tiraba
  // excepcion y dejaba en blanco los radares de distribucion muscular.
  it("una rutina inexistente devuelve 404, no 403", async () => {
    expect(await restRead("routines/watch-f1-no-existe", athlete.idToken))
      .toBe(404);
  });
});
