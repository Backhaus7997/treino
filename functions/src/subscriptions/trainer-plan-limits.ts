/**
 * trainer-plan-limits.ts — los interruptores y los escritores de los topes
 * del PF en `users/{uid}.planLimits`: ejercicios propios
 * (`customExercises`, limite-ejercicios-pf.md, PR1) y plantillas
 * (`templates`, limite-plantillas-pf.md, PR1). Las plantillas tienen su
 * propio encabezado al final de este bloque.
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
 *
 * ─── Plantillas (limite-plantillas-pf.md, PR1) ──────────────────────────────
 *
 * El mismo molde con una clave mas: `planLimits.templates` (el tope) y
 * `templateUsage.count` (plantillas NO archivadas del PF). Con su PROPIO
 * interruptor, [TRAINER_TEMPLATE_LIMITS_ENABLED], para poder encender las
 * plantillas sin tocar los ejercicios y al reves: `resolvePlanLimits` resuelve
 * cada clave con el suyo y ninguno opina sobre la clave del otro.
 *
 * El recuento NO esta calcado de `recountCustomExercises`: corre en una
 * transaccion. Ver el dartdoc de [recountTemplates] para la carrera que eso
 * cierra y que el de ejercicios todavia tiene.
 */

import { App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import { effectiveTier, SubscriptionState } from "./effective-limit";
import { TIER_CUSTOM_EXERCISE_LIMITS, TIER_TEMPLATE_LIMITS } from "./tier-config";

/** El interruptor. Ver el encabezado antes de tocarlo. */
export const TRAINER_EXERCISE_LIMITS_ENABLED = false;

/** El campo que escribe este modulo, y nadie mas. */
export const USAGE_FIELD = "customExerciseUsage";

/**
 * El interruptor del tope de plantillas (limite-plantillas-pf.md, PR1).
 * Arranca APAGADO por el mismo motivo que el de ejercicios: la plomeria corre
 * y escribe `{templates: null}` en produccion antes de que importe, y
 * encenderlo es un cambio de valor. Ver el encabezado antes de tocarlo.
 */
export const TRAINER_TEMPLATE_LIMITS_ENABLED = false;

/** El contador de plantillas: lo escribe [recountTemplates], y nadie mas. */
export const TEMPLATE_USAGE_FIELD = "templateUsage";

/** La forma de `users/{uid}.planLimits`, tal cual la escribe este modulo. */
export interface TrainerPlanLimits {
  customExercises: number | null;
  templates: number | null;
}

/** Un interruptor por clave de `planLimits`. */
export type PlanLimitSwitches = Record<keyof TrainerPlanLimits, boolean>;

/** El tope de ejercicios propios que le corresponde a un tier. */
export function customExerciseLimitFor(
  tier: SubscriptionState["tier"],
): number | null {
  return Object.prototype.hasOwnProperty.call(TIER_CUSTOM_EXERCISE_LIMITS, tier)
    ? TIER_CUSTOM_EXERCISE_LIMITS[tier]
    : TIER_CUSTOM_EXERCISE_LIMITS.free;
}

/**
 * El tope de plantillas que le corresponde a un tier. Calcado de
 * [customExerciseLimitFor]: `hasOwnProperty` y no `??`, porque `null` es SIN
 * TOPE y un `??` convertiria el plan mas caro en el mas chico.
 */
export function templateLimitFor(
  tier: SubscriptionState["tier"],
): number | null {
  return Object.prototype.hasOwnProperty.call(TIER_TEMPLATE_LIMITS, tier)
    ? TIER_TEMPLATE_LIMITS[tier]
    : TIER_TEMPLATE_LIMITS.free;
}

/**
 * Que `planLimits` le corresponde a un PF, o `null` para decir «no tocar
 * nada».
 *
 * `switches` es parametro y no las constantes leidas directo, mismo motivo que
 * `resolveAthletePaywallEnforced`: si no, el camino PRENDIDO se shipearia sin
 * un solo test encima.
 *
 * CADA CLAVE SE RESUELVE CON SU INTERRUPTOR, y ninguno opina sobre la clave
 * del otro:
 *
 * - Clave apagada: `null`, para TODOS — incluido un PF de plan3 o uno
 *   degradado. El valor no depende de nada que se haya podido leer mal, asi
 *   que la plomeria queda escrita y observable antes de importar.
 * - Clave prendida y `degraded === true`: la clave se OMITE (no tocar). Sobre
 *   un documento que sabemos que leimos mal no se decide nada — mismo
 *   criterio que `decideSubscriptionMail`/`decideExpiryMail`, que cortan con
 *   `if (degraded) return null`.
 * - Clave prendida y sana: el tope del tier efectivo.
 *
 * Por eso con `degraded` puede salir un mapa PARCIAL (la clave apagada en
 * `null`, sin la prendida), y `sync-entitlements.ts` lo escribe con
 * `merge: true`, que en Firestore mergea los mapas anidados campo por campo:
 * la clave omitida queda como estaba (probado contra el emulador en
 * `template-count.test.ts`). Resolverlo todo-o-nada seria mas simple, pero
 * haria que prender las plantillas cambie lo que se escribe en la clave de
 * ejercicios cuando el doc esta degradado. Si no queda ninguna clave —las dos
 * prendidas y `degraded`— devuelve `null`, como antes.
 *
 * Sano, SIEMPRE devuelve el mapa completo: las dos claves viajan explicitas,
 * aunque sean `null`, porque con `merge: true` omitirlas es "no tocar" y un
 * numero viejo quedaria pegado.
 */
export function resolvePlanLimits(
  sub: SubscriptionState | null | undefined,
  degraded: boolean,
  nowMs: number,
  switches: PlanLimitSwitches = {
    customExercises: TRAINER_EXERCISE_LIMITS_ENABLED,
    templates: TRAINER_TEMPLATE_LIMITS_ENABLED,
  },
): Partial<TrainerPlanLimits> | null {
  const tier = effectiveTier(sub, nowMs);
  const limits: Partial<TrainerPlanLimits> = {};

  if (!switches.customExercises) limits.customExercises = null;
  else if (!degraded) limits.customExercises = customExerciseLimitFor(tier);

  if (!switches.templates) limits.templates = null;
  else if (!degraded) limits.templates = templateLimitFor(tier);

  return Object.keys(limits).length > 0 ? limits : null;
}

export interface RecountResult {
  uid: string;
  count: number;
  changed: boolean;
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
 */
export async function recountCustomExercises(
  app: App,
  uid: string,
): Promise<RecountResult> {
  const db = getFirestore(app);
  const userRef = db.collection("users").doc(uid);

  const [snap, countSnap] = await Promise.all([
    userRef.get(),
    db.collection(`users/${uid}/customExercises`).count().get(),
  ]);

  const count = countSnap.data().count;
  const prev = snap.get(USAGE_FIELD) as { count?: number } | undefined;
  const changed = prev?.count !== count;

  if (changed && snap.exists) {
    await userRef.update({ [USAGE_FIELD]: { count } });
  }

  return { uid, count, changed };
}

/**
 * Las plantillas de un PF: `routines` con `assignedBy == uid` y
 * `source == 'trainer-template'`. Dos igualdades sin `orderBy`, que Firestore
 * sirve con el merge de los indices automaticos de un campo — no hace falta
 * un compuesto (limite-plantillas-pf.md §3, PR1: «Indices: ninguno nuevo», y
 * `docs/firestore-indexes.md`).
 */
function templatesOf(app: App, uid: string) {
  return getFirestore(app)
    .collection("routines")
    .where("assignedBy", "==", uid)
    .where("source", "==", "trainer-template");
}

/** Solo para el test de la carrera. Ver [recountTemplates]. */
export interface RecountTemplatesOptions {
  /**
   * Corre despues de contar y antes de escribir. En produccion no se pasa
   * nunca; existe para que `template-count.test.ts` pueda meter OTRA
   * invocacion justo en la ventana donde la carrera de abajo pierde un
   * recuento. Adentro de la transaccion puede correr mas de una vez (un
   * reintento vuelve a ejecutar el cuerpo entero).
   */
  afterCount?: () => Promise<void>;
}

/**
 * Recuenta las plantillas NO archivadas de un PF y deja
 * `users/{uid}.templateUsage.count` al dia. Escribe el valor ABSOLUTO, solo si
 * cambio, y solo en un doc de perfil que exista y sea de un `trainer`.
 *
 * Devuelve `null` si no conto nada: sin doc de perfil (no se crea uno desde
 * aca, mismo criterio que `reconcileVideoQuota`) o con un rol que no es
 * `trainer` (decision P6: la cuota corta por rol; un alumno con un
 * `trainer-template` forjado no recibe un contador que no le corresponde).
 *
 * ─── Total menos archivadas, no `status == 'active'` ────────────────────────
 *
 * `status` tiene default `active` en el modelo «para retro-compat»
 * (`routine.dart`): una plantilla vieja sin el campo NO matchea
 * `status == 'active'` y quedaria sin contar. `status == 'archived'` es el
 * unico valor que libera lugar, asi que se cuenta el total y se le resta eso.
 *
 * ─── Por que en TRANSACCION, y no calcado de `recountCustomExercises` ───────
 *
 * El recuento de ejercicios cuenta y despues hace un `update` suelto. Eso lo
 * protege de la redelivery, no de dos invocaciones concurrentes: contador en
 * 1; el evento A cuenta 2 y se demora; el evento B cuenta 3 y escribe 3; A
 * escribe 2. Quedan 3 plantillas con el contador en 2, y la regla deja crear
 * una cuarta hasta el barrido de las 04:00.
 *
 * Adentro de una transaccion, las dos lecturas y la escritura van juntas: si
 * otro recuento escribio el doc del usuario despues de que este lo leyo, este
 * commit no pasa y el cuerpo se reintenta, contando de nuevo. El que escribe
 * ultimo conto despues del otro. El SDK de `functions/`
 * (`@google-cloud/firestore` 7.x) acepta el `AggregateQuery` de `count()` en
 * `transaction.get()` — verificado en sus tipos, no asumido.
 *
 * El doc del usuario se lee PRIMERO y solo despues se cuenta, a proposito: el
 * orden es lo que garantiza que el conteo del que gana sea posterior a la
 * escritura del que perdio. Con un `Promise.all` de las tres lecturas, el
 * conteo podria salir de antes del commit ajeno aunque la lectura del doc
 * saliera de despues.
 */
export async function recountTemplates(
  app: App,
  uid: string,
  options: RecountTemplatesOptions = {},
): Promise<RecountResult | null> {
  const db = getFirestore(app);
  const userRef = db.collection("users").doc(uid);
  const templates = templatesOf(app, uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists || snap.get("role") !== "trainer") return null;

    const [total, archived] = await Promise.all([
      tx.get(templates.count()),
      tx.get(templates.where("status", "==", "archived").count()),
    ]);
    // Las archivadas son un subconjunto del total y las dos lecturas van en la
    // misma transaccion, asi que la resta no baja de 0. El piso es defensivo:
    // el cliente muestra este numero («2 de 3»), y un negativo no tiene
    // ninguna lectura posible.
    const count = Math.max(0, total.data().count - archived.data().count);

    await options.afterCount?.();

    const prev = snap.get(TEMPLATE_USAGE_FIELD) as { count?: number } | undefined;
    const changed = prev?.count !== count;
    if (changed) tx.update(userRef, { [TEMPLATE_USAGE_FIELD]: { count } });

    return { uid, count, changed };
  });
}
