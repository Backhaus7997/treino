/**
 * subscription-mail.ts — el canal de mail del paywall del PF.
 *
 * QUE SISTEMA ES ESTE. La suscripcion del ENTRENADOR a TREINO — no la cuota que
 * el alumno le paga a su PF. Ese otro sistema ya tiene su mail
 * (`payment-overdue`, producido por `notify-overdue-payments.ts`, destinatario
 * `athleteId`) y en castellano se dicen casi igual. Si estas tocando este
 * archivo pensando en la cuota del alumno, estas en el archivo equivocado.
 *
 * ── POR QUE EXISTE ────────────────────────────────────────────────────────
 *
 * Hasta acá el paywall no tenia ningun canal de salida. El PF se enteraba de que
 * algo cambio abriendo la app y chocando contra un bloqueo, y el slice 6 (PR
 * #758) construyo el copy in-app de ese choque. Este modulo es el otro canal:
 *
 *   el mail existe para llegar cuando el PF NO esta mirando la app.
 *
 * Esa frase decide todo lo que sigue, incluido lo que se descarto.
 *
 * ── EL TRIGGER ES LA TRANSICION, NUNCA EL ESTADO ──────────────────────────
 *
 * La forma obvia —"si hay alumnos bloqueados, mandá mail"— es un incidente
 * esperando. NINGUNA Cloud Function escribe `users/{uid}.subscription` todavia
 * (`rg "subscription:" functions/src --glob '!__tests__'` → vacio): el mapa se
 * carga a mano con el Admin SDK. O sea que HOY todo PF resuelve a `FREE_LIMIT`
 * = 2, y si `sweepEntitlements` esta desplegado ya viene marcando `blocked` todo
 * salvo 2 alumnos por cabeza. Un disparador por ESTADO le mandaria, en el primer
 * barrido despues del deploy, un mail a cada PF real de `treino-dev` sobre un
 * paywall que nunca les vendimos.
 *
 * Disparar por TRANSICION (`before` → `after`) invierte la falla: un sistema que
 * todavia no transiciona no manda nada. Este modulo mergea MUDO, a proposito, y
 * empieza a hablar cuando exista la integracion con MP.
 *
 * Efecto lateral bueno: el backfill manual que el diseño exige antes del
 * enforcement (`undefined` → `{tier: plan2, status: active}`) es una SUBIDA de
 * 2 a 15. No dispara nada.
 *
 * ── LAS DOS TRANSICIONES, Y LAS QUE NO ────────────────────────────────────
 *
 * 1. ENTRAR EN `grace`. La mas importante, y la menos obvia: `grace` CONSERVA el
 *    limite pagado (`effective-limit.ts`, ADR-3), asi que no se bloquea a nadie,
 *    no rebota ninguna escritura, y la pantalla del PR #758 mostraria "ninguno
 *    de tus alumnos quedó fuera de tu cupo". No hay una sola señal in-app. Es el
 *    unico canal que existe, y encima es el momento en que la accion del PF
 *    todavia previene el daño.
 *
 * 2. QUE BAJE EL LIMITE EFECTIVO. El predicado es
 *    `effectiveWeightLimit(before) > effectiveWeightLimit(after)` y NO una lista
 *    de status. Un solo predicado cubre `active→paused`, `active→pending`,
 *    `grace→paused`, la bajada de tier (`plan2→plan1` baja de 15 a 7 y bloquea
 *    8 alumnos sin que ninguna pantalla lo diga) y el vencimiento de
 *    `cancelled`. Reusa la funcion que ya es la unica fuente de verdad del
 *    limite y que ya tiene guard de exhaustividad: un status nuevo no se puede
 *    escapar por adelante.
 *
 * LO QUE NO LLEVA MAIL, y por que:
 *
 *   - "Te estas acercando al límite" (6 de 7). Nada fallo, y el PF ve `N/limite`
 *     en cada pantalla del Coach Hub. Eso es un UPSELL, no un aviso de servicio.
 *     Meterlo en el mismo canal que "tu cobro fallo" le enseña al PF que estos
 *     mails son venta, y deja de abrirlos — la reputacion de remitente que el
 *     header de `enqueue-mail.ts` dice que no se recompra.
 *   - Un mail propio de "llegaste al límite". Cuando eso pasa sin transicion de
 *     suscripcion, el PF esta en la app haciendo la accion y el gate de
 *     `promote-link.ts` le contesta ahi mismo. El conteo de bloqueados viaja
 *     ADENTRO del mail de downgrade, como consecuencia con causa.
 *   - `cancelled` en el momento del clic. El limite NO baja ahi: baja en
 *     `currentPeriodEnd`. Anunciarlo como Free seria falso, y es justo la
 *     correccion que el PR #758 dejo pineada. Ademas el PF acaba de tocar
 *     "cancelar" en la app — no es el momento en que nadie esta mirando. El
 *     vencimiento SI lo es, y ese lo cubre `decideExpiryMail`.
 *   - `pending` y `→ active`. Son recibos de pago. Los manda el procesador.
 *
 * ── LA VALVULA DE DEGRADACION ─────────────────────────────────────────────
 *
 * Corrida con `degraded: true` ⇒ NO se manda mail. Es la misma valvula que ya
 * gobierna `sync-entitlements.ts`, aplicada al canal nuevo: si no entendimos el
 * documento, no le avisamos a un PF que su servicio se esta cortando en base a
 * un dato que sabemos que leimos mal. Un mail equivocado sobre plata no se
 * puede retirar de una bandeja de entrada.
 *
 * Del lado del `before` la proteccion sale sola: un `before` degradado cae al
 * fallback conservador (limite 2), asi que arreglar el documento se lee como una
 * SUBIDA y no dispara nada. La degradacion falla hacia el silencio en los dos
 * sentidos.
 *
 * ── EL SCOPE DE DEDUPE ────────────────────────────────────────────────────
 *
 * La clave del outbox es `{scope}__{kind}__{toUid}`, y el requisito tiene dos
 * mitades que tiran para lados opuestos: un trigger re-disparado (los eventos
 * son at-least-once) NO puede mandar dos, pero entrar en `grace` dos meses
 * seguidos SI tiene que mandar dos.
 *
 * Lo que resuelve las dos es el CICLO DE FACTURACION al que pertenece el hecho,
 * y ese ciclo lo identifica `currentPeriodEnd`: estable durante todo el periodo,
 * distinto en cuanto se paga el siguiente.
 *
 *   - `artDateKey` solo NO alcanza: un re-disparo cruzando la medianoche ART
 *     manda dos. (Es el scope correcto para `payment-overdue`, que es un
 *     recordatorio SEMANAL legitimo — no es el mismo problema.)
 *   - Solo el trainerId tampoco: mandaria un unico mail de grace en la vida.
 *   - Con `currentPeriodEnd`, un flap `grace→active→grace` dentro del mismo
 *     ciclo colapsa en uno. Es lo correcto: es la misma falla de cobro.
 *
 * El downgrade suma el LIMITE NUEVO al scope, porque dos downgrades distintos
 * pueden caer en el mismo ciclo: `plan2→plan1` (15→7) y despues `plan1→paused`
 * (7→2) son dos hechos con dos consecuencias, y el PF tiene que enterarse de los
 * dos.
 */

