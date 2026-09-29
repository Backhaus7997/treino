/**
 * trainer-limit-mail.ts — el mail al PF que chocó un tope de su plan:
 * ejercicios propios (limite-ejercicios-pf.md, §3 PR4) o plantillas
 * (limite-plantillas-pf.md, §3 PR4).
 *
 * GENERALIZADO POR `kind`: cada tope tiene su propia clave de `planLimits`,
 * su propio campo de uso y su propio `MailKind`, todo en `CAMPOS_POR_KIND`
 * más abajo. El resto del módulo —las cuatro cláusulas, la ventana, el
 * enfriamiento— es idéntico para los dos, porque son la MISMA pregunta
 * ("¿sigue en el tope, y hace cuánto que no le avisamos?") sobre datos
 * distintos.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUE HACE FALTA UN MAIL
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * El PF que choca el tope desde el teléfono no tiene forma de enterarse ahí de
 * dónde se paga: el móvil sólo informa el ESTADO (E8 del plan), sin botón, sin
 * "web", sin "pasá a un plan" — mismo criterio que sostiene
 * `plan_limit_paywall.dart` desde el #1141. Sin este mail, ese funnel no tiene
 * por dónde salir. En la web el aviso SÍ lleva botón, así que este mail no es
 * el ÚNICO canal para todos, pero sí lo es para quien entró por el teléfono.
 *
 * Calcado de `free-limit-mail.ts` (#1149): estructura, horario relativo,
 * ventana de 36 horas y enfriamiento de 14 días. Difiere en UNA cosa: la
 * cláusula 3 no depende de una query aparte ("¿ya paga?") sino de los MISMOS
 * dos campos que la regla equivalente ya lee para cada tope —
 * `planLimits.<clave>` y `<campo de uso>.count`, ver `CAMPOS_POR_KIND` — así
 * que la decisión entera es pura sobre el documento de `users/{uid}`, sin una
 * segunda lectura.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  LAS CUATRO CLAUSULAS DEL SILENCIO (idénticas en espíritu a free-limit-mail)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   1. **Sin anotación → silencio.** `trainerLimitHitAt` no existe: el PF
 *      nunca chocó el tope, o el cliente todavía no lo anotó.
 *
 *   2. **Anotación vieja → silencio.** El mail vale porque llega CERCA del
 *      intento (ventana de 36 h, igual razón que en `free-limit-mail.ts`).
 *
 *   3. **Ya no está en el tope → silencio.** `count < limit`, o el `planLimits`
 *      del tope que chocó es `null`/ausente (sin tope, interruptor apagado, o
 *      el PF subió de plan y el barrido de las 04:00 ya lo reflejó).
 *      Escribirle "hay una salida" a quien ya la tiene es el mismo error caro
 *      que documenta `free-limit-mail.ts`.
 *
 *   4. **Enfriamiento de 14 días → silencio.** Un PF que sigue en el tope
 *      todos los días —porque no quiere pagar más, no porque no se dio
 *      cuenta— recibiría un mail diario sobre lo mismo sin esto.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL prefKey
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Este mail LE OFRECE un plan más caro a alguien que ya es cliente — es
 * comunicación comercial, no un aviso operativo. Mismo razonamiento textual
 * que `athlete-prospect-mail.ts` §"EL prefKey, Y POR QUE ESTE MAIL SI LO
 * LLEVA": `docs/legal/politica-de-privacidad.md` promete que para esas «la
 * oposición es ABSOLUTA». Reusa el MISMO valor de clave que
 * `ATHLETE_PROSPECT_PREF_KEY` ("novedades_plan") en vez de definir uno nuevo:
 * es la misma categoría de mensaje —novedades sobre el plan propio— y la
 * clave no está namespaceada por rol en ningún otro lugar del repo (el campo
 * vive en `notificationPrefs`, un mapa plano en `users/{uid}` que ya es
 * exclusivo de UN documento con UN rol). Compartir el string no puede generar
 * una colisión entre dos personas, y sí evita que el día que un `athlete` se
 * promueva a `trainer` (aprovisionamiento manual, ver comentario de
 * `firestore.rules` sobre `subscription`) pierda una preferencia que ya
 * había fijado sobre el mismo tipo de contenido.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  DOS CAMINOS: AL TOQUE, Y EL BARRIDO DE LAS 05:30 COMO RED
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Calcado de `free-limit-mail.ts` (#1149, y el trigger del 2026-09-25): el
 * camino principal es `sendTrainerLimitMailOnHit`, un trigger sobre
 * `users/{uid}` que encola apenas el cliente anota `trainerLimitHitAt`. El
 * mail sale en segundos, mientras el PF todavía tiene la pantalla del tope
 * delante.
 *
 * **`sweepTrainerLimitMail` se queda, como red.** Si el trigger falla, el
 * barrido lo reintenta al otro día dentro de la ventana de 36 h. Los dos
 * caminos no se pisan y no pueden producir un mail doble: comparten el mismo
 * enfriamiento de 14 días (`trainerLimitMailAt`, cláusula 4), y ESE campo es
 * lo único que impide el doble mail — no la dedupe de la cola, que dedupea
 * por `kind` + `scope` + destinatario y con DOS `kind` distintos
 * (`exercise-limit-reached` / `template-limit-reached`) no ve nada en común.
 * Un PF que choca los dos topes casi al mismo tiempo dispara dos escrituras
 * de `trainerLimitHitAt`/`trainerLimitHitKind` con `kind` distinto, y si cada
 * camino DECIDIERA sobre su propio snapshot y anotara el enfriamiento RECIÉN
 * DESPUÉS de encolar, los dos pasarían las cuatro cláusulas antes de que
 * cualquiera alcance a escribir `trainerLimitMailAt` — dos mails, no uno.
 * Por eso `enqueueTrainerLimitMail` no decide sobre el snapshot que trae el
 * llamador: RELEE `users/{uid}` y decide DENTRO de una transacción de
 * Firestore, que también hace la reserva (escribe `trainerLimitMailAt`) antes
 * de encolar. Firestore serializa las transacciones que chocan sobre el mismo
 * documento, así que la segunda de las dos siempre ve la reserva de la
 * primera y sale por la cláusula 4. Si el encolado post-transacción falla de
 * verdad, la reserva se deshace (ver el docstring de `enqueueTrainerLimitMail`)
 * para no dejar un enfriamiento anotado sin mail alguno atrás.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL ANTI-LOOP DEL CAMINO AL TOQUE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `enqueueTrainerLimitMail` escribe `trainerLimitMailAt` en el MISMO documento
 * que dispara el trigger. Esa escritura lo despertaría de nuevo si no se
 * filtrara: `esToqueNuevo` (calcado de `free-limit-mail.ts`) sólo devuelve
 * `true` cuando CAMBIA `trainerLimitHitAt` — la escritura del enfriamiento
 * deja ese campo igual, así que sale sin encolar nada. Cualquier otra
 * escritura del perfil (nombre, foto, preferencias) también sale ahí, sin
 * costo.
 *
 * El chequeo de `role == 'trainer'` es una red de más, en memoria: mismo
 * criterio defensivo que ya usa `barrerLimiteDeEjercicios` para el barrido —
 * `trainerLimitHitAt` sólo lo escribe el flujo del PF, así que en la práctica
 * ya es exclusivo de `trainer`, pero el chequeo no cuesta una query extra.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL HORARIO DEL BARRIDO — 05:30 ART
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Después del barrido de las 04:00 (`sweepEntitlements`, que recalcula
 * `planLimits`/`customExerciseUsage` para todo PF) y después de
 * `sweepAthletePaywall`/`sweepFreeLimitMail`, que corren a las 04:30 y 05:00.
 * Ese orden importa por la cláusula 3: correr ANTES del barrido de las 04:00
 * dejaría a este mail decidiendo sobre el `planLimits` de ayer para quien
 * cambió de plan durante la noche. Verificado contra el resto de los
 * schedules del repo (`rg 'schedule:' functions/src`) — no hay otro a las
 * 05:30.
 */

