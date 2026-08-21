/**
 * subscription-state.ts — el UNICO lector del mapa crudo
 * `users/{uid}.subscription` (paywall Fase 7).
 *
 * POR QUE EXISTE: `promote-link.ts` (el gate) y `sync-entitlements.ts` (el
 * barrido) tenian cada uno su copia del mismo mapper, y las dos hacian el mismo
 * `as` ciego sobre el documento. Un cast no valida NADA en runtime, y
 * `subscription` no lo escribe ninguna Cloud Function: se carga a mano con el
 * Admin SDK. O sea que el tipo era una promesa que nadie chequeaba, sobre el
 * unico input del que depende TODO el paywall.
 *
 * QUE HACE ADEMAS DE MAPEAR: valida `tier`, `status` y `currentPeriodEnd`
 * contra sus formas reales, DEGRADA POR CAMPO al valor conservador con un warn
 * que lleva el uid, y devuelve ademas un flag `degraded` para que el consumidor
 * pueda decidir. El log es la mitad del arreglo: hoy un typo degrada en
 * silencio y no nos enteramos hasta que un PF reclama.
 *
 * POR QUE DEGRADA POR CAMPO Y NO DEVUELVE null: si el status no se entiende
 * pero el tier SI, conservar el tier hace que `promotionDenialReason` (D-2)
 * responda `subscription-inactive` — "revisá tu suscripción" — en vez de
 * `plan-limit` — "comprá un plan mas grande" — que seria una mentira para
 * alguien que ya pago plan2. Ademas manda al PF por el canal donde un humano
 * puede ver el documento roto.
 *
 * ── POR QUE EL FLAG Y NO SOLO EL WARN: LA POLITICA ────────────────────────
 *
 *   La degradacion de datos frena TRABAJO NUEVO (friccion sobre el entrenador)
 *   pero NUNCA revoca relaciones existentes (friccion sobre el alumno).
 *
 * El warn solo no alcanza porque degradar CAMBIO el signo del fallo. Antes de
 * este modulo, un `currentPeriodEnd` escrito como number (epoch ms — un error a
 * mano tan plausible como el typo "canceled") hacia explotar
 * `sub.currentPeriodEnd.toMillis()` con un TypeError: la transaccion abortaba y
 * el catch por-PF de `entitlement-triggers.ts` salteaba a ese entrenador. Feo,
 * ruidoso, y CERO escrituras. Degradar a `null` en silencio convierte ese fallo
 * en limite 2 efectivo, y el barrido pasa a emitir N-2 `tx.update` que bloquean
 * alumnos: un typo NUESTRO le corta el servicio a los alumnos de un PF que
 * capaz pago plan3. `degraded` existe para que esa segunda cara no ocurra.
 *
 * Los dos consumidores lo usan ASIMETRICAMENTE, a proposito:
 *   - el GATE (`promote-link.ts`) lo ignora y sigue denegando con FREE_LIMIT —
 *     fail-closed contra el entrenador: no suma alumnos nuevos con la
 *     suscripcion en un estado que no entendemos;
 *   - el BARRIDO (`sync-entitlements.ts`) corre SOLO `unblock` y saltea
 *     `block` — nunca le saca un alumno a nadie por un dato que escribimos mal.
 *
 * Esa regla es la que va a gobernar el enforcement que llega en el slice
 * siguiente: cualquier clausula nueva se decide con la misma frase.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import {
  SubscriptionState,
  SubscriptionStatus,
  SUBSCRIPTION_STATUSES,
} from "./effective-limit";
import { SubscriptionTier, TIER_WEIGHT_LIMITS } from "./tier-config";

// Set y no `in`: `in` camina la cadena de prototipos y aceptaria "toString".
const KNOWN_TIERS: ReadonlySet<string> = new Set(Object.keys(TIER_WEIGHT_LIMITS));
const KNOWN_STATUSES: ReadonlySet<string> = new Set<string>(SUBSCRIPTION_STATUSES);

/** Tier de fallback: el mas barato, el unico que no regala entitlement. */
const FALLBACK_TIER: SubscriptionTier = "free";

/**
 * Status de fallback. `paused` es el unico cuyo significado de producto es "el
 * entitlement esta suspendido pero la relacion sigue viva", que es exactamente
 * lo que sabemos cuando no entendemos el dato, y resuelve a Free (2). No se
 * agrega un "unknown" a la union a proposito: la union la espeja el cliente y
 * la valida firestore.rules, y un miembro nuevo obliga a tocar las tres.
 */
const FALLBACK_STATUS: SubscriptionStatus = "paused";

interface RawSubscription {
  tier?: unknown;
  status?: unknown;
  currentPeriodEnd?: unknown;
}

