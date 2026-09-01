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
 * ESTADO: desplegado, pero EL CLIENTE TODAVIA NO LO LLAMA.
 *
 * `AuthService.sendPasswordResetEmail` y `sendEmailVerification`
 * (lib/features/auth/data/auth_service.dart:121 y :130) siguen yendo a
 * FirebaseAuth directo, asi que los mails de recuperacion aun salen por las
 * plantillas default. Es a proposito: `treino-dev` es produccion y el padron de
 * Auth es uno solo, no hay donde ensayar. Primero se comprueba a mano que estos
 * callables mandan bien, y recien despues se migra el cliente — sobre un flujo
 * donde el usuario ya esta afuera de su cuenta, ese orden no es opcional.
 *
 * `requestPasswordReset` es un endpoint SIN autenticar que escribe en
 * Firestore. Se publico recien cuando `send.gettreino.com` quedo verificado en
 * Resend: antes habria encolado mail que despues fallaba con 403.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { APP_ENTRY_ATHLETE, APP_ENTRY_TRAINER } from "../mail/templates";
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
 * vez de ilimitado. Es mas flojo que una ventana larga, y se elige igual
 * porque sobre un flujo de RECUPERACION el riesgo de dejar afuera a alguien
 * que de verdad no puede entrar pesa mas que el de mandar un mail de mas.
 *
 * OJO: esta ventana es el UNICO control de abuso que tiene este endpoint. No
 * hay `enforceAppCheck` (ver el bloque de los onCall wrappers y por que), asi
 * que aflojarla no es solo una decision de UX. Si algun dia se sube este
 * numero, revisar primero si App Check ya volvio.
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

/**
 * Que mail corresponde para una cuenta que pidio reseteo.
 *
 * PURA Y EXPORTADA A PROPOSITO — el emulador NO puede validar esta decision.
 *
 * El emulador de Auth no gatea por proveedor: sobre una cuenta solo-Google, sin
 * password hash, `generatePasswordResetLink` devuelve link igual. Verificado en
 * el fuente de firebase-tools (`emulator/auth/operations.js`, PASSWORD_RESET
 * solo hace `getUserByEmail`) y reproducido. O sea que un test de emulador
 * sobre este caso da verde por construccion, sin haber medido nada.
 *
 * Por eso la decision vive ACA, en una funcion sin dependencias, con su propia
 * tabla de casos. Ver el test `resetOutcomeFor` y el guardian que documenta la
 * no-fidelidad del emulador.
 *
 * Nota sobre `providerData` vacio: se elige `password-reset`, o sea el
 * comportamiento de hoy. Una cuenta sin ningun proveedor listado no es
 * federada, asi que mandarle un mail que dice "entra con Google" seria peor que
 * dejarla en el camino actual — que en el peor caso falla en silencio, como ya
 * lo hace.
 *
 * @param providerIds - `user.providerData.map(p => p.providerId)`.
 */
export function resetOutcomeFor(
  providerIds: readonly string[],
): "password-reset" | "federated-signin-hint" {
  if (providerIds.length === 0) return "password-reset";
  return providerIds.includes("password")
    ? "password-reset"
    : "federated-signin-hint";
}

/**
 * A donde mandar a esta persona cuando toque el boton del mail.
 *
 * El destino depende del ROL, y a diferencia de los otros mails —donde el
 * productor ya sabe si le escribe al profe o al atleta— aca no hay contexto:
 * alguien pidio recuperar su cuenta y lo unico que tenemos es el uid.
 *
 * Ante la duda, `alumno`: es el rol mayoritario, y su pagina no le promete al
 * profe nada que no pueda hacer — al reves si, mandar a un atleta al Coach Hub
 * lo deja contra el gate de rol.
 *
 * No es un canal de enumeracion: solo se llega aca con una cuenta que EXISTE y
 * es federada, y la respuesta del callable no cambia.
 */