import * as admin from "firebase-admin";

import { enqueueMail } from "../mail/enqueue-mail";
import { artDateKey } from "../mail/format";
import { APP_ENTRY_TRAINER } from "../mail/templates";
import { MailParams } from "../mail/types";
import { effectiveWeightLimit, SubscriptionState } from "./effective-limit";
import { MappedSubscription } from "./subscription-state";

/** Los dos unicos kinds que produce el paywall. */
export type SubscriptionMailKind =
  | "subscription-grace"
  | "subscription-downgraded";

/** Un mail decidido pero todavia no encolado. */
export interface SubscriptionMailPlan {
  kind: SubscriptionMailKind;
  /** Lo que este mail se deduplica POR. Ver el encabezado. */
  scope: string;
  /**
   * Params listos para el template, MENOS los que no se saben hasta despues de
   * la transaccion (`blockedCount`) y el CTA. Todos son DATOS —codigos y
   * numeros—, nunca prosa: el outbox guarda que paso, y el copy se aplica al
   * enviar, asi que un arreglo de texto alcanza a lo que ya esta encolado.
   */
  params: MailParams;
}

/**
 * Cuanto despues del vencimiento sigue siendo noticia.
 *
 * 48h y no 24: el barrido es diario, y si se saltea una corrida una ventana de
 * 24h perderia el aviso para siempre. Con 48 tolera un barrido perdido, y la
 * clave de dedupe —que va por `currentPeriodEnd`— se encarga de que dos
 * corridas dentro de la ventana sigan mandando UN mail.
 *
 * El tope existe para que un `cancelled` que vencio hace meses no genere un
 * aviso al primer barrido despues de un deploy. Es el mismo riesgo que motiva
 * disparar por transicion y no por estado, entrando por la unica puerta donde no
 * hay un `before` que comparar.
 */