import { App } from "firebase-admin/app";
import {
  DocumentData,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

import { dedupeKey, enqueueMail } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION } from "../mail/types";
import { artDateKey } from "../mail/format";
import { trainerWebCheckout } from "../mail/templates";

/** El campo que anota el cliente al rebotar contra el tope (PR3, plan §2). */
export const CAMPO_TOPE_AT = "trainerLimitHitAt";
/** Qué tope se tocó: `"customExercises"` o `"templates"`. */
export const CAMPO_TOPE_KIND = "trainerLimitHitKind";
/**
 * Cuándo se le escribió por última vez. Lo escribe este módulo.
 *
 * COMPARTIDO entre los dos topes a propósito (limite-plantillas-pf.md §3
 * PR4): un PF que choca los dos en la misma ventana recibe UN mail cada 14
 * días, no uno por tope. El problema que el enfriamiento evita es el spam,
 * no "qué tope fue".
 */
export const CAMPO_MAIL_AT = "trainerLimitMailAt";

/**
 * Qué mirar en `users/{uid}` para cada valor posible de `trainerLimitHitKind`.
 *
 * Un kind que no está acá (ausente, corrupto, o un valor que todavía no
 * existe) NO cae a `customExercises` — revisado por Codex (hilo
 * `01a0d934-760f-7763-9948-ba9bb43fe98a`): con UN solo tope posible,
 * "no sé cuál" y "es el único que existe" eran la misma cosa, pero con DOS
 * dejaron de serlo. Adivinar `customExercises` para un PF que en realidad
 * chocó `templates` manda un mail que dice una mentira concreta — "llegaste
 * al tope de EJERCICIOS"—, y es el mismo error que AGENTS.md §11.1 marca
 * como peor que no decir nada. `decideTrainerLimitMail` falla CERRADO (sin
 * mail) para cualquier kind que esta tabla no reconoce.
 */
