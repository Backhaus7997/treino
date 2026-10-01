/**
 * baja-de-promocionales.ts — el link de baja del pie de los correos comerciales.
 *
 * Diseño completo: `openspec/changes/baja-de-correos-promocionales/design.md`.
 *
 * ── Qué resuelve ──
 *
 * `users/{uid}.notificationPrefs.novedades_plan.email === false` ya frena los
 * mails comerciales (`emailChannelAllowed`, en `send-queued-mail.ts`), pero
 * nadie escribía esa preferencia. Esto es el mecanismo para pedirlo desde el
 * propio correo, sin sesión: el Decreto 1558/01 (Anexo I, art. 27, párrafo 3) lo
 * exige en TODA comunicación con fines de publicidad.
 *
 * ── Las dos mitades ──
 *
 *   1. Al ENVIAR, `sendQueuedMail` firma `(uid, prefKey)` y pone el link en el
 *      pie (`urlDeBaja`). El link NO se guarda en `mail_queue`.
 *   2. La página de la landing lee el token del fragmento y, con un click,
 *      llama a `bajaDeCorreosPromocionales({token})`, que lo verifica y apaga el
 *      canal de mail de esa preferencia.
 *
 * ── Por qué un HMAC y no un token guardado ──
 *
 * `subscriptions/mp/token-un-solo-uso.ts` guarda `sha256(token)` con 72 h de
 * vida y uso único. Para una baja de correos las dos propiedades están mal: el
 * link tiene que servir en el mail que se abre dos meses después (la norma pide
 * el mecanismo en TODA comunicación, no en las recientes), y darse de baja dos
 * veces es idempotente. Un token guardado, además, deja un documento por mail
 * con el uid adentro y obliga a sumar la colección al borrado de cuenta. El HMAC
 * no guarda nada.
 *
 * ── ⚠️ Invariantes que no se negocian ──
 *
 * **1. El uid sale del token, nunca del request.** La callable recibe `{token}`
 * y nada más.
 *
 * **2. La forma se chequea ANTES de calcular nada.** Un input gigante o con
 * basura se corta en la regex, sin gastar CPU en el HMAC (mismo criterio que
 * `baja-por-mail.ts`).
 *
 * **3. `prefKey` en allowlist.** Un token bien firmado con otra clave de
 * preferencia contesta `invalido`: la callable nunca escribe un campo que no
 * esté en la lista.
 *
 * **4. Nunca se CREA el documento.** Se escribe con `update`; si la cuenta ya no
 * existe contesta `listo`, igual que una viva (anti-enumeración: es cierto, no
 * le vamos a escribir, y no le cuenta a nadie si la cuenta existe).
 *
 * **4b. El replay no escribe.** El token no vence, así que uno filtrado se puede
 * repetir. Se lee el documento antes: con la preferencia ya apagada contesta
 * `listo` SIN escribir, y sin escritura no se disparan los triggers de `users`.
 * El costo de un replay es una lectura por llamada.
 *
 * **5. El token no se loguea.** Lo que se loguea es el uid, que ya está en la
 * base; el token es la credencial.
 */

import { createHmac, timingSafeEqual } from "crypto";

