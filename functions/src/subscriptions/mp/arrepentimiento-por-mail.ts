/**
 * arrepentimiento-por-mail.ts — el Botón de Arrepentimiento, VERIFICADO por
 * mail y con el plazo decidido por NUESTRO registro.
 *
 * ── NO ES LA BAJA ──
 *
 * Son dos derechos distintos y no se mezclan:
 *
 *   - BAJA (`baja-por-mail.ts`): en cualquier momento. Conserva el acceso hasta
 *     el fin del período pagado y NO devuelve plata.
 *   - ARREPENTIMIENTO (este archivo): sólo dentro de los 10 días corridos de la
 *     contratación (Ley 24.240 art. 34). Devuelve TODO lo pagado.
 *
 * ── Qué se automatiza y qué no ──
 *
 * Se automatiza todo lo que se puede deshacer o verificar:
 *
 *   1. Que quien pide sea el dueño de la cuenta (link al mail de la cuenta).
 *   2. Que esté dentro del plazo, con la fecha de contratación de NUESTRO
 *      registro con Mercado Pago y no la que escribe la persona en el formulario.
 *   3. Cortar la suscripción Y LOS BENEFICIOS en el acto. Se devuelve TODO lo
 *      pagado, así que no queda acceso gratis hasta fin de período (que es lo
 *      que hace una baja común). El corte es un marcador en el plan que el
 *      reconciliador respeta: ver `arrepentidoAtDe`.
 *   4. Avisar: al usuario con su código, y al equipo con todo lo necesario.
 *
 * **La devolución de la plata queda MANUAL, a propósito.** Es lo único que no se
 * puede deshacer, y es el paso donde una persona tiene que mirar.
 *
 * ── Lo que decide el plazo (ver `plazo-arrepentimiento.ts`) ──
 *
 *   - `dentro`    → se corta la suscripción y el acceso, y se avisa al equipo
 *                   para devolver.
 *   - `a-revisar` → NO se cancela nada; lo decide una persona. Es la franja del
 *                   último día donde un feriado pudo haber corrido el plazo
 *                   (términos §6: el derecho es irrenunciable).
 *   - `fuera`     → se le avisa al usuario que el plazo venció y qué sí puede
 *                   hacer (la baja). No se toca nada.
 *
 * ── Invariantes ──
 *
 * Los del canje del token (un solo uso, uid del documento, anti-enumeración, el
 * crudo no se guarda) viven en `token-un-solo-uso.ts` y en `baja-por-mail.ts`,
 * y valen igual acá. Cada trámite usa SU colección de tokens: uno emitido para
 * la baja no se puede canjear como arrepentimiento, ni al revés.
 */

import { randomBytes as cryptoRandomBytes } from "crypto";

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";

import { MpClient, MpPreapproval, createMpClient } from "./client";
import { CAMPO_ARREPENTIDO, arrepentidoAtDe, reconcileSubscription } from "./reconcile";
import { runCancelMySubscription } from "./cancel-my-subscription";
import { ventanaDeThrottle } from "./baja-por-mail";
import { Plazo, evaluarPlazo } from "./plazo-arrepentimiento";
import { MP_PLANS_COLLECTION } from "./tier-mapping";
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

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

/** Colección de los tokens. CF-only: `firestore.rules` la cierra entera. */
export const ARREPENTIMIENTOS_POR_MAIL_COLLECTION = "mp_arrepentimientos_por_mail";

/**
 * El buzón del equipo. El mismo al que escribe la landing cuando algo falla y el
 * que usa el aviso de moderación. Si cambia, cambia acá.
 */
export const EQUIPO_MAILBOX = "treino@gettreino.com";

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * El código que emite la landing (`ARR-2026-0A1B2C`). Sólo esta forma exacta:
 * viaja al asunto de un mail, y un campo libre ahí sería un canal para escribirle
 * texto arbitrario a un tercero desde nuestro dominio.
 */
const CODE_SHAPE = /^ARR-\d{4}-[0-9A-F]{6}$/i;

/** Ruta de la página de confirmación, en la landing. */
const CONFIRM_PATH = "/es/arrepentimiento/confirmar";

/**
 * Estados de una suscripción que cuentan como «hubo contratación». Una
 * `pending` es un checkout que nadie completó: no hay nada de qué arrepentirse.
 */
const CONTRATADAS = new Set(["authorized", "paused", "cancelled"]);

export interface SolicitarArrepentimientoResult {
  status: "ok";
}
const OK: SolicitarArrepentimientoResult = { status: "ok" };