interface CamposDelTope {
  /** Clave dentro de `planLimits`. */
  limitField: "customExercises" | "templates";
  /** Campo del doc del usuario con `{count: number}`. */
  usageField: "customExerciseUsage" | "templateUsage";
  /** El `MailKind` que corresponde a este tope. */
  mailKind: TrainerLimitMailKind;
}

export type TrainerLimitMailKind = "exercise-limit-reached" | "template-limit-reached";

const CAMPOS_POR_KIND: Record<string, CamposDelTope> = {
  customExercises: {
    limitField: "customExercises",
    usageField: "customExerciseUsage",
    mailKind: "exercise-limit-reached",
  },
  templates: {
    limitField: "templates",
    usageField: "templateUsage",
    mailKind: "template-limit-reached",
  },
};

/** Ver el encabezado — "EL prefKey". Mismo valor que `athlete-prospect-mail.ts`. */
export const TRAINER_LIMIT_PREF_KEY = "novedades_plan";

/** Ventana de la cláusula 2. Misma razón que `free-limit-mail.ts`. */
export const VENTANA_MS = 36 * 60 * 60 * 1000;

/** Enfriamiento de la cláusula 4. Mismo valor y mismo motivo que su hermano. */
export const ENFRIAMIENTO_MS = 14 * 24 * 60 * 60 * 1000;

export interface TrainerLimitMailPlan {
  kind: TrainerLimitMailKind;
  scope: string;
  tope: string;
  /** El tope numérico vigente. Siempre un número: ver `sigueEnElTope`. */
  limit: number;
}

