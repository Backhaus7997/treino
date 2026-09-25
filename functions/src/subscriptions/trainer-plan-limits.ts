/**
 * trainer-plan-limits.ts — el interruptor y el escritor del tope de
 * ejercicios propios del PF, `users/{uid}.planLimits.customExercises`
 * (limite-ejercicios-pf.md, PR1).
 *
 * ─── Por que existe este campo ──────────────────────────────────────────────
 *
 * `firestore.rules` tiene que saber cuantos ejercicios propios tiene ya un PF
 * para poder rebotarle el que se pasa del tope. Y no puede: las reglas de
 * Firestore no cuentan documentos de una coleccion (lo mismo que ya bloquea
 * `kFreeMaxOwnRoutines` y el tope de videos). De ahi el contador
 * denormalizado: esta CF cuenta contra `customExercises` y deja el numero
 * donde la regla lo alcanza con un `get()`. Es el MISMO patron —y por el
 * mismo motivo— que `athletePaywallEnforced` en `athlete-paywall-enforced.ts`
 * y que `customExerciseVideoUsage` en `custom-exercise-video-quota.ts`.
 *
 * `planLimits` es un MAPA y no un campo suelto a proposito: el proximo tope
 * del PF (plantillas publicas, espacio de archivos) suma una clave sin tocar
 * los pins de las reglas existentes.
 *
 * Los dos campos son CF-write-only: los pinea `firestore.rules` en el create
 * y en el update de `users/{uid}` (PR2). Sin ese pin el PF se escribe
 * `{planLimits: {customExercises: null}}` y el tope entero es decorativo — el
 * mismo bypass de una sola escritura que el pin de `athletePaywallEnforced`
 * documenta.
 *
 * ─── El interruptor, y por que arranca APAGADO ──────────────────────────────
 *
 * [TRAINER_EXERCISE_LIMITS_ENABLED] arranca en `false`. Con el interruptor
 * apagado esta CF igual corre y escribe `{customExercises: null}` en todos
 * lados: la plomeria queda ejercitada y OBSERVABLE en produccion antes de que
 * cobre importancia, y prender el tope pasa a ser un cambio de valor y nada
 * mas. Apagarlo vuelve a limpiar el campo (a `null`), o sea que el rollback es
 * real y no un deploy de emergencia.
 *
 * ─── El orden de encendido (limite-ejercicios-pf.md §4) ─────────────────────
 *
 * Este modulo (PR1, backend) se deploya apagado junto con PR2 (reglas, que
 * quedan inertes mientras el campo sea `null`) y PR3 (el gate del cliente,
 * tambien inerte con `null`). Recien el dia D:
 *
 *   1. Se mergea PR5 (copy de planes y legales) y se deploya el Coach Hub.
 *   2. Se flipea [TRAINER_EXERCISE_LIMITS_ENABLED] a `true` y se deploya
 *      functions.
 *   3. Se corre el barrido a mano (sin esperar a las 04:00) para que todos
 *      los PF queden con su numero de una.
 *   4. Se verifica: cada PF tiene el numero que le corresponde, crear en el
 *      tope rebota con el aviso correcto en cada superficie, y un alumno
 *      sigue sin friccion (el control negativo).
 *
 * El rollback es el mismo interruptor en `false` y un deploy: en el proximo
 * sync `planLimits` vuelve a `null` y la regla y el cliente dejan de gatear.
 * No hay nada que migrar.
 */

