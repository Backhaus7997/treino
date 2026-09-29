/**
 * baja-por-mail.ts — el Botón de Baja de Servicio, AUTOMÁTICO, verificado por
 * mail.
 *
 * Diseño completo: `openspec/changes/baja-por-mail/design.md`.
 *
 * ── Qué resuelve ──
 *
 * La Disp. 954/2025 (art. 4) exige un «BOTÓN DE BAJA DE SERVICIO» público, sin
 * registración previa. Hasta hoy la landing lo tenía, pero detrás había un
 * formulario que terminaba en una planilla y una persona dando la baja a mano.
 * Esto lo hace automático sin abrir el agujero obvio: un endpoint público que da
 * de baja por correo le permitiría a cualquiera darle de baja la suscripción a
 * otro sabiéndole el mail. La Disp. 3/2026 habilita exactamente el resguardo que
 * falta —verificación de identidad razonable, por medios habituales, DESPUÉS del
 * botón— y el medio habitual es el propio correo de la cuenta.
 *
 * ── El flujo, en dos llamadas ──
 *
 *   1. `solicitarBajaPorMail({email, code?})` — público. Si el correo es de una
 *      cuenta con una suscripción que todavía puede cobrar, le manda a ESE
 *      buzón un link de un solo uso. Contesta SIEMPRE `{status:"ok"}`.
 *   2. `confirmarBajaPorMail({token})` — público. Canjea el link y ejecuta la
 *      MISMA baja que `cancelMySubscription`, con el uid que dice el documento
 *      del token — nunca con uno que venga en el request.
 *
 * ── ⚠️ Invariantes que no se negocian ──
 *
 * **1. Anti-enumeración.** `solicitarBajaPorMail` no puede distinguir «no
 * existe», «existe pero no paga» y «te mandamos el mail». Mismo contrato que
 * `runRequestPasswordReset` (REQ-AUTH-011), con la misma limitación conocida: el
 * camino que encola hace más trabajo, así que queda un canal lateral por tiempo
 * de respuesta. Se documenta en vez de fingir que no está.
 *
 * **2. El token crudo no se guarda en ningún documento propio.** Se guarda su
 * SHA-256 como id de `mp_bajas_por_mail/{hash}`. Quien lea la colección —un
 * backup, una exportación, un operador— no puede canjear nada. El crudo viaja
 * UNA vez, adentro del mail, en `params.actionLink`, que `sendQueuedMail` BORRA
 * del documento de la cola apenas se envía (ver `send-queued-mail.ts`). Por eso
 * el param se llama `actionLink` y no `confirmUrl`: es el nombre que el
 * outbox ya sabe tratar como secreto.
 *
 * **3. El token va en el FRAGMENTO de la URL (`#t=`).** Un fragmento no viaja
 * en el request HTTP: no aparece en logs de Vercel, ni de un proxy, ni en el
 * `Referer`. La página lo lee con JS.
 *
 * **4. La confirmación es un CLICK, no un GET.** Los escáneres de correo
 * (Outlook Safe Links, Gmail, antivirus corporativos) PRE-ABREN los links de un
 * mail. Si abrir el link diera la baja, la daría el escáner. La página de la
 * landing muestra un botón y recién ese botón llama a `confirmarBajaPorMail`.
 * (Ese lado vive en `treino-app`, en un PR aparte.)
 *
 * **5. Un solo uso, con reclamo en transacción.** Dos clicks simultáneos no
 * pueden cancelar dos veces. Y si Mercado Pago no contesta, el reclamo se
 * LIBERA: el link sigue sirviendo para reintentar, en vez de quemarse sobre una
 * baja que no pasó.
 */

import { randomBytes as cryptoRandomBytes } from "crypto";

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";

import { MpClient, createMpClient } from "./client";
import { planesQueCobran, runCancelMySubscription } from "./cancel-my-subscription";
import {
  TOKEN_SHAPE,
  TOKEN_TTL_MS,
  hashToken,
  liberarReclamo,
  reclamarToken,
} from "./token-un-solo-uso";
import { dedupeKey, enqueueMail } from "../../mail/enqueue-mail";
import { LANDING_URL } from "../../mail/templates";
import { MAIL_QUEUE_COLLECTION } from "../../mail/types";