export type EstadoConfirmacionArrepentimiento =
  /** El token no tiene forma, o no existe. */
  | "invalido"
  /** Ya se canjeó. */
  | "ya-usado"
  /** Pasaron las 72 horas. */
  | "vencido"
  /** Dentro de plazo: se cortó la suscripción y el equipo devuelve el pago. */
  | "recibido"
  /** En el límite del plazo: NO se canceló nada, lo revisa una persona. */
  | "en-revision"
  /** Venció el plazo. No se toca nada. */
  | "fuera-de-plazo"
  /** No hay contratación de la que arrepentirse. El link sigue sirviendo. */
  | "sin-suscripcion"
  /** MP o la cola no contestaron. El link sigue sirviendo. */
  | "no-disponible";

export interface ConfirmarArrepentimientoResult {
  status: EstadoConfirmacionArrepentimiento;
  /** Último día del plazo, ISO. Sólo con `fuera-de-plazo`: la página lo muestra. */
  ultimoDiaIso?: string;
}

export interface SolicitarArrepentimientoDeps {
  nowMs: number;
  /** Inyectable: los tests fijan el token. Default `crypto.randomBytes`. */
  randomBytes?: (n: number) => Buffer;
}

export interface ConfirmarArrepentimientoDeps {
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
export function normalizarCodigoArrepentimiento(code: unknown): string | null {
  if (typeof code !== "string") return null;
  const c = code.trim();
  return CODE_SHAPE.test(c) ? c.toUpperCase() : null;
}

// ---------------------------------------------------------------------------
// La fecha de contratación
// ---------------------------------------------------------------------------

export interface Contrato {
  /** La suscripción de la que sale la fecha. */
  sub: MpPreapproval;
  /** Cuándo se contrató, en ms. `null` si MP no mandó una fecha que se entienda. */
  contratoMs: number | null;
}

/**
 * La contratación más reciente entre las suscripciones del usuario.
 *
 * La más reciente y no la primera: quien cambió de plan tiene un contrato nuevo,
 * y es de ése que se arrepiente. Si hubo pagos de contratos anteriores, el
 * aviso al equipo lista todas las suscripciones para que decida una persona.
 *
 * `null` si ninguna llegó a contratarse (todas `pending`).
 */
export function contratoMasReciente(subs: MpPreapproval[]): Contrato | null {
  let mejor: Contrato | null = null;
  for (const sub of subs) {
    if (typeof sub.status !== "string" || !CONTRATADAS.has(sub.status)) continue;
    const ms = typeof sub.date_created === "string" ? Date.parse(sub.date_created) : Number.NaN;
    const contratoMs = Number.isFinite(ms) ? ms : null;
    const gana =
      mejor === null ||
      (contratoMs !== null && (mejor.contratoMs === null || contratoMs > mejor.contratoMs));
    if (gana) mejor = { sub, contratoMs };
  }
  return mejor;
}

/** `auto_recurring.transaction_amount`, o `null`. */
function montoDe(sub: MpPreapproval): number | null {
  const monto = (sub.auto_recurring as { transaction_amount?: unknown } | undefined)
    ?.transaction_amount;
  return typeof monto === "number" && Number.isFinite(monto) ? monto : null;
}

/** `summarized.charged_quantity`: cuántos cobros lleva, o `null`. */
function cobrosDe(sub: MpPreapproval): number | null {
  const n = (sub.summarized as { charged_quantity?: unknown } | undefined)?.charged_quantity;
  return typeof n === "number" && Number.isFinite(n) ? n : null;
}

/**
 * TODOS los planes de la cuenta, terminales incluidos.
 *
 * ⚠️ NO es `planesQueCobran`, y la diferencia es el derecho entero. Aquella
 * excluye los planes terminales —los que ya se dieron de baja, o los que un
 * cambio de plan reemplazó— porque le sirve a la BAJA: no hay nada que cortar
 * ahí. Al arrepentimiento le sirve lo contrario. Quien se dio de baja el día 1
 * paga la baja con un plan terminal, y el día 5 tiene todo el derecho a
 * arrepentirse y que le devuelvan lo pagado: la baja NO devuelve plata. Con el
 * filtro de la baja, esa persona no recibía ni el mail. Y si algo fallaba a
 * mitad de camino, el reintento tampoco encontraba nada.
 *
 * Lo que decide si hay algo de qué arrepentirse no es el estado del plan sino
 * las suscripciones de Mercado Pago que cuelgan de él (ver
 * [contratoMasReciente]). Un plan que nunca cobró no aporta ninguna.
 */
async function planesDeLaCuenta(app: App, uid: string): Promise<{ planId: string }[]> {
  const snap = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .where("uid", "==", uid)
    .get();
  return snap.docs.map((d) => ({ planId: d.id }));
}

// ---------------------------------------------------------------------------
// La solicitud
// ---------------------------------------------------------------------------

/**
 * Pide el mail de confirmación.
 *
 * NUNCA tira y SIEMPRE devuelve `{status:"ok"}` — input basura incluido — por el
 * mismo motivo que `runSolicitarBajaPorMail`: cualquier rama que tire es una rama
 * que mañana alguien hace tirar distinto según exista o no la cuenta.
 */
export async function runSolicitarArrepentimientoPorMail(
  app: App,
  input: { email: unknown; code?: unknown },
  deps: SolicitarArrepentimientoDeps,
): Promise<SolicitarArrepentimientoResult> {
  if (typeof input?.email !== "string") return OK;
  const email = input.email.trim().toLowerCase();
  if (!EMAIL_SHAPE.test(email)) return OK;
  const code = normalizarCodigoArrepentimiento(input.code);

  try {
    const user = await getAuth(app).getUserByEmail(email);
    const uid = user.uid;

    // Todos los planes, no sólo los que pueden seguir cobrando (ver
    // `planesDeLaCuenta`). Sin ningún plan, un mail de «confirmá tu
    // arrepentimiento» prometería algo que la confirmación después no puede
    // hacer: ese caso lo cubre el canal manual.
    const planes = await planesDeLaCuenta(app, uid);
    if (planes.length === 0) {
      logger.info("arrepentimientoPorMail: sin plan, no se manda nada", { uid });
      return OK;
    }

    // Throttle ANTES de crear el token (ver `baja-por-mail.ts`).
    const scope = `${uid}_${ventanaDeThrottle(deps.nowMs)}`;
    const mailId = dedupeKey("withdrawal-confirm", scope, uid);
    const db = getFirestore(app);
    if ((await db.collection(MAIL_QUEUE_COLLECTION).doc(mailId).get()).exists) {
      logger.info("arrepentimientoPorMail: throttle, ya hay un mail en esta ventana", { uid });
      return OK;
    }

    const token = (deps.randomBytes ?? cryptoRandomBytes)(32).toString("base64url");
    const ref = db
      .collection(ARREPENTIMIENTOS_POR_MAIL_COLLECTION)
      .doc(hashToken(token));
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
      kind: "withdrawal-confirm",
      scope,
      params,
      // SIN prefKey: es la respuesta a un trámite que la persona acaba de
      // iniciar, no una novedad de producto que se pueda apagar.
    });

