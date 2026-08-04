/**
 * mintWatchCredential — Callable de TREINO que le da credencial PROPIA al
 * companion de Apple Watch.
 *
 * Change `watch-standalone-client`, fase F1.
 *
 * POR QUE EXISTE
 * --------------
 * El reloj tiene que operar sin la app del telefono abierta: iniciar entreno,
 * cargar series, finalizar. Para eso necesita credencial propia y renovable.
 *
 * El plan original era que el telefono le pasara SU refresh token. No se
 * puede: `User.refreshToken` de firebase_auth es vacio en nativo. La
 * documentacion del platform interface lo dice textual — "This property will
 * be an empty string for native platforms (android, iOS & macOS) as they do
 * not support refresh tokens".
 *
 * FLUJO
 * -----
 *   1. El telefono llama a esta funcion (autenticado).
 *   2. Recibe un custom token y se lo pasa al reloj por WatchConnectivity.
 *   3. El reloj lo canjea con `accounts:signInWithCustomToken` → obtiene
 *      idToken + refreshToken PROPIOS.
 *   4. De ahi en adelante renueva solo contra `securetoken.googleapis.com`,
 *      sin telefono y sin SDK de Firebase (Locked Decision #9 — Firestore no
 *      figura entre los productos Firebase soportados en watchOS).
 *
 * Ventaja sobre el diseño original: la credencial del reloj es independiente
 * de la del telefono — revocable por separado, y el telefono nunca expone la
 * suya.
 *
 * SEGURIDAD — LA PROPIEDAD LOAD-BEARING
 * -------------------------------------
 * Se mintea SOLO para `request.auth.uid`. La funcion **no acepta ningun uid
 * por parametro**, y esa ausencia es deliberada: es la forma mas fuerte de
 * garantizar que no se puede spoofear, porque no hay input que manipular. Si
 * alguna vez alguien agrega un uid parametrizable, cualquier usuario
 * autenticado podria fabricarse credenciales de cualquier otro y quedarse con
 * su historial entero. El test "ignora un uid inyectado en data" existe para
 * que ese cambio no pase desapercibido.
 *
 * Deliberadamente NO se agregan claims extra (tipo `source: 'watch'`) al
 * custom token: no hay hoy ninguna regla ni consulta que los use, y superficie
 * especulativa es superficie que alguien va a asumir que significa algo.
 *
 * Patron: handler puro (runMintWatchCredential) + wrapper onCall fino
 * (mintWatchCredential). Mismo que addAlias / deleteAccount en este codebase.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * Inicializa la app default del Admin SDK de forma perezosa, para que el
 * modulo se pueda importar sin que exista una app previa (los tests crean su
 * propia app nombrada antes de importar). Copiado de add-alias.ts.
 */
function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * Logica central, extraida para testearla sin pasar por el harness de onCall.
 *
 * @param app      - App de firebase-admin (default, o la nombrada del emulador en tests)
 * @param callerId - UID del llamador autenticado. La credencial se mintea para
 *                   ESTE uid y ningun otro.
 */
export async function runMintWatchCredential(
  app: admin.app.App,
  callerId: string,
): Promise<{ customToken: string }> {
  // Validado aca ademas de en el wrapper, para que el handler sea
  // independientemente testeable.
  if (!callerId) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const customToken = await admin.auth(app).createCustomToken(callerId);

  return { customToken };
}

/**
 * El callable v2 exportado como Cloud Function.
 * Region southamerica-east1, igual que el resto de los callables del proyecto.
 */
export const mintWatchCredential = functions.onCall(
  // App Check enforced: esta funcion entrega credenciales renovables, asi que
  // el gate de atestacion es defensa en profundidad sobre request.auth. Mismo
  // criterio que addAlias (QA-SEC-006).
  { region: "southamerica-east1", enforceAppCheck: true },
  async (request): Promise<{ customToken: string }> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    // `request.data` se ignora a proposito y por completo. Ver la nota de
    // seguridad del encabezado: el uid sale UNICAMENTE del token verificado.
    return runMintWatchCredential(getApp(), request.auth.uid);
  },
);