/** Lee un `Timestamp` de Firestore sin confiar en su forma. */
function msDe(valor: unknown): number | null {
  const c = valor as { toMillis?: unknown } | null | undefined;
  if (c == null || typeof c.toMillis !== "function") return null;
  const ms = (c.toMillis as () => number)();
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Si el PF SIGUE en el tope ahora mismo — la cláusula 3.
 *
 * Lee los MISMOS dos campos que la regla equivalente en `firestore.rules`
 * (`customExerciseQuotaOk` o `templateQuotaOk`, según `campos`), y con la
 * MISMA semántica: `limit` no numérico (null, ausente, o corrupto) es SIN
 * TOPE — nunca "sigue en el tope". `count < limit` es "ya no está" —
 * `count >= limit` es lo único que mantiene el mail vivo (E6: en el tope
 * exacto SÍ cuenta como "en el tope", porque ahí es donde el próximo create
 * rebota).
 *
 * Devuelve el límite ya angosto a `number` para que el productor no tenga que
 * repetir el chequeo de tipo.
 */
function sigueEnElTope(
  userData: DocumentData | undefined,
  campos: CamposDelTope,
): number | null {
  const limit = (userData?.planLimits as Record<string, unknown> | undefined)?.[
    campos.limitField
  ];
  if (typeof limit !== "number" || !Number.isFinite(limit)) return null;

  const countRaw = (userData?.[campos.usageField] as { count?: unknown } | undefined)
    ?.count;
  const count = typeof countRaw === "number" && Number.isFinite(countRaw) ? countRaw : 0;

  return count >= limit ? limit : null;
}

/**
 * Si corresponde escribirle a este PF, y con qué alcance de dedupe.
 *
 * PURA: no toca Firestore. Sin segunda query — a diferencia de
 * `free-limit-mail.ts`, que necesita `hasActiveTrainerLink`, acá no hay nada
 * más que consultar: la cláusula 3 ya está resuelta con lo que trae el
 * documento.
 *
 * @param userData - El documento de `users/{uid}`.
 * @param nowMs    - Reloj, inyectado.
 */
export function decideTrainerLimitMail(
  userData: DocumentData | undefined,
  nowMs: number,
): TrainerLimitMailPlan | null {
  const tocadoMs = msDe(userData?.[CAMPO_TOPE_AT]);
  if (tocadoMs === null) return null; // clausula 1

  // El mail vale porque llega CERCA del intento. Ver la clausula 2.
  if (nowMs - tocadoMs > VENTANA_MS) return null;

  const topeRaw = userData?.[CAMPO_TOPE_KIND];
  const tope = typeof topeRaw === "string" && topeRaw ? topeRaw : "desconocido";
  const campos = CAMPOS_POR_KIND[tope];
  if (!campos) return null; // kind sin reconocer: no sabemos que tope mirar

  const limit = sigueEnElTope(userData, campos);
  if (limit === null) return null; // clausula 3

  // EL ENFRIAMIENTO. Ver la clausula 4: sin esto, un PF que sigue en el tope
  // todos los dias recibe un mail diario sobre lo mismo.
  const ultimoMs = msDe(userData?.[CAMPO_MAIL_AT]);
  if (ultimoMs !== null && nowMs - ultimoMs < ENFRIAMIENTO_MS) return null;

  return {
    kind: campos.mailKind,
    scope: `tope_${artDateKey(nowMs)}`,
    tope,
    limit,
  };
}

/** Lo que devuelve la reserva: el plan a mandar y el enfriamiento previo. */
interface Reserva {
  plan: TrainerLimitMailPlan;
  /** `trainerLimitMailAt` ANTES de esta reserva. `null` si no había. */
  anteriorMailAtMs: number | null;
}

/**
 * Relee `users/{uid}` FRESCO dentro de una transacción, decide, y si
 * corresponde mandar, RESERVA el enfriamiento ahí mismo (escribe
 * `trainerLimitMailAt = nowMs`) antes de que nadie encole nada.
 *
 * Esta es la pieza que cierra la carrera entre los dos `kind` (ver el
 * encabezado del módulo — "DOS CAMINOS"): dos transacciones sobre el MISMO
 * documento se serializan, así que la segunda de las dos siempre ve la
 * reserva que dejó la primera y sale por la cláusula 4 (`decideTrainerLimitMail`
 * devuelve `null`), sin importar qué snapshot tenía el llamador al entrar.
 *
 * Devuelve `null` cuando `decideTrainerLimitMail` dice que no corresponde —
 * ninguna de las cuatro cláusulas se cumple, o esta transacción perdió la
 * carrera contra otra.
 */
async function reservarEnfriamiento(
  app: App,
  trainerId: string,
  nowMs: number,
): Promise<Reserva | null> {
  const ref = getFirestore(app).collection("users").doc(trainerId);
  return getFirestore(app).runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const datosFrescos = snap.data();

    const plan = decideTrainerLimitMail(datosFrescos, nowMs);
    if (!plan) return null;

    const anteriorMailAtMs = msDe(datosFrescos?.[CAMPO_MAIL_AT]);
    tx.set(ref, { [CAMPO_MAIL_AT]: Timestamp.fromMillis(nowMs) }, { merge: true });
    return { plan, anteriorMailAtMs };
  });
}

