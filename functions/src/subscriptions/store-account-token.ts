/**
 * store-account-token.ts — un UUID v4 por usuario, que hoy no se usa para nada.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUE EXISTE ALGO QUE NO SE USA
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Es un seguro, y de los baratos. Hoy TREINO le cobra al alumno por IAP a
 * traves de RevenueCat, y RevenueCat resuelve la identidad del comprador con
 * UNA linea: `Purchases.logIn(uid)`.
 *
 * **Ninguna de las dos tiendas tiene equivalente.** El dia que se quiera
 * hablarles directo:
 *
 *   - Google manda su notificacion de compra con tres campos y **cero
 *     identificador de usuario**. La unica forma de saber a quien acreditarle
 *     es haberle mandado ANTES un token propio (`obfuscatedAccountId`) y
 *     tenerlo indexado.
 *   - Apple consulta por `transactionId`, no por tu uid. El puente es el
 *     `appAccountToken` que vos mandaste al comprar.
 *
 * Y ahi esta la trampa que hace que esto valga la pena hacerlo HOY:
 *
 *   **`appAccountToken` tiene que ser un UUID.** Si el string que se manda no
 *   parsea como UUID, el plugin lo descarta **sin excepcion ni warning**, la
 *   compra sale igual, y el problema aparece en produccion con la plata de un
 *   alumno adentro.
 *
 * Los uid de Firebase son 28 caracteres alfanumericos. **No son UUID.** Asi
 * que el uid no sirve como token y hace falta uno aparte.
 *
 * ── Por que ahora, si no se planea migrar ──
 *
 * Porque el valor de este campo es RETROACTIVO. El dia que haga falta, lo
 * necesitas para todo el que **ya compro**, y a esa altura reconstruir el
 * mapeo significa cruzar transacciones viejas de dos tiendas contra usuarios.
 * Generarlo desde hoy cuesta dos horas y cubre a todos los que compren de
 * aca en adelante.
 *
 * Si nunca se migra, el costo total fueron 36 bytes por usuario.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUE LO ESCRIBE UNA CLOUD FUNCTION Y NO EL CLIENTE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Porque es un ANCLA DE IDENTIDAD DE PAGOS. Si el cliente pudiera escribirlo,
 * podria ponerse el token de otro y reclamar sus compras: el webhook recibe el
 * token, busca a quien pertenece, y encuentra al atacante.
 *
 * Por eso va pineado en `firestore.rules` en los DOS verbos, con la misma
 * leccion que ya dejo escrita `athleteSubscription`: medio pin es peor que
 * ninguno, porque pinear solo el update vuelve INDELEBLE lo que se sembro al
 * crear.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUE `onDocumentWritten` Y NO `onDocumentCreated`
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Porque asi el backfill sale gratis. Con `onDocumentCreated` el campo lo
 * tendrian solo los usuarios nuevos, y los que ya existen necesitarian un
 * script aparte.
 *
 * Escuchando toda escritura y saliendo temprano si el token ya esta, cualquier
 * usuario que toque su documento —cambiar el nombre, la foto, cualquier cosa—
 * queda cubierto solo. El costo es **una escritura extra por usuario, una vez
 * en la vida**: apenas el token existe, esta funcion no vuelve a hacer nada
 * para el.
 *
 * Y no hay loop: la escritura re-dispara el trigger, pero la segunda pasada
 * encuentra el token y corta. Tampoco cascadea sobre
 * `syncAthletePaywallOnUser`, que compara `athleteSubscription` y `role` — y
 * este campo no es ninguno de los dos.
 *
 * El unico caso que queda afuera es el usuario totalmente dormido, que no
 * escribe su documento nunca mas. Lo va a cubrir su proxima escritura, y si
 * algun dia hiciera falta cerrarlo del todo, es un `scripts/` de veinte
 * lineas.
 *
 * ── Nada de dependencias nuevas ──
 *
 * `crypto.randomUUID()` es de Node, y `functions/package.json` pide Node 20.
 * Se evita a proposito sumar un paquete: `functions/` tiene DOS dependencias
 * de produccion y este modulo vive al lado del unico endpoint del repo que
 * otorga acceso pago.
 */

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { getFirestore } from "firebase-admin/firestore";
import { randomUUID } from "node:crypto";

/**
 * El campo. `users/{uid}.storeAccountToken`.
 *
 * Se llama por lo que ES —el token con el que una tienda identifica la cuenta—
 * y no por el proveedor que lo vaya a usar, justamente porque el proveedor es
 * lo que puede cambiar.
 */
export const STORE_ACCOUNT_TOKEN_FIELD = "storeAccountToken";

/** Forma de un UUID v4, que es lo que Apple exige. */
export const UUID_V4 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/**
 * ¿Hay que escribirle un token a este documento?
 *
 * Separado del trigger para poder testear la decision sin emulador. Devuelve
 * `false` tambien cuando el documento fue BORRADO: no tiene sentido —ni es
 * posible— escribirle un campo a algo que ya no esta.
 */
export function necesitaToken(after: Record<string, unknown> | undefined): boolean {
  if (after === undefined) return false;
  const actual = after[STORE_ACCOUNT_TOKEN_FIELD];
  // Se re-emite si lo que hay NO es un UUID valido. Un token con la forma
  // equivocada es peor que ninguno: Apple lo descarta en silencio y la compra
  // queda sin dueno.
  return typeof actual !== "string" || !UUID_V4.test(actual);
}

/**
 * Le asegura un token a cada usuario.
 *
 * Region: la misma que el resto de los triggers de este modulo.
 */
export const ensureStoreAccountToken = onDocumentWritten(
  { document: "users/{uid}", region: "southamerica-east1" },
  async (event) => {
    const after = event.data?.after?.data();
    if (!necesitaToken(after)) return;

    const uid = event.params.uid;
    const token = randomUUID();

    await getFirestore()
      .collection("users")
      .doc(uid)
      .set({ [STORE_ACCOUNT_TOKEN_FIELD]: token }, { merge: true });

    // A nivel debug y sin el token: es un identificador de pagos y no tiene
    // por que quedar en los logs de Cloud Logging.
    logger.debug("store-account-token: token emitido", { uid });
  },
);