const EXPIRY_WINDOW_MS = 48 * 60 * 60 * 1000;

/** Centinela del "sin límite" al cruzar Firestore. Espejo de `templates.ts`. */
const NO_LIMIT_PARAM = "sin-tope";

/**
 * Ordena limites para poder comparar `number | null`.
 *
 * `null` es plan3 = SIN TOPE, o sea el mayor de todos — no una ausencia. Un
 * `limitBefore > limitAfter` a secas con `null` de un lado compara contra 0 en
 * JS y da la respuesta al reves: bajar de plan3 a plan2 dejaba de ser un
 * downgrade, y justo para el PF que mas paga.
 */
function limitRank(limit: number | null): number {
  return limit === null ? Number.POSITIVE_INFINITY : limit;
}

/** El limite, como viaja en los params. Ver `NO_LIMIT_PARAM`. */
function limitParam(limit: number | null): string | number {
  return limit === null ? NO_LIMIT_PARAM : limit;
}

/**
 * El fragmento de scope que identifica el ciclo de facturacion.
 *
 * Sin `currentPeriodEnd` no hay ciclo del cual colgarse, y ahi `artDateKey` es
 * el fallback honesto: acota a un mail por dia ART en vez de a uno por evento.
 * Es peor que la clave por ciclo y mejor que no deduplicar; y para llegar a este
 * caso el documento tiene que estar incompleto de una forma que la valvula de
 * degradacion no atrapa (`currentPeriodEnd` ausente es legitimo, no degradado).
 */
function periodScope(sub: SubscriptionState | null, nowMs: number): string {
  const end = sub?.currentPeriodEndMs;
  return end != null ? String(end) : artDateKey(nowMs);
}

/**
 * El codigo de causa que consume el template.
 *
 * Es un CODIGO y no la frase: el copy vive entero en `templates.ts`, del lado
 * que se re-renderiza al enviar.
 *
 * `active` y `grace` de este lado significan que el limite bajo SIN que el
 * status cambiara a uno inactivo — o sea, cambio el tier. Un mapa
 * `subscription` borrado entero cae en `""`, y el template contesta con una
 * frase neutra y cierta en vez de inventar una causa.
 */
function downgradeReasonCode(state: SubscriptionState | null): string {
  if (!state) return "";
  switch (state.status) {
  case "paused":
    return "paused";
  case "pending":
    return "pending";
  case "cancelled":
    return "cancelled-expired";
  case "active":
  case "grace":
    return "tier-change";
  default: {
    // Mismo guard que `effectiveWeightLimit`: un status nuevo rompe el build
    // aca en vez de mandar un mail sin causa.
    const _exhaustive: never = state.status;
    void _exhaustive;
    return "";
  }
  }
}

function gracePlan(
  state: SubscriptionState | null,
  nowMs: number,
): SubscriptionMailPlan {
  return {
    kind: "subscription-grace",
    scope: `subgrace_${periodScope(state, nowMs)}`,
    params: {
      tier: state?.tier ?? "",
      limit: limitParam(effectiveWeightLimit(state, nowMs)),
    },
  };
}

function downgradePlan(
  state: SubscriptionState | null,
  limitAfter: number | null,
  nowMs: number,
): SubscriptionMailPlan {
  return {
    kind: "subscription-downgraded",
    scope: `subdown_${limitParam(limitAfter)}_${periodScope(state, nowMs)}`,
    params: {
      tier: state?.tier ?? "",
      limit: limitParam(limitAfter),
      reason: downgradeReasonCode(state),
    },
  };
}