/**
 * Deshace una reserva que quedó sin mail detrás (el encolado falló de
 * verdad). Vuelve `trainerLimitMailAt` a `anteriorMailAtMs` (o lo borra si no
 * había ninguno) — PERO sólo si el campo sigue valiendo exactamente `nowMs`,
 * es decir, sólo si sigue siendo ESTA reserva. Si otra transacción posterior
 * ya volvió a chocar el tope y reservó de nuevo, `trainerLimitMailAt` ya no es
 * `nowMs` y este rollback no toca nada — pisar esa reserva más nueva
 * silenciaría un mail que sí va a salir.
 */
async function deshacerReserva(
  app: App,
  trainerId: string,
  nowMs: number,
  anteriorMailAtMs: number | null,
): Promise<void> {
  const ref = getFirestore(app).collection("users").doc(trainerId);
  await getFirestore(app).runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const actualMs = msDe(snap.data()?.[CAMPO_MAIL_AT]);
    if (actualMs !== nowMs) return; // ya no es esta reserva, no tocar

    if (anteriorMailAtMs === null) {
      tx.update(ref, { [CAMPO_MAIL_AT]: FieldValue.delete() });
    } else {
      tx.set(
        ref,
        { [CAMPO_MAIL_AT]: Timestamp.fromMillis(anteriorMailAtMs) },
        { merge: true },
      );
    }
  });
}

/**
 * El camino común del trigger y del barrido: decide, reserva, encola, y
 * deshace la reserva si el encolado falló de verdad.
 *
 * ORDEN (invertido respecto de una versión anterior de este módulo, que
 * anotaba el enfriamiento DESPUÉS de encolar — ver "DOS CAMINOS" en el
 * encabezado para el porqué):
 *
 *   1. `reservarEnfriamiento` relee el documento FRESCO dentro de una
 *      transacción, decide con `decideTrainerLimitMail`, y si corresponde
 *      mandar, escribe `trainerLimitMailAt = nowMs` ahí mismo — la reserva.
 *      Si no corresponde (cualquiera de las cuatro cláusulas, incluyendo
 *      haber perdido la carrera contra otra reserva), no hay nada más que
 *      hacer.
 *   2. Con la reserva ya firme, se encola con `enqueueMail`. Nunca tira:
 *      devuelve `null` tanto si el mail YA estaba en la cola (reintento del
 *      barrido, sano) como si la escritura FALLÓ. Ante un `null`, se mira la
 *      cola: si el documento está, todo bien — la reserva queda como está.
 *   3. Si el documento NO está (el encolado falló de verdad), la reserva
 *      quedó sin mail detrás: `deshacerReserva` la revierte —para que el
 *      próximo choque del tope no encuentre un enfriamiento anotado sobre un
 *      mail que nunca salió— y se tira, para que el barrido lo cuente como
 *      fallido.
 *
 * Tirar NO garantiza un reintento. El barrido es diario y la ventana es de
 * 36 h, así que la corrida de mañana sólo vuelve a ver los topes que hoy
 * tienen menos de 12 h. Uno más viejo sale de la query y no se reintenta: el
 * mail llega recién si el PF vuelve a chocar un tope. Se aceptó así porque la
 * falla es rara y el mail es comercial.
 *
 * @returns el plan que se mandó, o `null` si no correspondía mandar nada.
 */