    if (queued === null) {
      // Perdió la carrera contra otro pedido de la misma ventana, o la cola
      // falló: este token no llega a ningún buzón. Se borra.
      await ref.delete().catch(() => undefined);
    }
  } catch (error: unknown) {
    // Se traga TODO, incluido user-not-found. Se loguea el código, nunca el mail.
    logger.info("arrepentimientoPorMail: no se encoló", {
      reason: (error as { code?: string }).code ?? "unknown",
    });
  }

  return OK;
}

// ---------------------------------------------------------------------------
// La confirmación
// ---------------------------------------------------------------------------

/**
 * Escribe el aviso al equipo. **Si falla, tira** — a diferencia de los mails al
 * usuario, que se pierden sin consecuencia.
 *
 * Va directo a la cola y no por `enqueueMail` por una razón que importa: éste
 * devuelve `null` tanto si el mail ya existía como si la cola falló, y acá esas
 * dos cosas son opuestas. Un aviso perdido después de haber cancelado la
 * suscripción es una devolución que nadie sabe que tiene que hacer.
 *
 * Es idempotente: un reintento del mismo token encuentra el documento
 * (`ALREADY_EXISTS`) y sigue.
 */
async function avisarAlEquipo(
  app: App,
  tokenId: string,
  uid: string,
  params: Record<string, string | number>,
  nowMs: number,
): Promise<void> {
  try {
    await getFirestore(app)
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(dedupeKey("withdrawal-team-notice", tokenId, uid))
      .create({
        toUid: "",
        toAddress: EQUIPO_MAILBOX,
        kind: "withdrawal-team-notice",
        params,
        status: "pending",
        attempts: 0,
        createdAt: Timestamp.fromMillis(nowMs),
      });
  } catch (error: unknown) {
    if ((error as { code?: number }).code === 6) return; // ya estaba
    throw error;
  }
}

