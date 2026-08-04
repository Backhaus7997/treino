/**
 * Tests de reglas para las escrituras que hace el reloj sobre la REST API de
 * Firestore (change `watch-standalone-client`, fase F0).
 *
 * POR QUE ESTE TEST EXISTE
 * ------------------------
 * Firebase no soporta Firestore en watchOS (watchOS es community-supported y
 * Firestore no figura entre sus productos). El cliente del reloj, entonces,
 * habla la REST API de Firestore con un ID token de Firebase Auth como
 * `Authorization: Bearer <token>`.
 *
 * Toda la arquitectura de `watch-standalone-client` descansa en una premisa:
 * que las Security Rules se apliquen a esas requests REST igual que al SDK. Si
 * no se aplicaran, el reloj escribiria sin control de acceso y habria que
 * replantear el change entero. Este test es esa premisa, verificada.
 *
 * POR QUE NO USA @firebase/rules-unit-testing
 * -------------------------------------------
 * Esa libreria ejercita las reglas a traves del SDK de Firestore. El riesgo que
 * hay que cubrir acá es especificamente el camino REST + Bearer token, que el
 * SDK no recorre. Por eso el test hace HTTP crudo contra el emulador: es el
 * mismo camino que va a usar el reloj, byte por byte.
 *
 * Corre bajo `npm --prefix functions test` (que el CI ejecuta dentro de
 * `firebase emulators:exec --only firestore,auth,storage`). NO esta en el
 * allowlist del script `test:rules`, que es solo un atajo local.
 *
 * Requiere los emuladores de Firestore (8080) y Auth (9099).
 */

// El proyecto que levanta `firebase emulators:exec` sale de .firebaserc. El
// emulador de Auth firma los tokens con ese projectId como `aud`, y el de
// Firestore valida contra el mismo, asi que ambos DEBEN resolverse al mismo
// valor: de ahi que se use una sola constante para los dos hosts.
const PROJECT_ID =
  process.env.GCLOUD_PROJECT ?? process.env.FIREBASE_PROJECT ?? "treino-dev";

const AUTH_HOST = "http://127.0.0.1:9099";
const FIRESTORE_HOST = "http://127.0.0.1:8080";
const DOCS = `${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

/** Un usuario nuevo del emulador de Auth. `localId` es el uid que ven las rules. */
interface EmulatorUser {
  idToken: string;
  uid: string;
}

/**
 * Crea un usuario en el emulador de Auth y devuelve su ID token.
 *
 * La apiKey es irrelevante para el emulador (no valida credenciales de
 * proyecto), pero el endpoint la exige como query param.
 */
async function signUpUser(label: string): Promise<EmulatorUser> {
  const res = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        email: `watch-rules-${label}-${Date.now()}@treino.test`,
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
  const body = (await res.json()) as {idToken: string; localId: string};
  return {idToken: body.idToken, uid: body.localId};
}

/** Documento de sesion con la forma que escribe `session_repository.create`. */
function sessionFields() {
  return {
    fields: {
      routineId: {stringValue: "routine-1"},
      routineName: {stringValue: "Push A"},
      startedAt: {timestampValue: "2026-08-04T10:00:00Z"},
    },
  };
}

/** Documento de serie con la identidad logica que usa la idempotencia. */
function setLogFields() {
  return {
    fields: {
      exerciseId: {stringValue: "exercise-1"},
      exerciseName: {stringValue: "Press banca"},
      setNumber: {integerValue: "1"},
      reps: {integerValue: "10"},
      weightKg: {doubleValue: 60},
    },
  };
}

/**
 * PATCH sobre un path de documento — el verbo que usa la REST API para
 * crear-o-actualizar en una ruta conocida. Devuelve el status HTTP crudo:
 * 200 = las rules dejaron pasar, 403 = las rules denegaron.
 */
async function restWrite(
  documentPath: string,
  fields: object,
  idToken?: string,
): Promise<number> {
  const headers: Record<string, string> = {"Content-Type": "application/json"};
  if (idToken !== undefined) {
    headers["Authorization"] = `Bearer ${idToken}`;
  }
  const res = await fetch(`${DOCS}/${documentPath}`, {
    method: "PATCH",
    headers,
    body: JSON.stringify(fields),
  });
  return res.status;
}

describe("watch REST writes — firestore.rules", () => {
  let owner: EmulatorUser;
  let stranger: EmulatorUser;

  beforeAll(async () => {
    owner = await signUpUser("owner");
    stranger = await signUpUser("stranger");
  });

  describe("users/{uid}/sessions/{sessionId}", () => {
    it("acepta que el dueño escriba su propia sesion", async () => {
      const status = await restWrite(
        `users/${owner.uid}/sessions/watch-session-own`,
        sessionFields(),
        owner.idToken,
      );
      expect(status).toBe(200);
    });

    it("deniega que un tercero escriba la sesion de otro uid", async () => {
      const status = await restWrite(
        `users/${owner.uid}/sessions/watch-session-intruder`,
        sessionFields(),
        stranger.idToken,
      );
      expect(status).toBe(403);
    });

    it("deniega la escritura sin token", async () => {
      const status = await restWrite(
        `users/${owner.uid}/sessions/watch-session-anon`,
        sessionFields(),
      );
      expect(status).toBe(403);
    });
  });

  describe("users/{uid}/sessions/{sessionId}/setLogs/{setLogId}", () => {
    it("acepta que el dueño escriba sus propias series", async () => {
      const status = await restWrite(
        `users/${owner.uid}/sessions/watch-session-own/setLogs/set-1`,
        setLogFields(),
        owner.idToken,
      );
      expect(status).toBe(200);
    });

    // El write de setLogs es owner-only incluso para un entrenador vinculado
    // (comentario de firestore.rules: "trainers may never mutate set data").
    // Un tercero cualquiera cae en la misma rama denegada.
    it("deniega que un tercero escriba las series de otro uid", async () => {
      const status = await restWrite(
        `users/${owner.uid}/sessions/watch-session-own/setLogs/set-intruder`,
        setLogFields(),
        stranger.idToken,
      );
      expect(status).toBe(403);
    });

    it("deniega la escritura de series sin token", async () => {
      const status = await restWrite(
        `users/${owner.uid}/sessions/watch-session-own/setLogs/set-anon`,
        setLogFields(),
      );
      expect(status).toBe(403);
    });
  });
});