export async function enqueueTrainerLimitMail(
  app: App,
  trainerId: string,
  nowMs: number,
): Promise<TrainerLimitMailPlan | null> {
  const reserva = await reservarEnfriamiento(app, trainerId, nowMs);
  if (!reserva) return null;
  const { plan, anteriorMailAtMs } = reserva;

  const queuedId = await enqueueMail(app, {
    toUid: trainerId,
    kind: plan.kind,
    scope: plan.scope,
    prefKey: TRAINER_LIMIT_PREF_KEY,
    params: {
      tope: plan.tope,
      limit: plan.limit,
      ctaUrl: trainerWebCheckout(),
    },
  });

  if (queuedId === null) {
    const enCola = await getFirestore(app)
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(dedupeKey(plan.kind, plan.scope, trainerId))
      .get();
    if (!enCola.exists) {
      await deshacerReserva(app, trainerId, nowMs, anteriorMailAtMs);
      throw new Error("trainer-limit-mail: no se pudo encolar el mail");
    }
  }

  return plan;
}

export interface ResultadoDelBarrido {
  candidatos: number;
  enviados: number;
}

/**
 * Le escribe a los PF que chocaron un tope de su plan —ejercicios propios o
 * plantillas— y siguen ahí. `enqueueTrainerLimitMail` es quien decide —relee
 * el documento fresco dentro de una transacción— cuál tope mirar según
 * `CAMPO_TOPE_KIND`; acá sólo se filtra por `role` antes de intentarlo.
 *
 * ── La query, y por que trae tan poco ──
 *
 * `trainerLimitHitAt >= hace 36hs`, igual criterio que `free-limit-mail.ts`:
 * el campo sólo existe en quien chocó el tope, y la ventana lo acota a ayer.
 * No hace falta índice compuesto — Firestore indexa cada campo por su cuenta.
 *
 * ── Por que se revisa el rol acá y no en la query ──
 *
 * `trainerLimitHitAt` sólo lo escribe el flujo del PF (`registrarTopeDelPlanPf`,
 * el tramo siguiente), así que en la práctica el campo es exclusivo de
 * `trainer`. El chequeo es una red de más, en memoria y sin costo de query
 * extra, por si algún día ese supuesto deja de sostenerse — mismo criterio
 * defensivo que `custom-exercise-count.ts` aplica antes de recontar. Se lee
 * del snapshot de la query, no fresco — es sólo un filtro previo; la decisión
 * que importa (las cuatro cláusulas) la hace `enqueueTrainerLimitMail` sobre
 * el documento fresco.
 *
 * ── Un fallo no frena a los demás ──
 *
 * Mismo criterio que `barrerTopesTocados`: un documento raro no puede dejar
 * sin mail a toda la cola.
 */
export async function barrerLimiteDeEjercicios(
  app: App,
  nowMs: number = Date.now(),
  logger: { info: (m: string, d?: unknown) => void; error: (m: string, d?: unknown) => void } = console,
): Promise<ResultadoDelBarrido> {
  const desde = Timestamp.fromMillis(nowMs - VENTANA_MS);
  const snap = await getFirestore(app)
    .collection("users")
    .where(CAMPO_TOPE_AT, ">=", desde)
    .get();

  let enviados = 0;
  for (const doc of snap.docs) {
    try {
      const data = doc.data();
      if (data.role !== "trainer") continue;

      const plan = await enqueueTrainerLimitMail(app, doc.id, nowMs);
      if (plan) enviados++;
    } catch (err) {
      logger.error("trainer-limit-mail: fallo un PF", { uid: doc.id, err });
    }
  }

  return { candidatos: snap.size, enviados };
}

/** Qué hizo el trigger con una escritura de `users/{uid}`. Para el log. */
export type ResultadoAlToque =
  | "sin-tope-nuevo"
  | "no-trainer"
  | "silencio"
  | "encolado";