import { App, getApp, initializeApp } from "firebase-admin/app";
import { FieldPath, getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";

import { ATHLETE_PROSPECT_PREF_KEY } from "../subscriptions/athlete-prospect-mail";
import { LANDING_URL } from "./templates";

/**
 * Clave del HMAC. Un secreto propio, con un solo propósito: no se reusa
 * `RESEND_API_KEY` ni `MP_WEBHOOK_SECRET`. Se crea con:
 *   openssl rand -base64 48 | tr -d '\n' \
 *     | firebase functions:secrets:set BAJA_PROMOCIONALES_KEY --data-file=- --project prod
 *
 * ⚠️ Ese comando escribe en PRODUCCIÓN (#826): `prod` y `treino-dev` son el mismo
 * y único proyecto Firebase de TREINO. Lo crea una persona, nunca un agente, y
 * ANTES de mergear el PR que lo declara: con `defineSecret`, un secreto sin
 * versión hace fallar todo deploy de functions. Ver el §10 del diseño.
 *
 * Rotarlo (una versión nueva) invalida todos los links ya enviados. Sólo ante
 * una filtración; el prefijo `v1` del token deja lugar para convivir con un `v2`.
 */
export const BAJA_PROMOCIONALES_KEY = defineSecret("BAJA_PROMOCIONALES_KEY");

/** Ruta de la página de baja, en la landing (`treino-app`). */
const RUTA_DE_BAJA = "/es/correos-promocionales/baja";

/**
 * Lo que va firmado además de los dos campos. El propósito viaja en el mensaje:
 * una firma de este esquema no sirve para otra cosa, y una de otra cosa no sirve
 * acá.
 */
const PROPOSITO = "baja-promocionales/v1/";

/**
 * La gramática cerrada del token. Los segmentos van en base64url porque un uid
 * de Auth importado puede tener puntos: sin codificar sería irrepresentable o
 * ambiguo. 43 caracteres son los 32 bytes de un SHA-256 en base64url sin relleno.
 */
const TOKEN_SHAPE = /^v1\.[A-Za-z0-9_-]{1,64}\.[A-Za-z0-9_-]{1,200}\.[A-Za-z0-9_-]{43}$/;

/** Largo máximo total. Corta un input gigante antes de que cueste CPU. */
const TOKEN_MAX_LEN = 320;

/**
 * Las preferencias que tienen baja por link: sólo `novedades_plan`. Se DERIVA de
 * la constante que usan los productores; un literal acá sería una segunda copia
 * de la clave, y la que se desincronice deja un link que contesta `invalido`.
 */
const PREFS_CON_BAJA: ReadonlySet<string> = new Set([ATHLETE_PROSPECT_PREF_KEY]);

/**
 * ¿Este uid sirve como id de documento de `users/{uid}`?
 *
 * Auth acepta uids de 1 a 128 caracteres y no mira su contenido, pero
 * `collection("users").doc(uid)` SÍ lo lee como ruta: un uid `a/b/c` apunta a
 * `users/a/b/c`, otro documento, en otra colección. Con el uid sacado de un
 * token, ese sería el camino a escribir donde no corresponde, así que se
 * rechaza al firmar y al verificar. Tampoco sirven `.` ni `..`, ni los que
 * Firestore reserva (`__algo__`): `doc()` los rechaza con un error que no es
 * `NOT_FOUND`.
 */
function esUidDeDocumento(uid: string): boolean {
  return (
    uid.length > 0 &&
    !uid.includes("/") &&
    uid !== "." &&
    uid !== ".." &&
    !/^__.*__$/.test(uid)
  );
}

/** ¿Esta preferencia tiene baja por link? */
export function prefTieneBaja(prefKey: unknown): prefKey is string {
  return typeof prefKey === "string" && PREFS_CON_BAJA.has(prefKey);
}

const aBase64Url = (texto: string): string =>
  Buffer.from(texto, "utf8").toString("base64url");

const deBase64Url = (segmento: string): string =>
  Buffer.from(segmento, "base64url").toString("utf8");

/** HMAC-SHA256 del propósito y los dos segmentos YA codificados, en base64url. */
function firmar(key: string, p: string, u: string): string {
  return createHmac("sha256", key)
    .update(`${PROPOSITO}${p}/${u}`)
    .digest("base64url");
}

/**
 * Arma el token: `v1.<b64url(prefKey)>.<b64url(uid)>.<b64url(HMAC)>`.
 *
 * NO chequea la allowlist, a propósito: la autoridad es `verificarToken`, y así
 * el test puede firmar con una clave de preferencia ajena para probar que la
 * verificación la rechaza. Quien llama decide para qué claves emite links
 * (`prefTieneBaja`).
 *
 * Tira si la clave está vacía —un HMAC con clave vacía es válido para Node y
 * cualquiera podría forjarlo—, si el uid no sirve como id de documento (ver
 * `esUidDeDocumento`) o si el resultado no cabe en la gramática: un link que
 * `verificarToken` va a rechazar siempre es un link muerto en un mail que se
 * manda de verdad.
 */
export function firmarToken(uid: string, prefKey: string, key: string): string {
  if (!key) throw new Error("firmarToken: clave vacía");
  if (!esUidDeDocumento(uid)) {
    throw new Error("firmarToken: el uid no es un id de documento");
  }
  const p = aBase64Url(prefKey);
  const u = aBase64Url(uid);
  const token = `v1.${p}.${u}.${firmar(key, p, u)}`;
  if (token.length > TOKEN_MAX_LEN || !TOKEN_SHAPE.test(token)) {
    throw new Error("firmarToken: el token no entra en la gramática");
  }
  return token;
}

/** El link que va en el pie del mail. */
export function urlDeBaja(uid: string, prefKey: string, key: string): string {
  return `${LANDING_URL}${RUTA_DE_BAJA}#t=${firmarToken(uid, prefKey, key)}`;
}

/** Lo que dice un token válido. */
export interface BajaVerificada {
  uid: string;
  prefKey: string;
}

/**
 * Verifica un token. Devuelve lo que firma, o `null` por CUALQUIER motivo —
 * forma, firma, versión, clave vacía, preferencia fuera de la allowlist—: quien
 * llama no tiene por qué distinguirlos, y quien ataca no debería poder.
 */
export function verificarToken(token: unknown, key: string): BajaVerificada | null {
  // La forma, ANTES de cualquier cuenta. El largo primero: es lo más barato.
  if (typeof token !== "string") return null;
  if (token.length > TOKEN_MAX_LEN || !TOKEN_SHAPE.test(token)) return null;
  // Sin clave no hay nada contra qué verificar. Falla cerrado.
  if (!key) return null;

  const [, p, u, firma] = token.split(".");

  // Se comparan las firmas CODIFICADAS, byte a byte: así sólo la forma canónica
  // de la firma verifica (decodificar base64url ignora los bits sobrantes del
  // último carácter, y 4 strings distintos dan los mismos 32 bytes).
  // `timingSafeEqual` TIRA con largos distintos, por eso el chequeo previo.
  const dada = Buffer.from(firma);
  const esperada = Buffer.from(firmar(key, p, u));
  if (dada.length !== esperada.length || !timingSafeEqual(dada, esperada)) {
    return null;
  }

  // Recién con la firma buena se mira qué pide. El orden no filtra nada, pero
  // no hay por qué decodificar lo que no está firmado.
  const prefKey = deBase64Url(p);
  if (!prefTieneBaja(prefKey)) return null;

  // Y el uid tiene que ser un id de documento: con la firma buena igual puede
  // venir uno que `doc()` leería como ruta (`a/b/c`). Ver `esUidDeDocumento`.
  const uid = deBase64Url(u);
  if (!esUidDeDocumento(uid)) return null;

  return { uid, prefKey };
}

export type EstadoDeBaja =
  /** Quedó apagado (o ya lo estaba, o la cuenta ya no existe). */
  | "listo"
  /** El token no sirve. No distingue por qué. */
  | "invalido";

export interface BajaDeCorreosResult {
  status: EstadoDeBaja;
}

/** Código gRPC de `update()` sobre un documento que no existe. */
const NOT_FOUND = 5;

function esNotFound(error: unknown): boolean {
  const code = (error as { code?: unknown } | null)?.code;
  return code === NOT_FOUND || code === "not-found";
}

/**
 * Da de baja: `users/{uid}.notificationPrefs.<prefKey>.email = false`.
 *
 * NUNCA tira por input basura —no-objeto, sin token, token de 10 KB—: contesta
 * `invalido`. Sí tira ante una falla REAL de Firestore: contestar `listo` sin
 * haber escrito sería prometer algo falso, y la página tiene un mensaje para
 * «probá de nuevo con este mismo link».
 *
 * @param app   - Admin SDK app.
 * @param input - Lo que mandó el cliente, sin confiar en su forma.
 * @param key   - Clave del HMAC. Se inyecta para los tests.
 */
export async function runBajaDeCorreosPromocionales(
  app: App,
  input: unknown,
  key: string,
): Promise<BajaDeCorreosResult> {
  const token = typeof input === "object" && input !== null ?
    (input as { token?: unknown }).token :
    undefined;

  const baja = verificarToken(token, key);
  if (!baja) {
    // Ni el token ni su largo: el log no puede ser un lugar donde queden
    // credenciales, ni siquiera inválidas.
    logger.info("bajaDeCorreosPromocionales: token inválido");
    return { status: "invalido" };
  }

  const { uid, prefKey } = baja;
  const ref = getFirestore(app).collection("users").doc(uid);
  // Con `FieldPath` en vez de un string con puntos, para que una clave con
  // puntos no se lea como anidada.
  const campo = new FieldPath("notificationPrefs", prefKey, "email");
  try {
    // LEE PRIMERO. Un token válido no vence (es la propiedad buscada: tiene que
    // servir en el mail de hace meses), así que uno filtrado o reenviado se puede
    // repetir sin fin. Si cada llamada ESCRIBIERA, cada una dispararía los
    // triggers de `users`; leyendo primero, el replay cuesta una lectura y, con
    // la preferencia ya apagada, NO escribe: sin escritura no hay triggers.
    const snap = await ref.get();
    if (!snap.exists) {
      // La cuenta ya no existe. No hay nada que apagar ni a quién escribirle, y
      // decir «listo» es cierto y no revela si la cuenta existía. Nunca se CREA.
      logger.info("bajaDeCorreosPromocionales: la cuenta no existe", { uid });
      return { status: "listo" };
    }
    if (snap.get(campo) === false) {
      logger.info("bajaDeCorreosPromocionales: ya estaba apagada, no se escribe", {
        uid,
        prefKey,
      });
      return { status: "listo" };
    }

    // `update` y NO `set`: un `set` con merge crearía `users/{uid}` si la cuenta
    // se borra entre la lectura y la escritura, y un documento a medias en
    // `users` es peor que ninguno. Sólo toca esa hoja: no pisa las demás claves
    // de `notificationPrefs`.
    await ref.update(campo, false);
  } catch (error: unknown) {
    if (esNotFound(error)) {
      // Se borró entre la lectura y la escritura.
      logger.info("bajaDeCorreosPromocionales: la cuenta ya no existe", { uid });
      return { status: "listo" };
    }
    logger.error("bajaDeCorreosPromocionales: no se pudo dar de baja", {
      uid,
      prefKey,
      error: String(error),
    });
    throw error;
  }

  logger.info("bajaDeCorreosPromocionales: baja registrada", { uid, prefKey });
  return { status: "listo" };
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

// ---------------------------------------------------------------------------
// onCall wrapper
//
// SIN `enforceAppCheck`, y NO es un olvido: la llama la página pública de la
// landing, que no tiene Firebase ni App Check, y la norma pide el mecanismo SIN
// registración previa, así que tampoco hay `request.auth` que pedir.
//
// Lo que la cierra no es la atestación: la única entrada es un token firmado
// que sólo llegó al buzón de la cuenta, y lo único que habilita es apagar el
// canal de mail de UNA preferencia de esa cuenta —nunca encenderlo, nunca otro
// campo, nunca otro uid—. La exención está declarada en
// `__tests__/appcheck-enforcement.test.ts`.
//
// Lo que NO la cierra: un token válido que se filtre se puede reproducir sin
// límite, porque no vence. Cada llamada cuesta una lectura de `users/{uid}`, y
// si la preferencia ya estaba apagada no escribe (ver `runBajaDeCorreosPromocionales`).
// `maxInstances: 5` limita la CONCURRENCIA —cuántas instancias corren a la vez—,
// no el total de llamadas.
// ---------------------------------------------------------------------------

/** Callable: dar de baja los correos promocionales. Pública; la credencial es el token. */
export const bajaDeCorreosPromocionales = functions.onCall(
  {
    region: "southamerica-east1",
    maxInstances: 5,
    secrets: [BAJA_PROMOCIONALES_KEY],
  },
  async (request): Promise<BajaDeCorreosResult> =>
    runBajaDeCorreosPromocionales(
      ensureApp(),
      request.data,
      BAJA_PROMOCIONALES_KEY.value(),
    ),
);