/** Si esta suscripción llegó a contratarse (no es un checkout abandonado). */
const esContratada = (s: MpPreapproval): boolean =>
  typeof s.status === "string" && CONTRATADAS.has(s.status);

/**
 * Termina los beneficios de los planes cuya contratación más reciente está
 * dentro de SU propio plazo: los marca como arrepentidos y reconcilia para que
 * el derecho se escriba ya. Un plan anterior, dado de baja pero con días pagos,
 * no se marca ni se reconcilia: este trámite no devuelve esa contratación.
 *
 * ── Por qué es un marcador y no una escritura suelta ──
 *
 * El reconciliador corre de nuevo con cada evento de Mercado Pago y con el
 * barrido de las 03:00, y sin marcador cada vez volvería a calcular «cancelado,
 * con período hasta el día X» y a devolverle el acceso. Ver `arrepentidoAtDe`.
 *
 * **No pisa un marcador existente**: el momento del arrepentimiento es el de la
 * PRIMERA confirmación, no el del último reintento.
 *
 * ── ⚠️ El estado se lee POR ID, no por búsqueda ──
 *
 * Esto NO andaba en la primera versión, y se vio en producción: el corte quedó
 * escrito y el alumno siguió `active`. `/preapproval/search` —lo que usa el
 * reconciliador— devuelve el estado VIEJO justo después de cancelar. Medido en
 * el sandbox: a los 0 s la búsqueda decía `authorized` y la lectura por id
 * `cancelled`; recién a los 5 s coincidían. Como el marcador sólo vale con
 * `status === "cancelled"`, el reconciliador veía una suscripción viva y lo
 * ignoraba.
 *
 * La lectura por id es consistente, y acabamos de cancelar esa suscripción: se
 * la pasamos al reconciliador como `conocida`, que va primero que lo que traiga
 * la búsqueda. Mismo mecanismo que el del webhook (ver `conLaConocidaPrimero`).
 *
 * Si MP no contesta, tira: el marcador ya quedó escrito y el reintento del
 * usuario lo termina de aplicar.
 */
async function cortarElAcceso(
  app: App,
  contratadasPorPlan: Map<string, MpPreapproval[]>,
  deps: ConfirmarArrepentimientoDeps,
): Promise<void> {
  const db = getFirestore(app);
  for (const planId of contratadasPorPlan.keys()) {
    const ref = db.collection(MP_PLANS_COLLECTION).doc(planId);
    if (arrepentidoAtDe((await ref.get()).data()) === null) {
      await ref.set({ [CAMPO_ARREPENTIDO]: deps.nowMs }, { merge: true });
    }
  }
  for (const [planId, subs] of contratadasPorPlan) {
    // La más reciente del plan: es la que el reconciliador mira (`subs[0]`).
    const id = contratoMasReciente(subs)?.sub.id;
    const fresca =
      typeof id === "string" && id !== "" ? await deps.mpClient.getPreapproval(id) : undefined;

    const r = await reconcileSubscription(app, planId, deps, fresca);
    if (r.outcome === "error-mp") {
      throw new Error(`no se pudo aplicar el corte al plan ${planId}`);
    }
  }
}

/**
 * Canjea el link y resuelve el arrepentimiento.
 *
 * El uid SALE DEL DOCUMENTO DEL TOKEN; el request trae un token y nada más.
 */
