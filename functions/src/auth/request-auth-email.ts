/**
 * requestPasswordReset / requestEmailVerification — Cloud Functions for TREINO.
 *
 * Reemplazan las plantillas default de Firebase Auth por mail propio, ruteado
 * por el outbox transaccional (Resend).
 *
 * QUE CAMBIA Y QUE NO
 *
 * El link es el mismo que Firebase pondria en su propio mail —mismo `oobCode`,
 * mismo handler— con el HOST reescrito al dominio propio (ver
 * `rewriteActionHost`). No hace falta escribir una pagina de action handler:
 * `auth.gettreino.com` sirve el mismo `/__/auth/action` que hostea Firebase.
 *
 * ANTI-ENUMERACION (REQ-AUTH-011) — la invariante de este archivo
 *
 * `getUserByEmail` y `generatePasswordResetLink` tiran `auth/user-not-found`
 * para una direccion desconocida. Si esa excepcion escapa, el cliente puede
 * distinguir "existe" de "no existe" y el endpoint se convierte en un oraculo
 * de cuentas. Por eso `requestPasswordReset` devuelve SIEMPRE el mismo
 * `{ status: "ok" }`: exista o no, se haya encolado o no, haya fallado o no.
 * La pantalla ya trata `userNotFound` como exito; esto lo sostiene del lado
 * del servidor.
 *
 * Limitacion conocida y NO resuelta: el camino de una cuenta que existe hace
 * mas trabajo (dos llamadas al Admin SDK + una escritura) que el de una que no
 * (una llamada que falla), asi que queda un canal lateral por TIEMPO DE
 * RESPUESTA. Cerrarlo pide un delay constante artificial; se documenta en vez
 * de fingir que no esta.
 *
 * ESTADO: SHELVED — no se exporta desde index.ts todavia.
 *
 * `requestPasswordReset` es un endpoint SIN autenticar que escribe en
 * Firestore. Desplegarlo antes de que el dominio del remitente este verificado
 * por DNS en Resend deja superficie de abuso a cambio de nada: el mail se
 * encola y despues falla con 403. Se activa el mismo dia que el dominio,
 * descomentando el export en index.ts. Ver el comentario de
 * `mail/send-queued-mail.ts`.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { enqueueMail } from "../mail/enqueue-mail";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * Ventana de agrupamiento para limitar la tasa, en minutos.
 *
 * No hace falta una coleccion de throttling: el outbox ya deduplica por ID
 * determinístico, asi que meter el numero de ventana en el `scope` hace que
 * todos los pedidos de la misma ventana colapsen en UN documento — o sea, un
 * solo mail. Un pedido legitimo posterior cae en otra ventana y sale.
 *
 * TIENE QUE SEGUIR ALINEADO con el cooldown del boton "Reenviar" de
 * `forgot_password_screen.dart` (_resendCooldown, 60s). Si esta ventana fuera
 * mas larga que ese cooldown, el usuario apretaria Reenviar, veria la
 * confirmacion, y el mail se descartaria en silencio por deduplicacion — un
 * boton que miente es peor que no tener boton.
 *
 * Con 1 minuto el peor caso queda acotado a ~60 mails por hora por cuenta en
 * vez de ilimitado. Es mas flojo que una ventana larga, y se elige igual:
 * `enforceAppCheck` ya obliga a que el que llama sea una instancia real de la
 * app, y sobre un flujo de RECUPERACION el riesgo de dejar afuera a alguien
 * que de verdad no puede entrar pesa mas que el de mandar un mail de mas.
 *
 * No es un limitador exacto: dos pedidos a caballo del borde de la ventana
 * mandan dos mails. Tambien a proposito, por la misma razon.
 */
const THROTTLE_WINDOW_MIN = 1;

/** Numero de ventana para `nowMs`. Inyectable para testear. */
export function throttleWindow(nowMs: number): number {
  return Math.floor(nowMs / (THROTTLE_WINDOW_MIN * 60 * 1000));
}

/**
 * Host propio donde vive el action handler de Firebase.
 *
 * `auth.gettreino.com` apunta por CNAME al sitio de Hosting `treino-dev`, que
 * sirve el mismo `/__/auth/action` que `treino-dev.firebaseapp.com`. Verificado
 * en produccion: ambos devuelven 200 sobre ese path.
 *
 * POR QUE SE REESCRIBE EN CODIGO Y NO EN LA CONSOLA
 *
 * Firebase Auth tiene un ajuste para esto ("Customize action URL", que escribe
 * `notification.sendEmail.callbackUri`). En este proyecto ese PATCH devuelve
 * **400 EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED** con un payload perfectamente
 * valido, asi que el ajuste esta bloqueado a nivel proyecto por una causa que
 * no pudimos diagnosticar.
 *
 * Reescribir el host aca es mejor igual, con o sin ese bloqueo: queda
 * versionado, revisable, cubierto por tests, y no depende de una config
 * invisible en una consola. `generatePasswordResetLink` devuelve el link con
 * el `oobCode` ya firmado; cambiar el host NO lo invalida, porque el codigo
 * viaja en el query string y lo valida el backend de Auth, no el host.
 */
const ACTION_HANDLER_HOST = "auth.gettreino.com";