/**
 * Decide que mail —si alguno— corresponde a una transicion de `subscription`.
 *
 * Pura: sin Firestore y sin reloj propio, para que los casos de borde se puedan
 * testear con un `nowMs` fijo.
 *
 * `grace` GANA cuando las dos condiciones dan a la vez (entrar en grace con un
 * tier mas chico al mismo tiempo). Es un solo hecho para el PF, y de los dos
 * mensajes el de grace es el unico con una accion que evita la consecuencia.
 * Dos mails para un evento es la clase de ruido que hace que se dejen de leer.
 *
 * @param before - Suscripcion antes del write, ya saneada.
 * @param after  - Suscripcion despues del write, ya saneada.
 * @param nowMs  - Reloj, inyectado.
 */
export function decideSubscriptionMail(
  before: MappedSubscription,
  after: MappedSubscription,
  nowMs: number,
): SubscriptionMailPlan | null {
  if (after.degraded) return null;

  if (after.state?.status === "grace" && before.state?.status !== "grace") {
    return gracePlan(after.state, nowMs);
  }

  const limitBefore = effectiveWeightLimit(before.state, nowMs);
  const limitAfter = effectiveWeightLimit(after.state, nowMs);
  if (limitRank(limitBefore) > limitRank(limitAfter)) {
    return downgradePlan(after.state, limitAfter, nowMs);
  }

  return null;
}

/**
 * Decide el mail del vencimiento de un `cancelled`.
 *
 * Es la unica bajada de limite de todo el sistema que NO escribe un documento:
 * el status sigue diciendo `cancelled` y el tier sigue siendo el mismo; lo unico
 * que se movio es el reloj. No hay `before` que comparar, asi que el "antes" se
 * construye evaluando LA MISMA suscripcion un instante previo al vencimiento.
 *
 * Esa comparacion no es ceremonia: un `cancelled` de tier `free` vence sin bajar
 * nada (2 → 2), y sin el chequeo mandaria un mail anunciando un cambio que no
 * ocurrio.
 *
 * @param sub   - Suscripcion del PF, ya saneada.
 * @param nowMs - Reloj, inyectado.
 */
export function decideExpiryMail(
  sub: MappedSubscription,
  nowMs: number,
): SubscriptionMailPlan | null {
  if (sub.degraded) return null;

  const state = sub.state;
  if (!state || state.status !== "cancelled") return null;

  const end = state.currentPeriodEndMs;
  if (end == null) return null;
  if (end > nowMs) return null;
  if (nowMs - end > EXPIRY_WINDOW_MS) return null;

  const limitBefore = effectiveWeightLimit(state, end - 1);
  const limitAfter = effectiveWeightLimit(state, nowMs);
  if (limitRank(limitBefore) <= limitRank(limitAfter)) return null;

  return downgradePlan(state, limitAfter, nowMs);
}

/**
 * Encola el mail decidido.
 *
 * SIEMPRE DESPUES DE LA TRANSACCION, nunca adentro. `syncTrainerEntitlements`
 * corre en un `runTransaction`, y las transacciones REINTENTAN: un enqueue
 * adentro se ejecutaria una vez por intento. Que `enqueueMail` sea idempotente
 * cubre el reintento del TRIGGER —que es de lo que protege el outbox— y no
 * habria por que gastarlo en un problema que se evita llamando desde el lugar
 * correcto.
 *
 * `blockedCount` solo viaja en el downgrade: en `grace` el limite no bajo, asi
 * que no hay nadie bloqueado y el numero seria siempre 0.
 *
 * Sin `prefKey`: el PF no puede optar por no enterarse de que su servicio se
 * corta. Mismo criterio que `payment-overdue`.
 *
 * @param blockedCount - Alumnos que quedan en solo lectura. Es el ESTADO
 *                       resultante (`blockedAthleteIds.length`), no el delta de
 *                       esta corrida: el delta subcontaria a quien ya venia
 *                       bloqueado de antes, y el mail describe como quedo la
 *                       cuenta, no que cambio en este evento.
 */
export async function enqueueSubscriptionMail(
  app: admin.app.App,
  trainerId: string,
  plan: SubscriptionMailPlan,
  blockedCount: number,
): Promise<string | null> {
  const params: MailParams = { ...plan.params, ctaUrl: APP_ENTRY_TRAINER };
  if (plan.kind === "subscription-downgraded") {
    params.blockedCount = blockedCount;
  }

  return enqueueMail(app, {
    toUid: trainerId,
    kind: plan.kind,
    scope: plan.scope,
    params,
  });
}