export async function runConfirmarArrepentimientoPorMail(
  app: App,
  input: { token: unknown },
  deps: ConfirmarArrepentimientoDeps,
): Promise<ConfirmarArrepentimientoResult> {
  const token = input?.token;
  if (typeof token !== "string" || !TOKEN_SHAPE.test(token)) {
    return { status: "invalido" };
  }

  const db = getFirestore(app);
  const ref = db.collection(ARREPENTIMIENTOS_POR_MAIL_COLLECTION).doc(hashToken(token));
  const claimId = cryptoRandomBytes(8).toString("hex");

  const reclamo = await reclamarToken(app, ref, deps.nowMs, claimId);
  if (!reclamo.ok) return { status: reclamo.status };
  const { uid, code } = reclamo;

  /** Libera el link: no pasó nada irreversible, que pueda reintentar. */
  const liberar = async (status: "no-disponible" | "sin-suscripcion") => {
    await liberarReclamo(app, ref, reclamo.claimId);
    return { status } as const;
  };

  try {
    // ── 1. Qué contrató, según Mercado Pago ──
    const planes = await planesDeLaCuenta(app, uid);
    const todas: MpPreapproval[] = [];
    /** Las contrataciones de cada plan que tiene alguna. */
    const planesConContrato = new Map<string, MpPreapproval[]>();
    for (const { planId } of planes) {
      // Secuencial, como el resto: en paralelo son N requests a MP y contesta 429.
      const subs = await deps.mpClient.searchPreapprovalsByPlan(planId);
      todas.push(...subs);
      const contratadasDelPlan = subs.filter(esContratada);
      if (contratadasDelPlan.length > 0) planesConContrato.set(planId, contratadasDelPlan);
    }

    const contrato = contratoMasReciente(todas);
    if (contrato === null) {
      // ⚠️ Se LIBERA el link. El índice de búsqueda de MP tarda en incluir una
      // suscripción recién creada (medido: ~90 s), y el arrepentimiento es un
      // derecho irrenunciable: quemar el link sobre un «no encontré nada» que
      // era sólo demora dejaría a la persona sin salida.
      return await liberar("sin-suscripcion");
    }

    // ── 2. ¿Llega a tiempo? ──
    const plazo: Plazo = evaluarPlazo(contrato.contratoMs, deps.nowMs);
    const ultimoDiaIso =
      plazo.ultimoDiaMs === null ? undefined : new Date(plazo.ultimoDiaMs).toISOString();
    const contratoIso =
      contrato.contratoMs === null ? "" : new Date(contrato.contratoMs).toISOString();

    const contratadas = todas.filter(esContratada);
    const monto = montoDe(contrato.sub);
    const cobros = cobrosDe(contrato.sub);
    const email = await getAuth(app)
      .getUser(uid)
      .then((u) => u.email ?? "")
      .catch(() => "");

    // El resto prepago de un plan anterior NO se corta con el arrepentimiento
    // (ver `reconcile.ts`): es plata YA PAGADA que este pedido no devuelve. Pero
    // si el equipo decide devolverla también, tiene que saber que existe.
    const subActual = (await db.collection("users").doc(uid).get()).data()?.subscription as
      | { prepaidTier?: unknown; prepaidUntil?: { toMillis?: () => number } }
      | undefined;
    const pisoHastaMs = subActual?.prepaidUntil?.toMillis?.();
    const piso: Record<string, string> =
      typeof subActual?.prepaidTier === "string" &&
      typeof pisoHastaMs === "number" &&
      pisoHastaMs > deps.nowMs
        ? { pisoTier: subActual.prepaidTier, pisoHastaIso: new Date(pisoHastaMs).toISOString() }
        : {};

    const datosDelAviso = (estado: "dentro" | "a-revisar", canceladas: number) => ({
      estado,
      ...(code ? { code } : {}),
      email,
      uid,
      contratoIso,
      ...(plazo.diasTranscurridos === null ? {} : { diasTranscurridos: plazo.diasTranscurridos }),
      ...(ultimoDiaIso ? { ultimoDiaIso } : {}),
      ...(monto === null ? {} : { monto }),
      ...(cobros === null ? {} : { cobros }),
      suscripciones: contratadas
        .map((s) => (typeof s.id === "string" ? s.id : ""))
        .filter(Boolean)
        .join(", "),
      canceladas,
      ...piso,
    });

    // ── 3a. Venció: se avisa y no se toca nada ──
    if (plazo.estado === "fuera") {
      await ref.update({ resultado: "fuera-de-plazo" }).catch(() => undefined);
      await enqueueMail(app, {
        toUid: uid,
        kind: "withdrawal-expired",
        scope: ref.id,
        params: { ...(code ? { code } : {}), ...(ultimoDiaIso ? { ultimoDiaIso } : {}) },
      });
      return { status: "fuera-de-plazo", ...(ultimoDiaIso ? { ultimoDiaIso } : {}) };
    }

    // ── 3b. En el límite: NO se cancela, decide una persona ──
    if (plazo.estado === "a-revisar") {
      await avisarAlEquipo(app, ref.id, uid, datosDelAviso("a-revisar", 0), deps.nowMs);
      await ref.update({ resultado: "en-revision" }).catch(() => undefined);
      await enqueueMail(app, {
        toUid: uid,
        kind: "withdrawal-received",
        scope: ref.id,
        params: { ...(code ? { code } : {}), revision: "1" },
      });
      return { status: "en-revision" };
    }

    // El plazo global lo decide la contratación más reciente de la cuenta, pero
    // el corte se decide PLAN POR PLAN. Si A se dio de baja hace 40 días y aún
    // tiene período pago, y B se contrató hace 2, marcar A le quitaría días que
    // este trámite no devuelve. `contrato` sale de estas mismas listas: como su
    // plazo es `dentro`, el plan que disparó esta rama queda incluido siempre.
    const planesDentroDePlazo = new Map<string, MpPreapproval[]>();
    for (const [planId, subs] of planesConContrato) {
      const delPlan = contratoMasReciente(subs);
      if (
        delPlan !== null &&
        evaluarPlazo(delPlan.contratoMs, deps.nowMs).estado === "dentro"
      ) {
        planesDentroDePlazo.set(planId, subs);
      }
    }

    // ── 3c. Dentro de plazo: se corta la suscripción y se avisa al equipo ──
    const baja = await runCancelMySubscription(app, uid, deps);
    if (baja.estado === "no-disponible" || baja.enfriando === true) {
      // MP no contestó, o hay otra baja del mismo usuario hace menos de 10 s. No
      // se avisó nada al equipo, así que el reintento arranca de cero.
      return await liberar("no-disponible");
    }

    // ── El orden importa: primero la OBLIGACIÓN, después el corte ──
    //
    // 1. El aviso al equipo. Es lo que registra que hay que devolver plata, y es
    //    lo que no se puede perder: si falla, el link se libera y el reintento
    //    encuentra la suscripción ya cancelada (`sin-suscripcion`, no es error)
    //    y vuelve a intentarlo.
    // 2. El corte del acceso. Los beneficios terminan en el momento en que se
    //    confirma, porque se devuelve todo lo pagado. Es idempotente y
    //    reintentable: el marcador queda en el plan y cualquier reconciliación
    //    posterior —el evento de MP por esta misma cancelación, o el barrido— lo
    //    respeta.
    await avisarAlEquipo(app, ref.id, uid, datosDelAviso("dentro", baja.canceladas ?? 0), deps.nowMs);
    // Los planes viejos no se reconcilian acá: la baja ya reconcilió los que
    // seguían vivos, y volver a visitar uno fuera de plazo sólo podría tocar un
    // derecho pago que este arrepentimiento debe conservar.
    await cortarElAcceso(app, planesDentroDePlazo, deps);
    await ref
      .update({ resultado: "recibido", canceladas: baja.canceladas ?? 0 })
      .catch(() => undefined);
    await enqueueMail(app, {
      toUid: uid,
      kind: "withdrawal-received",
      scope: ref.id,
      params: code ? { code } : {},
    });
    return { status: "recibido" };
  } catch (error: unknown) {
    logger.error("arrepentimientoPorMail: reventó", { uid, error: String(error) });
    return await liberar("no-disponible");
  }
}