import { App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import { effectiveTier, SubscriptionState } from "./effective-limit";
import { TIER_CUSTOM_EXERCISE_LIMITS } from "./tier-config";

/** El interruptor. Ver el encabezado antes de tocarlo. */
export const TRAINER_EXERCISE_LIMITS_ENABLED = false;

/** El campo que escribe este modulo, y nadie mas. */
export const USAGE_FIELD = "customExerciseUsage";

/** La forma de `users/{uid}.planLimits`, tal cual la escribe este modulo. */
export interface TrainerPlanLimits {
  customExercises: number | null;
}

/** El tope de ejercicios propios que le corresponde a un tier. */
export function customExerciseLimitFor(
  tier: SubscriptionState["tier"],
): number | null {
  return Object.prototype.hasOwnProperty.call(TIER_CUSTOM_EXERCISE_LIMITS, tier)
    ? TIER_CUSTOM_EXERCISE_LIMITS[tier]
    : TIER_CUSTOM_EXERCISE_LIMITS.free;
}

/**
 * Que `planLimits` le corresponde a un PF, o `null` para decir «no tocar».
 *
 * `enabled` es parametro y no la constante leida directo, mismo motivo que
 * `resolveAthletePaywallEnforced`: si no, el camino PRENDIDO se shipearia sin
 * un solo test encima.
 *
 * - Apagado (`enabled === false`): `{customExercises: null}` para TODOS,
 *   incluido un PF de plan3 o uno degradado. La plomeria queda escrita y
 *   observable antes de importar.
 * - `degraded === true`: devuelve `null` (no tocar). Sobre un documento que
 *   sabemos que leimos mal no se decide nada — mismo criterio que el resto de
 *   `subscription-mail.ts` (ver `decideSubscriptionMail`/`decideExpiryMail`,
 *   que tambien cortan temprano con `if (degraded) return null`).
 * - Encendido y sano: `{customExercises: customExerciseLimitFor(effectiveTier(sub, nowMs))}`.
 */
export function resolvePlanLimits(
  sub: SubscriptionState | null | undefined,
  degraded: boolean,
  nowMs: number,
  enabled: boolean = TRAINER_EXERCISE_LIMITS_ENABLED,
): TrainerPlanLimits | null {
  if (!enabled) return { customExercises: null };
  if (degraded) return null;
  return { customExercises: customExerciseLimitFor(effectiveTier(sub, nowMs)) };
}

export interface RecountResult {
  uid: string;
  count: number;
  changed: boolean;
}

/** Solo para el test de la carrera. Ver [recountCustomExercises]. */
export interface RecountCustomExercisesOptions {
  /**
   * Corre despues de contar y antes de escribir. En produccion no se pasa
   * nunca; existe para que `custom-exercise-count.test.ts` pueda meter OTRA
   * invocacion justo en la ventana donde la carrera de abajo perdia un
   * recuento. Adentro de la transaccion puede correr mas de una vez (un
   * reintento vuelve a ejecutar el cuerpo entero).
   */
  afterCount?: () => Promise<void>;
}

/**
 * Recuenta `users/{uid}/customExercises` y deja el contador al dia. Escribe
 * el valor ABSOLUTO, solo si cambio.
 *
 * RECUENTA en vez de incrementar por el mismo motivo que
 * `reconcileVideoQuota` en `custom-exercise-video-quota.ts`: la entrega de
 * Eventarc es at-least-once, y un `FieldValue.increment()` se aplicaria dos
 * veces en una redelivery y dejaria el contador desviado PARA SIEMPRE.
 * Recontar el prefijo y escribir el valor absoluto es idempotente.
 *
 * Usa `.count()`, que es la PRIMERA agregacion `count()` de Cloud Functions en
 * este repo — verificado contra el emulador en `custom-exercise-count.test.ts`,
 * no asumido (el `audit_ranking_optin.js` de `scripts/` ya la usa, pero es un
 * script standalone, no una Cloud Function desplegada).
 *
 * No decide ROL: eso es responsabilidad del LLAMADOR (`custom-exercise-count.ts`
 * y el barrido de `entitlement-triggers.ts`, que ya filtra `role == 'trainer'`
 * en su query). Esta funcion cuenta y escribe para cualquier uid que se le
 * pase, sin opinar sobre si corresponde.
 *
 * Sin doc de perfil no hay donde escribir — no se crea uno desde aca, mismo
 * criterio que `reconcileVideoQuota`.
 *
 * ─── Por que en TRANSACCION ──────────────────────────────────────────────
 *
 * La entrega de Eventarc es at-least-once, y una redelivery ya esta cubierta
 * arriba (el recuento es idempotente). Lo que NO cubria la version anterior
 * —contar con `Promise.all` y despues un `update` suelto— es DOS INVOCACIONES
 * CONCURRENTES: contador en 1; la invocacion A cuenta 2 y se demora antes de
 * escribir; la invocacion B cuenta 3 y escribe 3; A escribe 2 encima. Quedan
 * 3 ejercicios con el contador en 2, y la regla deja crear uno de mas hasta
 * el barrido de las 04:00.
 *
 * Adentro de una transaccion, las dos lecturas y la escritura van juntas: si
 * otro recuento escribio el doc del usuario despues de que este lo leyo, este
 * commit no pasa y el cuerpo se reintenta, contando de nuevo. El que escribe
 * ultimo conto despues del otro.
 *
 * El doc del usuario se lee PRIMERO y solo despues se cuenta, a proposito: el
 * orden es lo que garantiza que el conteo del que gana sea posterior a la
 * escritura del que perdio. Con un `Promise.all` de las dos lecturas, el
 * conteo podria salir de antes del commit ajeno aunque la lectura del doc
 * saliera de despues.
 */
export async function recountCustomExercises(
  app: App,
  uid: string,
  options: RecountCustomExercisesOptions = {},
): Promise<RecountResult> {
  const db = getFirestore(app);
  const userRef = db.collection("users").doc(uid);
  const customExercises = db.collection(`users/${uid}/customExercises`);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const countSnap = await tx.get(customExercises.count());
    const count = countSnap.data().count;
    const prev = snap.get(USAGE_FIELD) as { count?: number } | undefined;
    const changed = prev?.count !== count;

    await options.afterCount?.();

    if (changed && snap.exists) {
      tx.update(userRef, { [USAGE_FIELD]: { count } });
    }

    return { uid, count, changed };
  });
}