/**
 * Lo que el mapper le entrega al consumidor: el estado ya saneado MAS el aviso
 * de si hubo que sanear algo.
 *
 * El flag va afuera de `SubscriptionState` y no adentro por dos motivos: uno,
 * `SubscriptionState` es el input PURO de `effectiveWeightLimit` y no tiene por
 * que enterarse de como se leyo el documento; dos, el caso "el mapa existe pero
 * es ilegible" devuelve `state: null` y necesita igual poder gritar
 * `degraded: true` — un flag adentro del estado no tendria donde vivir.
 */
export interface MappedSubscription {
  /**
   * `null` = no hay limite que derivar del documento: o no hay mapa
   * `subscription` (el PF free normal), o el mapa es ilegible. Cual de los dos
   * fue lo dice `degraded`.
   */
  state: SubscriptionState | null;
  /**
   * `true` = al menos un campo no se entendio y se reemplazo por el valor
   * conservador. Ver la POLITICA del encabezado: quien lo consume decide, y las
   * dos decisiones validas son "frenar trabajo nuevo" y "no revocar nada".
   */
  degraded: boolean;
}

/**
 * Chequeo ESTRUCTURAL del Timestamp, no `instanceof
 * admin.firestore.Timestamp`: los tests locales corren contra un doble de
 * firebase-admin donde el instanceof daria false para un timestamp valido.
 *
 * Una forma desconocida (un number, un string, un mapa a medio escribir) se
 * trata como ausente: un `cancelled` sin paid-through cae a Free, que es el
 * lado conservador — nunca regalar entitlement por un dato que no entendemos.
 * Y se reporta como degradacion, porque ese mismo `null` es el que antes era un
 * TypeError que abortaba la transaccion entera.
 */
function toMillisOrNull(
  value: unknown,
  trainerId: string,
): { ms: number | null; degraded: boolean } {
  if (value == null) return { ms: null, degraded: false };

  const candidate = value as { toMillis?: unknown };
  if (typeof candidate.toMillis === "function") {
    return { ms: (candidate.toMillis as () => number)(), degraded: false };
  }

  logger.warn(
    "subscription-state: currentPeriodEnd no es un Timestamp — se ignora",
    { trainerId, received: typeof value },
  );
  return { ms: null, degraded: true };
}

/**
 * Mapea `users/{uid}.subscription` al `SubscriptionState` puro que consume
 * `effectiveWeightLimit`. El campo en Firestore es `currentPeriodEnd`
 * (Timestamp); `effectiveWeightLimit` quiere `currentPeriodEndMs` (number) para
 * quedar independiente de Firestore y testeable con un reloj plano.
 *
 * `subscription` ausente ⇒ `{ state: null, degraded: false }` (Free, sin
 * backfill — el mismo contrato que usa `TrainerSubscription?` del lado del
 * cliente). Ese caso NO logea y NO es degradacion: es el estado normal de un PF
 * free, no una anomalia. Confundirlos haria que el barrido dejara de bloquear
 * para TODOS los free, que son la mayoria.
 *
 * `trainerId` es OBLIGATORIO: un warn sin uid no localiza el documento roto, y
 * hay un solo doc roto entre cientos. Era opcional y los dos callers lo pasaban
 * igual, pero "los dos callers lo pasan" no es una garantia — sacarlo compilaba.
 * Ahora lo garantiza el compilador, que es la unica capa que no se puede
 * olvidar.
 */
export function toSubscriptionState(
  data: admin.firestore.DocumentData | undefined,
  trainerId: string,
): MappedSubscription {
  const raw: unknown = data?.subscription;
  if (raw == null) return { state: null, degraded: false };

  if (typeof raw !== "object") {
    logger.warn("subscription-state: `subscription` no es un mapa — se ignora", {
      trainerId,
      received: typeof raw,
    });
    return { state: null, degraded: true };
  }

  const sub = raw as RawSubscription;
  let degraded = false;

  let tier: SubscriptionTier;
  if (typeof sub.tier === "string" && KNOWN_TIERS.has(sub.tier)) {
    tier = sub.tier as SubscriptionTier;
  } else {
    tier = FALLBACK_TIER;
    degraded = true;
    logger.warn(`subscription-state: tier desconocido — degradado a ${FALLBACK_TIER}`, {
      trainerId,
      tier: sub.tier,
    });
  }

  let status: SubscriptionStatus;
  if (typeof sub.status === "string" && KNOWN_STATUSES.has(sub.status)) {
    status = sub.status as SubscriptionStatus;
  } else {
    status = FALLBACK_STATUS;
    degraded = true;
    logger.warn(`subscription-state: status desconocido — degradado a ${FALLBACK_STATUS}`, {
      trainerId,
      status: sub.status,
      tier,
    });
  }

  const periodEnd = toMillisOrNull(sub.currentPeriodEnd, trainerId);

  return {
    state: { tier, status, currentPeriodEndMs: periodEnd.ms },
    degraded: degraded || periodEnd.degraded,
  };
}