// ---------------------------------------------------------------------------
// onCall wrappers
//
// SIN `enforceAppCheck`, por el mismo motivo que los de la baja: los llama la
// landing (el primero desde su servidor, el segundo desde la página de
// confirmación), que no tiene Firebase ni App Check, y el art. 4 de la 954/2025
// prohíbe exigir registración previa. Lo que los cierra es que `solicitar` sólo
// puede mandarle un mail al DUEÑO del buzón, con throttle, sin revelar nada, y
// `confirmar` sólo actúa con un token de 256 bits que únicamente llegó a ese
// buzón. La exención está declarada en `__tests__/appcheck-enforcement.test.ts`.
// ---------------------------------------------------------------------------

/** Callable: pedir el link de arrepentimiento. Público, a propósito. */
export const solicitarArrepentimientoPorMail = functions.onCall(
  { region: "southamerica-east1", maxInstances: 5 },
  async (request): Promise<SolicitarArrepentimientoResult> => {
    const data = (request.data ?? {}) as { email?: unknown; code?: unknown };
    return runSolicitarArrepentimientoPorMail(
      ensureApp(),
      { email: data.email, code: data.code },
      { nowMs: Date.now() },
    );
  },
);

/** Callable: canjear el link. Público; la credencial es el token. */
export const confirmarArrepentimientoPorMail = functions.onCall(
  { region: "southamerica-east1", maxInstances: 5, secrets: [MP_ACCESS_TOKEN] },
  async (request): Promise<ConfirmarArrepentimientoResult> => {
    const data = (request.data ?? {}) as { token?: unknown };
    return runConfirmarArrepentimientoPorMail(ensureApp(), { token: data.token }, {
      mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
      nowMs: Date.now(),
    });
  },
);