// El canje del token vive en `token-un-solo-uso.ts`, compartido con el botón de
// arrepentimiento. Se re-exportan las dos que este módulo siempre exportó.
export { TOKEN_TTL_MS, hashToken };

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

/** Colección de los tokens. CF-only: `firestore.rules` la cierra entera. */
export const BAJAS_POR_MAIL_COLLECTION = "mp_bajas_por_mail";

/**
 * Ventana de throttle, en minutos. Mismo mecanismo que `request-auth-email.ts`:
 * el número de ventana entra en el `scope` del mail, y el outbox deduplica por
 * id determinístico, así que todos los pedidos de una ventana colapsan en UN
 * mail.
 *
 * 10 y no 1 como el reseteo de contraseña, porque acá el riesgo es otro: el
 * endpoint es público y el que abusa no es el dueño del buzón, es alguien que
 * le quiere llenar la casilla a un tercero con mails de «confirmá tu baja». Y el
 * dueño legítimo no pierde nada esperando: el link que ya le llegó sirve 72
 * horas.
 */
const THROTTLE_WINDOW_MIN = 10;

/** Número de ventana para `nowMs`. */
export function ventanaDeThrottle(nowMs: number): number {
  return Math.floor(nowMs / (THROTTLE_WINDOW_MIN * 60 * 1000));
}

/** Forma mínima de email. La misma que `request-auth-email.ts`. */
const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * El código que emite la landing para el trámite (art. 5 de la 954/2025). Se
 * acepta sólo con esta forma exacta: viaja al asunto de un mail, y un campo
 * libre ahí sería un canal para escribirle texto arbitrario a un tercero desde
 * nuestro dominio.
 */
const CODE_SHAPE = /^BAJA-\d{4}-[0-9A-F]{6}$/i;

/** Ruta de la página de confirmación, en la landing. */
const CONFIRM_PATH = "/es/baja-de-servicio/confirmar";

/** Respuesta uniforme de la solicitud. Nunca revela nada. */
export interface SolicitarBajaResult {
  status: "ok";
}

const OK: SolicitarBajaResult = { status: "ok" };

export type EstadoConfirmacion =
  /** El token no tiene forma, o no existe. */
  | "invalido"
  /** Ya se canjeó. */
  | "ya-usado"
  /** Pasaron las 72 horas. */
  | "vencido"
  /** MP aceptó la baja. */
  | "dada-de-baja"
  /** No había nada que dar de baja. El token queda usado. */
  | "sin-suscripcion"
  /** MP no contestó, o hay una baja en curso. El link sigue sirviendo. */
  | "no-disponible";

export interface ConfirmarBajaResult {
  status: EstadoConfirmacion;
  /** Hasta cuándo conserva el acceso. Sólo con `dada-de-baja`, y si se sabe. */
  accesoHastaIso?: string;
}

export interface SolicitarBajaDeps {
  nowMs: number;
  /** Inyectable: los tests fijan el token. Default `crypto.randomBytes`. */
  randomBytes?: (n: number) => Buffer;
}