/**
 * Cambia el host del action link al dominio propio, dejando intacto el resto.
 *
 * Conservador a proposito: si el link no parsea, o su path no es el namespace
 * reservado de Firebase, se devuelve tal cual. Un link de recuperacion roto es
 * peor que uno feo — el usuario que lo recibe ya no puede entrar a su cuenta.
 *
 * @param link - URL que devolvio el Admin SDK.
 */
export function rewriteActionHost(link: string): string {
  try {
    const url = new URL(link);
    // Solo el namespace reservado de Hosting. Cualquier otra forma queda igual.
    if (!url.pathname.startsWith("/__/auth/")) return link;

    url.protocol = "https:";
    url.host = ACTION_HANDLER_HOST;
    url.port = "";
    return url.toString();
  } catch {
    return link;
  }
}

/** Respuesta uniforme. Nunca revela si la cuenta existe. */
export interface AuthEmailResult {
  status: "ok";
}

const OK: AuthEmailResult = { status: "ok" };

/** Forma minima de email. Rechaza basura sin intentar validar RFC 5322. */
const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Encola el mail de reseteo de contraseña.
 *
 * NUNCA tira por una direccion desconocida, invalida o ausente. Cualquier
 * salida que no sea `{status:"ok"}` seria un oraculo de enumeracion.
 *
 * @param app   - Admin SDK app.
 * @param email - Direccion cruda que mando el cliente.
 * @param nowMs - Reloj, inyectado para que los tests fijen la ventana.
 */
export async function runRequestPasswordReset(
  app: admin.app.App,
  email: unknown,
  nowMs: number = Date.now(),
): Promise<AuthEmailResult> {
  if (typeof email !== "string") return OK;

  const normalized = email.trim().toLowerCase();
  if (!EMAIL_SHAPE.test(normalized)) return OK;

  try {
    // El uid primero: el outbox guarda destinatarios por uid y resuelve la
    // direccion recien al enviar, asi que un cambio de email entre el pedido y
    // el envio sigue llegando a donde tiene que llegar.
    const user = await admin.auth(app).getUserByEmail(normalized);
    const link = await admin.auth(app).generatePasswordResetLink(normalized);

    await enqueueMail(app, {
      toUid: user.uid,
      kind: "password-reset",
      scope: `${user.uid}_${throttleWindow(nowMs)}`,
      params: { actionLink: rewriteActionHost(link) },
    });
  } catch (error: unknown) {
    // Se traga TODO a proposito — incluido user-not-found. Se logea para
    // poder operar, nunca se propaga.
    logger.info("requestPasswordReset: no se encolo", {
      reason: (error as { code?: string }).code ?? "unknown",
    });
  }

  return OK;
}

/**
 * Encola el mail de verificacion de email para un usuario logueado.
 *
 * A diferencia del reseteo, este pide sesion: el que lo llama ya probo quien
 * es, asi que no hay nada que enumerar. Igual devuelve una respuesta uniforme
 * para no filtrar el estado de verificacion de la cuenta.
 *
 * @param app   - Admin SDK app.
 * @param uid   - Usuario autenticado que lo pide.
 * @param nowMs - Reloj, inyectado en tests.
 */
export async function runRequestEmailVerification(
  app: admin.app.App,
  uid: string,
  nowMs: number = Date.now(),
): Promise<AuthEmailResult> {
  try {
    const user = await admin.auth(app).getUser(uid);

    if (!user.email) {
      logger.info("requestEmailVerification: el usuario no tiene email", { uid });
      return OK;
    }

    // Ya verificado: no hay nada que mandar. Sale sin encolar.
    if (user.emailVerified) {
      logger.info("requestEmailVerification: ya estaba verificado", { uid });
      return OK;
    }

    const link = await admin
      .auth(app)
      .generateEmailVerificationLink(user.email);

    await enqueueMail(app, {
      toUid: uid,
      kind: "email-verification",
      scope: `${uid}_${throttleWindow(nowMs)}`,
      params: { actionLink: rewriteActionHost(link) },
    });
  } catch (error: unknown) {
    logger.warn("requestEmailVerification: no se encolo", { uid, error });
  }

  return OK;
}

// ---------------------------------------------------------------------------
// onCall wrappers
//
// `enforceAppCheck: true` en los dos. Importa MAS en requestPasswordReset que
// en cualquier otro callable del repo: es el unico que se puede invocar sin
// sesion, y cada llamada le manda un mail a un tercero. Sin atestacion es un
// amplificador de spam apuntable contra cualquier direccion registrada.
//
// Los dos van a southamerica-east1 como el resto de las CFs de TREINO.
// ---------------------------------------------------------------------------

/** Callable: pedir mail de reseteo. NO requiere sesion, a proposito. */
export const requestPasswordReset = functions.onCall(
  { region: "southamerica-east1", enforceAppCheck: true },
  async (request) => {
    const email = (request.data ?? {}).email;
    return runRequestPasswordReset(getApp(), email);
  },
);

/** Callable: reenviar el mail de verificacion. Requiere sesion. */
export const requestEmailVerification = functions.onCall(
  { region: "southamerica-east1", enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return runRequestEmailVerification(getApp(), request.auth.uid);
  },
);