async function entradaSegunRol(
  app: admin.app.App,
  uid: string,
): Promise<string> {
  try {
    const snap = await admin.firestore(app).collection("users").doc(uid).get();
    return snap.data()?.role === "trainer"
      ? APP_ENTRY_TRAINER
      : APP_ENTRY_ATHLETE;
  } catch (error) {
    logger.warn("requestPasswordReset: no se pudo leer el rol", { uid, error });
    return APP_ENTRY_ATHLETE;
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
    const kind = resetOutcomeFor(user.providerData.map((p) => p.providerId));
    const scope = `${user.uid}_${throttleWindow(nowMs)}`;

    if (kind === "federated-signin-hint") {
      // Sin contraseña que restablecer: NO se pide link. Se le dice al dueño
      // del buzon como entra a su cuenta, y el callable devuelve el mismo
      // `{status:"ok"}` que las otras dos ramas.
      await enqueueMail(app, {
        toUid: user.uid,
        kind,
        scope,
        params: { ctaUrl: await entradaSegunRol(app, user.uid) },
      });
      return OK;
    }

    const link = await admin.auth(app).generatePasswordResetLink(normalized);

    await enqueueMail(app, {
      toUid: user.uid,
      kind,
      scope,
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
// SIN `enforceAppCheck`, y NO es un olvido. Es deuda declarada, con la misma
// condicion de salida que `deleteAccount` y `mintWatchCredential`.
//
// POR QUE
//
// El cliente Android no emite atestacion valida HOY. Medido sobre los logs de
// `mintWatchCredential` el 2026-08-25: iPhone 8 VALID / 2 INVALID, Android
// 1 VALID / 8 INVALID. Con el flag puesto, un usuario de Android no podria
// resetear su contraseña — y es el peor flujo posible para romper, porque el
// que lo necesita ya esta afuera de su cuenta.
//
// PRECISION (2026-08-27): decir "App Check en Android esta roto" seria pasarse
// de la evidencia. Esos 8 INVALID salieron de APKs SIDELOADEADOS, que no
// pueden atestar por construccion — Play Integrity devuelve
// UNRECOGNIZED_VERSION para binarios que Play no distribuyo. No sabemos si
// Play Integrity funciona en este proyecto: nunca se probo en una
// configuracion capaz de ganar. Lo que si esta medido, y es lo unico que hace
// falta para justificar la ausencia del flag, es que el cliente Android que
// existe hoy no atesta. Ver docs/security.md §4.8.2.
//
// Es la misma piedra que el repo ya piso dos veces. `deleteAccount` tuvo el
// flag desde el 2026-07-20 y en ese lapso el borrado no funciono NUNCA: cero
// respuestas 200 en todo el historico retenido. La regla que quedo escrita
// ahi vale igual aca: un flag que convierte un boton en un error permanente
// no da seguridad, da un boton roto.
//
// POR QUE NO EMPEORA NADA
//
// La superficie ya esta abierta HOY, sin nosotros: el SDK del cliente llama a
// `sendPasswordResetEmail` directo contra Firebase, con la API key que viaja
// en el bundle. Cualquiera puede invocarla.
//
// Esta CF no agrega una puerta: le pone un cerrojo a una que ya estaba
// abierta. La ventana de `THROTTLE_WINDOW_MIN` acota el peor caso a ~60 mails
// por hora por cuenta, control que hoy no existe. Y la anti-enumeracion se
// sostiene sola: quien abuse no aprende nada sobre que direcciones existen.
//
// CONDICION DE SALIDA
//
// Que el cliente emita atestacion valida en las DOS plataformas. Contar sobre
// `jsonPayload.verifications.app` en Cloud Logging, SCOPEADO A INSTALACIONES
// DE PLAY / APP STORE CON BUILD DE RELEASE.
//
// El scope no es un detalle de redaccion (corregido el 2026-08-27). Pedir
// "cero INVALID por plataforma" a secas NO SE PUEDE CUMPLIR NUNCA: el log
// mezcla dispositivos de desarrollo con usuarios reales, y mientras alguien
// corra `flutter run` en un Android va a haber INVALID. Sin el scope, esta
// exencion se vuelve permanente por omision — que es justo lo que el registry
// de `appcheck-enforcement.test.ts` existe para evitar.
//
// LOS TRES NO VUELVEN CON UN SOLO INTERRUPTOR. Comparten la causa, no el
// umbral, y este es el que VUELVE ULTIMO. Es el unico de los tres cuyo fallo
// no tiene workaround del lado del usuario: si `deleteAccount` se rompe, un
// boton no anda; si `mintWatchCredential` se rompe, el reloj no vincula. Si
// esto se rompe, alguien que ya no puede entrar a su cuenta se queda sin
// forma de recuperarla, y no se entera nadie — App Check corta en la capa de
// transporte, sin log de aplicacion ni excepcion que capturar.
//
// (`deleteAccount` pide otra cosa, no menos: monitoreo activo del ratio
// VALID/INVALID despues del deploy, porque lo que se cae ahi es Apple
// Guideline 5.1.1(v). Ver el bloque PARA RESTAURARLO de `delete-account.ts`.)
//
// Los dos van a southamerica-east1 como el resto de las CFs de TREINO.
// ---------------------------------------------------------------------------

/** Callable: pedir mail de reseteo. NO requiere sesion, a proposito. */
export const requestPasswordReset = functions.onCall(
  { region: "southamerica-east1" },
  async (request) => {
    const email = (request.data ?? {}).email;
    return runRequestPasswordReset(getApp(), email);
  },
);

/** Callable: reenviar el mail de verificacion. Requiere sesion. */
export const requestEmailVerification = functions.onCall(
  { region: "southamerica-east1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    return runRequestEmailVerification(getApp(), request.auth.uid);
  },
);