/**
 * Si esta escritura es un tope NUEVO: `trainerLimitHitAt` aparece o cambia.
 *
 * ⚠️ **Es lo que evita el loop.** `enqueueTrainerLimitMail` escribe
 * `trainerLimitMailAt` en el MISMO documento que dispara el trigger. Esa
 * escritura vuelve a despertarlo, pero deja `trainerLimitHitAt` igual, así
 * que sale acá. Lo mismo con cualquier otra escritura del perfil —nombre,
 * foto, preferencias—, que son la enorme mayoría de las que llegan. Calcado
 * de `esToqueNuevo` en `free-limit-mail.ts`.
 */
export function esToqueNuevo(
  antes: DocumentData | undefined,
  despues: DocumentData | undefined,
): boolean {
  const despuesMs = msDe(despues?.[CAMPO_TOPE_AT]);
  if (despuesMs === null) return false;
  return despuesMs !== msDe(antes?.[CAMPO_TOPE_AT]);
}

/**
 * El camino al toque: las mismas cuatro cláusulas que el barrido, para UN PF,
 * en el momento en que choca el tope.
 *
 * El chequeo de `role` va acá y no en la query del trigger (que no existe:
 * `onDocumentUpdated` no filtra por campo) — es la misma red defensiva que
 * `barrerLimiteDeEjercicios` aplica en memoria, sin costo de query extra. Se
 * lee de `despues`, el snapshot que trajo el evento — sólo un filtro previo;
 * la decisión que importa la hace `enqueueTrainerLimitMail` releyendo el
 * documento fresco dentro de una transacción. Ver el encabezado — "EL
 * ANTI-LOOP DEL CAMINO AL TOQUE" y "DOS CAMINOS".
 */
export async function alTocarElTope(
  app: App,
  uid: string,
  antes: DocumentData | undefined,
  despues: DocumentData | undefined,
  nowMs: number,
): Promise<ResultadoAlToque> {
  if (!esToqueNuevo(antes, despues)) return "sin-tope-nuevo";
  if (despues?.role !== "trainer") return "no-trainer";

  const plan = await enqueueTrainerLimitMail(app, uid, nowMs);
  return plan ? "encolado" : "silencio";
}

/**
 * El mail al toque. Ver «DOS CAMINOS» en el encabezado.
 *
 * `onDocumentUpdated` y no `Written`: la anotación sale de
 * `registrarTopeDelPlanPf` sobre un `users/{uid}` que ya existe —el PF ya
 * tiene sesión—, así que un alta nunca trae un tope.
 *
 * Un fallo se loguea y no se relanza. Relanzar no reintentaría (el trigger no
 * tiene `retry`), y la red para ese caso ya existe: el barrido de las 05:30.
 */
export const sendTrainerLimitMailOnHit = onDocumentUpdated(
  { document: "users/{uid}", region: "southamerica-east1" },
  async (event) => {
    const antes = event.data?.before?.data();
    const despues = event.data?.after?.data();
    // Filtro barato ANTES de tocar el app: casi todas las escrituras de
    // `users/{uid}` no son un tope.
    if (!esToqueNuevo(antes, despues)) return;

    const { getApp, initializeApp } = await import("firebase-admin/app");
    let app: App;
    try {
      app = getApp();
    } catch {
      app = initializeApp();
    }
    const uid = event.params.uid;
    try {
      const r = await alTocarElTope(app, uid, antes, despues, Date.now());
      logger.info("sendTrainerLimitMailOnHit", { uid, resultado: r });
    } catch (err) {
      logger.error(
        "sendTrainerLimitMailOnHit: falló; lo reintenta el barrido",
        { uid, err },
      );
    }
  },
);

/**
 * 05:30 ART. Ver el encabezado — "EL HORARIO DEL BARRIDO".
 */
export const sweepTrainerLimitMail = onSchedule(
  {
    schedule: "30 5 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const { getApp, initializeApp } = await import("firebase-admin/app");
    let app: App;
    try {
      app = getApp();
    } catch {
      app = initializeApp();
    }
    const r = await barrerLimiteDeEjercicios(app, Date.now(), logger);
    logger.info("sweepTrainerLimitMail: corrida diaria", r);
  },
);