export interface ConfirmarBajaDeps {
  mpClient: MpClient;
  nowMs: number;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** El código si tiene la forma exacta, normalizado a mayúsculas; si no, null. */
export function normalizarCodigo(code: unknown): string | null {
  if (typeof code !== "string") return null;
  const c = code.trim();
  return CODE_SHAPE.test(c) ? c.toUpperCase() : null;
}

/**
 * Pide el mail de confirmación de baja.
 *
 * NUNCA tira y SIEMPRE devuelve `{status:"ok"}` —input basura incluido—, igual
 * que `runRequestPasswordReset`. Un `invalid-argument` para un mail mal formado
 * y un `ok` para uno bien formado no filtran cuentas, pero cualquier rama que
 * tire es una rama que el día de mañana alguien hace tirar distinto según
 * exista o no la cuenta. Una sola salida no se puede romper así.
 */
export async function runSolicitarBajaPorMail(
  app: App,
  input: { email: unknown; code?: unknown },
  deps: SolicitarBajaDeps,
): Promise<SolicitarBajaResult> {
  if (typeof input?.email !== "string") return OK;
  const email = input.email.trim().toLowerCase();
  if (!EMAIL_SHAPE.test(email)) return OK;
  const code = normalizarCodigo(input.code);

  try {
    const user = await getAuth(app).getUserByEmail(email);
    const uid = user.uid;

    // La MISMA consulta que usa la baja. Si no hay nada que pueda cobrar, un
    // mail de «confirmá tu baja» sería prometer algo que la confirmación
    // después no hace. Ese caso lo cubre el canal manual (ver design.md).
    const planes = await planesQueCobran(app, uid);
    if (planes.length === 0) {
      logger.info("bajaPorMail: sin plan que cobre, no se manda nada", { uid });
      return OK;
    }

    // ── Throttle ANTES de crear el token ──
    //
    // El outbox ya deduplica, pero si se dejara todo en sus manos cada pedido
    // de la ventana crearía un token que nunca sale en ningún mail. Se mira
    // primero si el mail de esta ventana ya existe; la carrera entre dos
    // pedidos simultáneos la resuelve el `create()` de abajo.
    const scope = `${uid}_${ventanaDeThrottle(deps.nowMs)}`;
    const mailId = dedupeKey("service-cancel-confirm", scope, uid);
    const db = getFirestore(app);
    if ((await db.collection(MAIL_QUEUE_COLLECTION).doc(mailId).get()).exists) {
      logger.info("bajaPorMail: throttle, ya hay un mail en esta ventana", { uid });
      return OK;
    }

    const token = (deps.randomBytes ?? cryptoRandomBytes)(32).toString("base64url");
    const ref = db.collection(BAJAS_POR_MAIL_COLLECTION).doc(hashToken(token));
    await ref.create({
      uid,
      code,
      createdAt: Timestamp.fromMillis(deps.nowMs),
      expiresAt: Timestamp.fromMillis(deps.nowMs + TOKEN_TTL_MS),
      usedAt: null,
    });

    const params: Record<string, string> = {
      actionLink: `${LANDING_URL}${CONFIRM_PATH}#t=${token}`,
    };
    if (code) params.code = code;

    const queued = await enqueueMail(app, {
      toUid: uid,
      kind: "service-cancel-confirm",
      scope,
      params,
      // SIN prefKey: es la respuesta a un trámite que la persona acaba de
      // iniciar, no una novedad de producto que se pueda apagar.
    });

    if (queued === null) {
      // Perdió la carrera contra otro pedido de la misma ventana, o la cola
      // falló. En los dos casos este token no va a llegar a ningún buzón: se
      // borra para que no quede un secreto vivo que nadie tiene.
      await ref.delete().catch(() => undefined);
    }
  } catch (error: unknown) {
    // Se traga TODO, incluido user-not-found. Se loguea el código, nunca el
    // mail: el log no puede ser el oráculo que la respuesta evita ser.
    logger.info("bajaPorMail: no se encoló", {
      reason: (error as { code?: string }).code ?? "unknown",
    });
  }

  return OK;
}

/**
 * Canjea el link y da de baja.
 *
 * El uid SALE DEL DOCUMENTO DEL TOKEN. El request trae un token y nada más: no
 * hay ningún campo que pueda apuntar a la suscripción de otro, por el mismo
 * motivo que `cancelMySubscription` no tiene body — en Mercado Pago una baja no
 * se deshace.
 */
export async function runConfirmarBajaPorMail(
  app: App,
  input: { token: unknown },
  deps: ConfirmarBajaDeps,
): Promise<ConfirmarBajaResult> {
  const token = input?.token;
  if (typeof token !== "string" || !TOKEN_SHAPE.test(token)) {
    return { status: "invalido" };
  }

  const db = getFirestore(app);
  const ref = db.collection(BAJAS_POR_MAIL_COLLECTION).doc(hashToken(token));
  const claimId = cryptoRandomBytes(8).toString("hex");

  // ── El reclamo, en transacción ── (ver `token-un-solo-uso.ts`)
  //
  // Dos clicks simultáneos (doble tap, dos pestañas) leen `usedAt: null` los
  // dos; la transacción hace que sólo uno escriba. El otro reintenta, ve el
  // reclamo, y contesta `ya-usado`.
  const reclamo = await reclamarToken(app, ref, deps.nowMs, claimId);

  if (!reclamo.ok) return { status: reclamo.status };
  const { uid, code } = reclamo;

  let resultado;
  try {
    resultado = await runCancelMySubscription(app, uid, deps);
  } catch (error: unknown) {
    // Algo reventó a mitad de camino. Liberar es seguro aunque MP ya hubiera
    // cancelado: el reintento encuentra la suscripción cancelada, no vuelve a
    // llamar a `cancelPreapproval` y contesta `sin-suscripcion`.
    logger.error("bajaPorMail: la baja reventó", { uid, error: String(error) });
    await liberarReclamo(app, ref, reclamo.claimId);
    return { status: "no-disponible" };
  }

  if (resultado.estado === "no-disponible" || resultado.enfriando === true) {
    // MP no contestó, o hay otra baja del mismo usuario hace menos de 10 s. En
    // ninguno de los dos casos pasó nada: el link tiene que seguir sirviendo.
    await liberarReclamo(app, ref, reclamo.claimId);
    return { status: "no-disponible" };
  }

  await ref.update({ resultado: resultado.estado }).catch(() => undefined);

  if (resultado.estado === "sin-suscripcion") {
    return { status: "sin-suscripcion" };
  }

  const params: Record<string, string> = {};
  if (code) params.code = code;
  if (resultado.accesoHastaIso) params.accesoHastaIso = resultado.accesoHastaIso;

  await enqueueMail(app, {
    toUid: uid,
    kind: "service-cancel-done",
    // Un token, una baja, un mail. El hash ya es único y no es el secreto.
    scope: ref.id,
    params,
  });

  return {
    status: "dada-de-baja",
    ...(resultado.accesoHastaIso ? { accesoHastaIso: resultado.accesoHastaIso } : {}),
  };
}

// ---------------------------------------------------------------------------
// onCall wrappers
//
// SIN `enforceAppCheck`, y NO es un olvido: los llama la landing (el primero
// desde su servidor, el segundo desde la página de confirmación), y la landing
// no tiene Firebase ni App Check. Además el art. 4 de la 954/2025 prohíbe
// exigir registración previa, así que tampoco hay `request.auth` que pedir.
//
// Lo que los cierra no es la atestación:
//   - `solicitarBajaPorMail` sólo puede mandar un mail al DUEÑO del buzón, con
//     throttle de una ventana de 10 minutos, y no revela nada.
//   - `confirmarBajaPorMail` sólo actúa con un token de 256 bits que únicamente
//     llegó a ese buzón.
// La exención está declarada en `__tests__/appcheck-enforcement.test.ts`.
// ---------------------------------------------------------------------------

/** Callable: pedir el link de baja. Público, a propósito. */
export const solicitarBajaPorMail = functions.onCall(
  { region: "southamerica-east1", maxInstances: 5 },
  async (request): Promise<SolicitarBajaResult> => {
    const data = (request.data ?? {}) as { email?: unknown; code?: unknown };
    return runSolicitarBajaPorMail(
      ensureApp(),
      { email: data.email, code: data.code },
      { nowMs: Date.now() },
    );
  },
);

/** Callable: canjear el link. Público; la credencial es el token. */
export const confirmarBajaPorMail = functions.onCall(
  { region: "southamerica-east1", maxInstances: 5, secrets: [MP_ACCESS_TOKEN] },
  async (request): Promise<ConfirmarBajaResult> => {
    const data = (request.data ?? {}) as { token?: unknown };
    return runConfirmarBajaPorMail(ensureApp(), { token: data.token }, {
      mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
      nowMs: Date.now(),
    });
  },
);
