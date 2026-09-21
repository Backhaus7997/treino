/**
 * reconcile.ts — el unico lugar que escribe `users/{uid}.subscription` a partir
 * de Mercado Pago. Es lo que hace que pagar SIGNIFIQUE algo.
 *
 * Sin esto, `createPreapproval` abre un cobro y nadie se entera: el PF paga y
 * su limite no se mueve.
 *
 * ── EL PRINCIPIO, otra vez porque acá se aplica ──
 *
 * La verdad se le PREGUNTA a MP con un GET usando nuestro token. Nunca se
 * asume, nunca se lee de un body entrante. Ver el encabezado de `client.ts`.
 *
 * Consecuencia practica: esta funcion recibe UN id de PLAN y nada mas, y le
 * pregunta a MP que suscripciones existen contra el.
 *
 * Se busca por plan y no por id de suscripcion porque el plan lo creamos
 * NOSOTROS —su id ya esta en `mp_plans` desde que el PF toco comprar— mientras
 * que de la suscripcion no sabemos nada hasta que alguien paga. Ademas no esta
 * verificado que la suscripcion herede el `external_reference` del plan, asi
 * que buscarla por ahi seria apostar a lo que no sabemos.
 *
 * El webhook —cuando exista— trae un id de SUSCRIPCION, no de plan. Va a tener
 * que resolver el plan primero (el preapproval trae `preapproval_plan_id`) y
 * despues llamar acá. El barrido agendado la llama con los planes que ya
 * conocemos. Por eso el producto anda aunque el webhook no llegue nunca: se
 * pierde latencia, no correccion.
 *
 * ── CUANDO NO ESCRIBE, que es la parte que importa ──
 *
 * `subscription-state.ts` dejo escrita la politica, y no se reinventa acá:
 *
 *   La degradacion de datos frena TRABAJO NUEVO, pero NUNCA revoca relaciones
 *   existentes.
 *
 * Escribir un estado que no entendimos NO es neutral: bajaria al PF al limite
 * Free y el barrido de las 04:00 le bloquearia alumnos. O sea que un dato raro
 * de MP terminaria cortandole el servicio a alumnos que no tienen nada que ver.
 *
 * Por eso hay seis casos donde esta funcion NO toca el documento:
 *
 *   1. El estado de MP no se entiende (`degraded`).
 *   2. No sabemos de que plan es la suscripcion.
 *   3. El uid del mapeo no coincide con el `external_reference` de MP.
 *   4. Lo que ibamos a escribir es identico a lo que ya esta.
 *   5. Es un `pending` y el PF ya tiene un entitlement pago vigente.
 *   6. El plan fue REEMPLAZADO por otro y lo dimos de baja nosotros.
 *
 * El (5) protege al PF que cambia de plan. Nada impide abrir un checkout
 * estando ya suscripto, asi que un plan2 que quiere pasar a plan3 queda con DOS
 * documentos en `mp_plans` con su uid, y el barrido escribe por cada uno. Como
 * `effective-limit` le da el limite FREE a un `pending`, sin esa guarda el plan
 * nuevo —todavia sin autorizar— le bajaba el limite a 2 y le bloqueaba alumnos
 * a alguien que acababa de intentar pagarnos mas. Ver la guarda para el detalle.
 *
 * El (4) no es una optimizacion: cada escritura de `users/{uid}` dispara
 * `syncEntitlementsOnSubscription`, que decide MAIL por transicion. Reescribir
 * el mismo valor gasta invocaciones al pedo, y una regresion futura en la
 * deteccion de transiciones se convertiria en una tormenta de mails.
 *
 * ── EL CAMBIO DE PLAN, Y POR QUE LA BAJA DE LA VIEJA SE DECIDE ACA ──
 *
 * La guarda (5) le salvo el padron al PF que cambia de plan, pero tapaba la
 * mitad del problema: **la suscripcion vieja seguia viva en Mercado Pago y le
 * cobraba igual.** Un plan2 que pasaba a plan3 terminaba con DOS suscripciones
 * autorizadas y DOS debitos por mes. Nada en el repo las daba de baja —
 * `MpClient` no sabia cancelar, y `create-preapproval.ts` solo valida el rol.
 *
 * La pregunta de diseño no es COMO cancelar, es CUANDO. Hay dos momentos
 * posibles y uno de los dos le rompe el producto a alguien:
 *
 *   **Al abrir el checkout nuevo.** Es el momento obvio y es el equivocado.
 *   Abrir un checkout NO es pagar: `create-preapproval.ts` documenta que MP deja
 *   la suscripcion en `pending` hasta que el PF carga su medio de pago. O sea
 *   que el PF que toca "ELEGIR PLAN", mira el precio y cierra la pestaña se
 *   quedaria SIN PLAN y sin haber comprado nada — le dimos de baja lo que ya
 *   pagaba a cambio de una intencion. Y como la baja es TERMINAL en MP, no
 *   alcanza con arrepentirse: hay que hacerlo pasar por el checkout de nuevo.
 *
 *   **Cuando la NUEVA queda confirmada.** Es acá, y es el unico momento en que
 *   la informacion existe: la confirmacion es un `authorized` que solo se sabe
 *   preguntandole a MP, y este archivo es el unico que pregunta. Mientras la
 *   nueva no este confirmada, la vieja es lo unico que el PF tiene y se toca
 *   con cero razones.
 *
 * Es el mismo principio que gobierna todo lo demas, aplicado a una escritura que
 * sale del sistema en vez de entrar: **no se actua sobre una intencion, se actua
 * sobre lo que MP confirmo.**
 *
 * Tres detalles que no son de adorno:
 *
 *   - Se cancela lo ESTRICTAMENTE MAS VIEJO, por `mp_plans.createdAt`, y nunca
 *     "las otras del uid". El barrido recorre los planes en el orden que
 *     Firestore devuelva: con los dos autorizados a la vez, "cancelar las otras"
 *     le daria de baja al PF el plan que ACABA de comprar si el viejo se
 *     procesaba primero. Sin las dos fechas no se cancela nada.
 *
 *   - Corre tambien cuando el resultado es `unchanged`, no solo en el `written`.
 *     Si la baja falla una noche —MP caido, un 429— la nueva ya quedo escrita y
 *     la corrida siguiente la ve sin cambios. Colgar la cancelacion del `written`
 *     dejaba el cobro doble vivo para siempre despues de un unico fallo
 *     transitorio.
 *
 *   - **Se marca ANTES de cancelar, no despues**, y los dos campos que se
 *     escriben significan cosas distintas:
 *
 *       `supersededBy` es una decision NUESTRA —sale de comparar dos fechas que
 *       ya tenemos— y se escribe ANTES del PUT. Activa el caso (6).
 *
 *       `terminal` es un hecho de MP y se escribe DESPUES, solo si la baja
 *       confirmo.
 *
 *     El orden es el arreglo de un agujero real: escribiendo `supersededBy`
 *     despues del PUT, cualquier RESPUESTA PERDIDA lo desarmaba. No hacia falta
 *     que MP fallara — un 204, un 2xx con body vacio, el timeout de 10s con la
 *     baja ya aplicada, o la instancia muriendo entre las dos operaciones dejaba
 *     la suscripcion cancelada en MP y el plan sin marcar. Y ahi el caso (6) es
 *     necesario: dentro de la MISMA corrida el barrido tiene el snapshot viejo
 *     en la mano, reconcilia ese plan, MP contesta `cancelled` —que SI puede
 *     bajar el limite— y la ultima escritura de la noche termina siendo un
 *     downgrade encima del plan recien comprado, con su mail y sus alumnos
 *     bloqueados.
 *
 *   - `terminal` NO significa "muerto", y la baja no puede filtrar por el a
 *     secas. Ver `puedeSeguirCobrando`: un terminal por ABANDONO es una apuesta
 *     sobre el futuro, no un hecho — el `init_point` no vence y el PF lo puede
 *     pagar al dia 35. Saltearlo dejaba a ese PF con cobro doble PARA SIEMPRE,
 *     porque el barrido tampoco lo reconcilia.
 *
 * ── EL PERIODO QUE EL PF YA PAGO, Y POR QUE ESTE ARCHIVO LO CAPTURA ──
 *
 * La baja cierra el cobro doble, pero abrio un agujero al lado: como la guarda
 * (6) impide que el plan viejo escriba, su `cancelled` —que llevaria su
 * `currentPeriodEnd`— no se guarda en ningun lado. Y ese era el unico registro
 * de lo que el PF ya habia pagado.
 *
 * El daño NO es que MP no reembolse: eso es inevitable y no lo arregla ningun
 * codigo. El daño es que TREINO dejaba de honrar el periodo comprado. Un plan3
 * (SIN TOPE) que bajaba a plan1 (7) caia a 7 EN EL ACTO, y
 * `syncEntitlementsOnSubscription` le bloqueaba alumnos en la MISMA invocacion
 * mas un mail de degradacion. A alguien que pago por esos alumnos. Con el anual
 * es peor de escala: son 12 meses en UN cobro (`tier-config.ts`), asi que un
 * cambio en marzo evaporaba nueve.
 *
 * Por eso, en la misma escritura, se guarda el PISO PREPAGO: `prepaidTier` y
 * `prepaidUntil`. El dato no sale de ningun lado nuevo —es lo que estabamos por
 * pisar— y `effectiveWeightLimit` devuelve el MAXIMO entre lo que dice el status
 * y ese piso mientras siga vigente. Ver `resolverPisoPrepago` en
 * `effective-limit.ts` para las reglas.
 *
 * Lo que SIGUE sin resolverse, y conviene saberlo:
 *
 *   - **La plata.** Nada de esto recupera un peso. Un upgrade DESDE un anual
 *     chico sigue quemando lo prepago: el piso plan1 no aporta nada si el plan
 *     nuevo ya es plan3. Esto arregla ENTITLEMENT, no facturacion.
 *
 *   - **La escalera.** Hay UN solo slot de piso. Dos downgrades dentro del
 *     mismo periodo conservan solo el mejor. Falla hacia MENOS cupo, nunca
 *     hacia mas, y nunca peor que antes de este cambio.
 *
 *   - **El `paused`.** Un PF que pausa en MP sigue cayendo a Free en el acto
 *     aunque tenga periodo pago. Es la misma injusticia de forma, pero es otra
 *     decision de politica y meterla acá seria cambiarla de contrabando.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";

import {
  SubscriptionStatus,
  effectiveWeightLimit,
  limitRank,
  resolverPisoPrepago,
} from "../effective-limit";
import { toSubscriptionState } from "../subscription-state";
import { SubscriptionTier } from "../tier-config";
import {
  MpApiError,
  MpClient,
  MpPreapproval,
  createMpClient,
} from "./client";
import {
  AthleteStatus,
  athleteStatusDesde,
  athleteStatusOtorga,
  hayCobroPendiente,
  mapMpStatus,
} from "./map-status";
import {
  MP_PLANS_COLLECTION,
  ProductoMp,
  lookupPlan,
} from "./tier-mapping";

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

export type ReconcileOutcome =
  | "written"
  | "unchanged"
  | "skipped-degraded"
  | "skipped-sin-plan"
  | "skipped-uid-no-coincide"
  /**
   * El plan esta `pending` y el PF YA tiene un entitlement pago vigente. Ver
   * la guarda de no-regresion mas abajo: escribirlo seria bajarlo a Free.
   */
  | "skipped-pending-no-pisa"
  /**
   * El plan fue reemplazado por otro y NOSOTROS lo dimos de baja. Ver la guarda
   * de reemplazo: su `cancelled` no habla del PF, habla de nuestra propia
   * escritura, y pisaria el plan que acaba de comprar.
   */
  | "skipped-reemplazado"
  | "sin-suscripcion"
  | "error-mp";

export interface ReconcileResult {
  planId: string;
  outcome: ReconcileOutcome;
  uid?: string;
  /**
   * Cual de los dos productos escribio este plan. Lo necesita el cliente para
   * saber que pantalla dibujar al volver del checkout.
   */
  producto?: ProductoMp;
  /** Solo para `producto: "trainer"`. El alumno no tiene tiers. */
  tier?: SubscriptionTier;
  /**
   * El estado en el vocabulario del PF, los cinco de `effective-limit.ts`.
   * Se reporta para LOS DOS productos: es lo que mira `estadoDesdeResultados`
   * en `reconcile-my-checkout.ts`, y traducirlo ahi tambien obligaria a ese
   * archivo a saber de productos.
   */
  status?: SubscriptionStatus;
  /** Solo para `producto: "athlete"`. Lo que se escribio de verdad. */
  athleteStatus?: AthleteStatus;
  /**
   * Hasta cuando el derecho sigue valiendo, en ms. Es la fecha que
   * `resolverFinDePeriodo` acaba de decidir.
   *
   * Se reporta —y no se deja que el llamador la busque— porque es lo que la
   * pantalla de baja tiene que decirle al usuario: «conservás el acceso hasta
   * el X». Sacarla de acá evita persistir un campo nuevo en `users/{uid}`, que
   * costaria pin en los dos verbos de `firestore.rules`.
   *
   * Ausente cuando no se pudo determinar por ningun camino de la cascada.
   */
  accesoHastaMs?: number;
  /**
   * Cuantas suscripciones VIEJAS se dieron de baja en MP porque este plan las
   * reemplaza. Casi siempre 0; un 1 es un cambio de plan que dejo de cobrarse
   * dos veces.
   */
  dadosDeBaja?: number;
}

export interface ReconcileDeps {
  mpClient: MpClient;
  /** Reloj inyectable: el abandono se testea sin esperar 30 dias. */
  nowMs: number;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * `next_payment_date` de MP → Timestamp, o `null`.
 *
 * MP lo manda como ISO 8601. Cualquier otra cosa se trata como ausente y se
 * reporta: preferimos perder el dato a escribir una fecha inventada, porque
 * `currentPeriodEnd` es lo que decide cuanto le dura el plan a un PF que se
 * dio de baja.
 */
export function parsePeriodEnd(
  raw: unknown,
  planId: string,
): Timestamp | null {
  if (raw == null) return null;
  if (typeof raw !== "string") {
    logger.warn("mp/reconcile: next_payment_date no es un string — se ignora", {
      planId,
      received: typeof raw,
    });
    return null;
  }
  const ms = Date.parse(raw);
  if (!Number.isFinite(ms)) {
    logger.warn("mp/reconcile: next_payment_date no es una fecha ISO valida", {
      planId,
      received: raw.slice(0, 40),
    });
    return null;
  }
  return Timestamp.fromMillis(ms);
}

/** `unknown` → Timestamp si tiene la forma, si no `null`. */
function comoTimestamp(v: unknown): Timestamp | null {
  return v != null && typeof (v as { toMillis?: unknown }).toMillis === "function"
    ? (v as Timestamp)
    : null;
}

/**
 * Un periodo de `auto_recurring` sumado a su `start_date`.
 *
 * Existe por un hallazgo de la prueba real contra MP, y la asimetria es fea:
 * una suscripcion CANCELADA que **pago** viene SIN `next_payment_date`,
 * mientras que una cancelada que **nunca pago** SI lo trae. O sea que el dato
 * esta justo cuando no importa y falta justo cuando si — y el que se queda sin
 * fecha es el que te pago.
 *
 * `start_date + frequency` es exactamente el periodo que esa persona compro.
 */
export function finDePeriodoDesdeAltaMs(autoRecurring: unknown): number | null {
  if (autoRecurring === null || typeof autoRecurring !== "object") return null;
  const ar = autoRecurring as {
    start_date?: unknown;
    frequency?: unknown;
    frequency_type?: unknown;
  };

  if (typeof ar.start_date !== "string") return null;
  const inicio = Date.parse(ar.start_date);
  if (!Number.isFinite(inicio)) return null;

  const n = ar.frequency;
  if (typeof n !== "number" || !Number.isInteger(n) || n <= 0 || n > 24) {
    return null;
  }

  // Solo se entiende "months". `days` existe en la API de MP pero TREINO no lo
  // usa, y sumar un periodo cuyo tipo no conocemos seria inventar una fecha —
  // el mismo error que `parsePeriodEnd` evita con las fechas mal formadas.
  if (ar.frequency_type !== "months") return null;

  // `setUTCMonth` normaliza el desborde de mes solo: enero 31 + 1 mes cae en
  // marzo 3, que es como cuenta el calendario y no hay que arreglarlo.
  const d = new Date(inicio);
  d.setUTCMonth(d.getUTCMonth() + n);
  return d.getTime();
}

interface FinDePeriodoInput {
  /** Lo que dijo MP en `next_payment_date`, ya parseado. */
  deMp: Timestamp | null;
  /** Lo que ya teniamos escrito en `subscription.currentPeriodEnd`. */
  yaGuardada: unknown;
  autoRecurring: unknown;
  status: SubscriptionStatus;
  planId: string;
}

/**
 * Hasta cuando le dura el plan PAGO a este PF.
 *
 * `effective-limit` le da el tier pago a un `cancelled` HASTA esta fecha. Que
 * quede en `null` significa sacarle el plan EN EL ACTO a alguien que pago el
 * periodo entero, asi que la cascada existe para no llegar nunca ahi:
 *
 *   1. `next_payment_date`, si MP lo mando.
 *   2. La que ya teniamos. Cubre al PF que estuvo meses suscripto: el barrido
 *      diario la fue refrescando mientras estaba activo.
 *   3. `start_date + frequency`. Cubre la baja el MISMO DIA, antes de que el
 *      barrido corriera una sola vez — ahi no hay nada guardado que conservar,
 *      y "me suscribi, me arrepenti, cancelo" es un comportamiento normal.
 *   4. `null`, y recien ahi nos rendimos.
 *
 * Los pasos 2 y 3 solo corren si MP ya dijo algo terminal. Mientras la
 * suscripcion sigue viva, que falte la fecha es informacion —no la sabemos— y
 * conservar una vieja seria inventar un periodo que quizas no se pago.
 */
export function resolverFinDePeriodo(
  i: FinDePeriodoInput,
): Timestamp | null {
  if (i.deMp !== null) return i.deMp;
  if (i.status !== "cancelled" && i.status !== "paused") return null;

  const previa = comoTimestamp(i.yaGuardada);
  if (previa !== null) return previa;

  const derivada = finDePeriodoDesdeAltaMs(i.autoRecurring);
  if (derivada === null) {
    logger.warn(
      "mp/reconcile: sin fecha de fin de periodo por ningun camino — el PF " +
        "pierde el plan pago en el acto",
      { planId: i.planId, status: i.status },
    );
    return null;
  }

  logger.info("mp/reconcile: fin de periodo derivado del alta", {
    planId: i.planId,
    status: i.status,
  });
  return Timestamp.fromMillis(derivada);
}

/**
 * El rango del limite (`null` = plan3 = SIN TOPE = el mayor) ahora se importa de
 * `effective-limit.ts` como `limitRank`.
 *
 * Habia una copia privada acá —`rangoDelLimite`— y otra en
 * `subscription-mail.ts`. El piso prepago necesitaba una tercera adentro del
 * propio modulo del limite, y tres copias de la misma trampa es exactamente como
 * se desincronizan: se centralizo donde vive el concepto.
 */

/** Los dos Timestamp son el mismo instante. Tolera nulls de los dos lados. */
function mismaFecha(
  a: Timestamp | null,
  b: unknown,
): boolean {
  const bMs =
    b != null && typeof (b as { toMillis?: unknown }).toMillis === "function"
      ? (b as { toMillis: () => number }).toMillis()
      : null;
  return (a?.toMillis() ?? null) === bMs;
}

/**
 * El campo de `mp_plans` que dice "a este plan lo dimos de baja NOSOTROS, porque
 * el PF se paso a este otro".
 *
 * Es distinto de `terminal` a proposito, y no alcanza con aquel: `terminal`
 * tambien lo pone una baja que hizo el PF, y esa SI tiene que poder escribir
 * `cancelled` sobre su `subscription`. Este campo marca la unica baja cuyo
 * `cancelled` no habla del entrenador sino de nuestra propia escritura.
 */
const CAMPO_REEMPLAZO = "supersededBy";

/**
 * Los dos motivos de `terminal` que escribe este archivo. Son constantes y no
 * literales sueltos porque `puedeSeguirCobrando` COMPARA contra uno de ellos:
 * escritos a mano en dos lados, el dia que alguien cambie una redaccion el
 * filtro deja de reconocer su propio motivo y el bug es silencioso.
 *
 * (El tercer `terminal` que existe no tiene motivo: el de `status === cancelled`
 * mas abajo. Que la baja del PF sea la unica SIN motivo es deliberado — ver
 * `puedeSeguirCobrando`.)
 */
const MOTIVO_ABANDONO = "checkout abandonado";
const MOTIVO_REEMPLAZO = "reemplazado por otro plan";

/**
 * Este plan todavia PUEDE estar cobrandole al PF, asi que hay que mirarlo.
 *
 * `terminal` NO significa "muerto", y confundir las dos cosas fue un bug real de
 * la primera version de la baja: filtraba con `terminal === true` pelado y
 * dejaba afuera al checkout ABANDONADO que despues se pago.
 *
 * Esa poblacion existe y el repo la construyo a proposito. `esAbandonado` marca
 * terminal a los 30 dias, pero el `init_point` de un plan NO VENCE: el PF puede
 * encontrar la pestaña vieja al dia 35 y pagarla. `reconcile-my-checkout.ts` lo
 * documenta y lo rescata justamente por eso — su `planesDelPf` sigue
 * consultando los terminal CON motivo porque «un terminal con motivo es una
 * apuesta sobre el futuro, no un hecho».
 *
 * Con el filtro pelado, ese PF hacia upgrade y su plan viejo —vivo y
 * cobrando— quedaba fuera de la baja PARA SIEMPRE: el barrido tampoco lo
 * reconcilia, asi que ninguna corrida futura lo reintentaba. Cobro doble
 * permanente, justo en el caso que este archivo existe para cerrar.
 *
 * Los otros dos terminal si son hechos y se saltean: una baja del PF (que MP ya
 * confirmo con `cancelled`) y una baja NUESTRA que MP acepto.
 */
export function puedeSeguirCobrando(datos: Record<string, unknown> | undefined): boolean {
  if (datos?.terminal !== true) return true;
  return datos?.terminalReason === MOTIVO_ABANDONO;
}

/**
 * Deja escrito que este plan quedo REEMPLAZADO por otro.
 *
 * Se llama ANTES de pedirle la baja a MP — ver el comentario de
 * `darDeBajaUnPlan` para por que el orden es el punto entero. NO marca
 * `terminal`: eso es un hecho de MP y se escribe recien cuando la baja confirma.
 */
async function marcarReemplazado(
  app: App,
  planViejo: string,
  planVigente: string,
): Promise<void> {
  await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .doc(planViejo)
    .set({ [CAMPO_REEMPLAZO]: planVigente }, { merge: true });
}

/**
 * La suscripcion todavia puede cobrar, o sea que hay que darla de baja.
 *
 * Solo `cancelled` queda afuera, y un estado que NO conocemos cae adentro — al
 * reves que en el resto del archivo. La asimetria es deliberada y la decide la
 * consecuencia de equivocarse: acá ya sabemos que esta suscripcion quedo
 * reemplazada, asi que no cancelarla es seguir cobrandole dos veces a alguien.
 * Un PUT de mas sobre algo ya muerto da un error que se ve en el log; un PUT de
 * menos es plata del PF, todos los meses, en silencio.
 */
export function sigueViva(raw: unknown): boolean {
  return raw !== "cancelled";
}

/**
 * Da de baja en MP todas las suscripciones de UN plan viejo y, si MP acepto, lo
 * saca del barrido marcandolo reemplazado.
 *
 * Total: nunca tira. Devuelve cuantas cancelo.
 */
async function darDeBajaUnPlan(
  app: App,
  planViejo: string,
  planVigente: string,
  deps: ReconcileDeps,
): Promise<number> {
  // ── PRIMERO SE MARCA, DESPUES SE CANCELA. El orden es el arreglo ──
  //
  // La version anterior escribia `supersededBy` DESPUES del PUT, y eso dejaba
  // desarmada justo la guarda que este diseño necesita. El agujero no pedia que
  // MP fallara: alcanzaba con que la RESPUESTA se perdiera. `cancelPreapproval`
  // tira igual si MP contesta 204 o un 2xx con body vacio (`request` exige un
  // objeto JSON), si se agota el `AbortSignal.timeout` de 10s con la baja ya
  // aplicada, o si la instancia muere entre el PUT y el write. En los tres casos
  // la suscripcion quedaba CANCELADA en MP y el plan viejo sin marcar — y a la
  // corrida siguiente MP contestaba `cancelled`, que si puede bajar el limite.
  // O sea: el downgrade sobre el que acaba de pagar, que es exactamente lo que
  // la guarda existe para impedir.
  //
  // Marcando antes, los dos campos dicen cosas distintas y cada uno se escribe
  // cuando de verdad se sabe:
  //
  //   `supersededBy` — **una decision NUESTRA**, y no depende de MP para nada:
  //   sale de comparar dos `createdAt` que ya tenemos. Significa "el estado de
  //   este plan ya no es el del PF". Vale igual si la baja falla: el PF compro
  //   el plan nuevo, y el viejo no puede definir su entitlement pase lo que pase.
  //
  //   `terminal` — **un hecho de MP**, y por eso sigue escribiendose recien
  //   cuando la baja resolvio bien. Significa "dejá de preguntar por este plan".
  //
  // Con eso los dos finales feos convergen solos: si el PUT salio y no nos
  // enteramos, mañana el search devuelve `cancelled`, no se manda ningun PUT y
  // se marca terminal. Si el PUT no salio, mañana se reintenta. En los dos
  // casos el PF conserva el plan que compro mientras tanto.
  await marcarReemplazado(app, planViejo, planVigente);

  let subs: MpPreapproval[];
  try {
    subs = await deps.mpClient.searchPreapprovalsByPlan(planViejo);
  } catch (e) {
    const err = e as MpApiError;
    logger.error(
      "mp/reconcile: no se pudo buscar que dar de baja del plan reemplazado",
      { planViejo, planVigente, status: err.status, retryable: err.retryable },
    );
    return 0;
  }

  // Un plan sin ninguna suscripcion nunca cobro: es un checkout que el PF abrio
  // y abandono antes de comprar otro. NO se marca terminal acá. Un `[]` tambien
  // puede ser MP contestando raro, y sacarlo del barrido por eso seria dejar de
  // mirar —y de intentar cancelar— una suscripcion que si existe y si cobra. De
  // los abandonados de verdad se encarga `esAbandonado` a los 30 dias.
  if (subs.length === 0) return 0;

  let cancelados = 0;
  for (const sub of subs) {
    if (!sigueViva(sub.status)) continue;

    const preapprovalId = sub.id;
    if (typeof preapprovalId !== "string" || preapprovalId === "") {
      logger.error("mp/reconcile: una suscripcion a dar de baja vino sin id", {
        planViejo,
        planVigente,
      });
      // Sin marcar terminal: quedo algo vivo que no supimos tocar.
      return cancelados;
    }

    try {
      await deps.mpClient.cancelPreapproval(preapprovalId);
    } catch (e) {
      const err = e as MpApiError;
      logger.error(
        "mp/reconcile: la baja de la suscripcion vieja no confirmo — puede " +
          "haber un COBRO DOBLE vivo",
        {
          planViejo,
          planVigente,
          preapprovalId,
          status: err.status,
          retryable: err.retryable,
          body: err.body,
        },
      );
      // "No confirmo" y no "MP la rechazo": desde acá NO se puede distinguir un
      // 400 —donde la baja no ocurrio— de un timeout con la baja ya aplicada.
      // Por eso se sale sin marcar terminal: el plan sigue en el barrido y la
      // corrida de mañana averigua cual de las dos fue, preguntandole a MP.
      return cancelados;
    }

    cancelados += 1;
    logger.info("mp/reconcile: suscripcion vieja dada de baja en MP", {
      planViejo,
      planVigente,
      preapprovalId,
    });
  }

  // Se llega acá con todo lo vivo cancelado, o con un plan cuyas suscripciones
  // MP ya daba por muertas. En los dos casos no queda nada que cobre.
  await marcarTerminal(app, planViejo, MOTIVO_REEMPLAZO);
  return cancelados;
}

/**
 * Da de baja lo que el plan [planVigente] —recien confirmado por MP— reemplaza.
 *
 * Ver el encabezado para POR QUE es acá y no al abrir el checkout. Lo que se
 * decide en esta funcion es CUALES: solo los planes del mismo uid ESTRICTAMENTE
 * MAS VIEJOS que el confirmado.
 *
 * Total: nunca tira. Devuelve cuantas suscripciones se cancelaron.
 */
async function darDeBajaLosReemplazados(
  app: App,
  uid: string,
  planVigente: string,
  altaVigente: Timestamp | null,
  deps: ReconcileDeps,
): Promise<number> {
  if (altaVigente === null) {
    // Sin la fecha de alta del plan confirmado no hay forma de saber cual es el
    // viejo, y "el otro" no sirve: el barrido los recorre en el orden que
    // Firestore devuelva, asi que adivinar es cancelarle al PF el plan que
    // ACABA de comprar. Se prefiere el cobro doble —que se ve, se reclama y se
    // devuelve— a una baja equivocada, que en MP es irreversible.
    logger.warn(
      "mp/reconcile: el plan confirmado no tiene createdAt legible — no se da " +
        "de baja nada",
      { planVigente, uid },
    );
    return 0;
  }

  // `where` sobre un solo campo: Firestore lo resuelve con el indice automatico,
  // sin indice compuesto que crear ni desplegar. Se filtra por uid y no se
  // recorre la coleccion entera porque esto corre una vez POR PLAN CONFIRMADO.
  //
  // El costo hay que decirlo, porque esta funcion no corre solo de madrugada:
  // `reconcile-my-checkout.ts` llama a `reconcileSubscription` cuando el PF
  // VUELVE del checkout, y ahi cada plan viejo que se visite son dos llamadas a
  // MP en el camino de una pantalla que alguien esta mirando. Queda acotado por
  // tres cosas que ya existen: los terminales se saltean, `esAbandonado` marca
  // terminal a los 30 dias todo checkout que nadie pago, y la ventana de reuso
  // de `create-preapproval.ts` evita que dos clicks abran dos planes. O sea que
  // el peor caso realista son los pocos checkouts que ese PF abrio en el ultimo
  // mes, no su historial entero.
  const otros = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .where("uid", "==", uid)
    .get();

  let cancelados = 0;
  for (const doc of otros.docs) {
    if (doc.id === planVigente) continue;

    const datos = doc.data();
    // NO es `terminal === true`: ver `puedeSeguirCobrando`. Un terminal por
    // ABANDONO puede tener una suscripcion viva —el `init_point` no vence— y
    // saltearlo dejaba ese cobro doble sin cerrar para siempre.
    if (!puedeSeguirCobrando(datos)) continue;

    const alta = comoTimestamp(datos?.createdAt);
    // Sin fecha no se toca, y el `>=` es estricto a proposito: solo lo ANTERIOR
    // al plan confirmado se da de baja.
    if (alta === null || alta.toMillis() >= altaVigente.toMillis()) continue;

    cancelados += await darDeBajaUnPlan(app, doc.id, planVigente, deps);
  }

  return cancelados;
}

/**
 * Reconcilia UNA suscripcion contra MP.
 *
 * Total: nunca tira. Cualquier fallo se reporta en el `outcome` — un barrido
 * que se cae por un PF deja a todos los demas sin reconciliar.
 */
/**
 * Escribe el derecho del ALUMNO. El espejo de lo que el resto de
 * `reconcileSubscription` hace para el PF, con tres diferencias que importan.
 *
 * ── 1. Escribe UN SOLO CAMPO, y eso es load-bearing ──
 *
 * `users/{uid}.athleteSubscription` es `{ status }` y nada mas. No es
 * minimalismo estetico: `athletePaywallInputChanged`
 * (`athlete-paywall-enforced.ts`) compara **el mapa entero serializado**, asi
 * que cualquier campo volatil adentro —`updatedAt`, `currentPeriodEnd`,
 * `lastEventId`— dispararia `syncAthletePaywallOnUser` en cada evento de MP. Y
 * con el paywall prendido, ese trigger paga una query a `trainer_links` por
 * alumno y por evento.
 *
 * Lo mismo ya lo documenta `rc/webhook.ts`, que es el otro escritor de este
 * campo. Hay un test que fija que el mapa escrito tiene exactamente una clave.
 *
 * ── 2. La fecha de fin de periodo vive en `mp_plans/{planId}` ──
 *
 * Consecuencia directa de lo anterior: la fecha no puede ir en el mapa, y un
 * campo hermano en `users/{uid}` tampoco es gratis —necesitaria pin en los dos
 * verbos de `firestore.rules`, un archivo que ya cruzo los 256 KiB una vez.
 * `mp_plans` ya es CF-only por regla y este reconciliador ya lo lee.
 * **Costo en reglas: cero lineas.**
 *
 * ── 3. `terminal` NO se marca por `cancelled` a secas ──
 *
 * Ver la guarda al final. Es el unico lugar donde este escritor no puede
 * copiar al del PF, y copiarlo le regalaba acceso permanente al alumno.
 */
async function escribirSuscripcionDeAlumno(i: {
  app: App;
  planId: string;
  uid: string;
  mp: MpPreapproval;
  status: SubscriptionStatus;
  planDoc: Record<string, unknown> | undefined;
  deps: ReconcileDeps;
}): Promise<ReconcileResult> {
  const { app, planId, uid, mp, status, planDoc, deps } = i;

  const db = getFirestore(app);
  const userRef = db.collection("users").doc(uid);
  const planRef = db.collection(MP_PLANS_COLLECTION).doc(planId);

  const userData = (await userRef.get()).data();
  const actual = userData?.athleteSubscription as
    | Record<string, unknown>
    | undefined;
  const statusPrevio =
    typeof actual?.status === "string" ? actual.status : undefined;

  // La fecha sale de la MISMA cascada que la del PF, cambiando de donde se lee
  // la anterior: del plan y no del usuario.
  const periodEnd = resolverFinDePeriodo({
    deMp: parsePeriodEnd(mp.next_payment_date, planId),
    yaGuardada: planDoc?.currentPeriodEnd,
    autoRecurring: mp.auto_recurring,
    status,
    planId,
  });

  const athleteStatus = athleteStatusDesde(
    status,
    periodEnd === null ? null : periodEnd.toMillis(),
    deps.nowMs,
  );

  // ── GUARDA DE NO-REGRESION: un `pending` NUNCA pisa un derecho vigente ──
  //
  // Misma politica que la del PF, mismo caso real: nada impide abrir un
  // checkout estando ya suscripto, asi que un alumno que pasa de mensual a
  // anual queda con DOS documentos en `mp_plans`. El barrido los recorre a los
  // dos, y sin esta guarda el `pending` del plan nuevo le corta las funciones
  // pagas a alguien que acaba de intentar pagarnos mas.
  //
  // Solo `pending`. `paused` y `cancelled` SI bajan el derecho: ahi MP dijo
  // algo terminal sobre la suscripcion que el alumno tenia, no sobre una que
  // esta naciendo.
  if (
    status === "pending" &&
    statusPrevio !== undefined &&
    athleteStatusOtorga(statusPrevio as AthleteStatus)
  ) {
    logger.info("mp/reconcile: `pending` que no pisa un derecho vigente", {
      planId,
      uid,
      producto: "athlete",
      statusPrevio,
    });
    return {
      planId,
      outcome: "skipped-pending-no-pisa",
      uid,
      producto: "athlete",
      status,
    };
  }

  const sinCambios = statusPrevio === athleteStatus;

  if (!sinCambios) {
    await userRef.set(
      // UN SOLO CAMPO. Ver el encabezado — agregarle uno rompe el guard
      // anti-loop de `athletePaywallInputChanged`.
      { athleteSubscription: { status: athleteStatus } },
      // `merge` y no `set` pelado: el documento de usuario tiene el perfil
      // entero. Sin merge, reconciliar una suscripcion borraria la cuenta.
      { merge: true },
    );

    logger.info("mp/reconcile: derecho del alumno actualizado", {
      planId,
      uid,
      status,
      athleteStatus,
    });
  }

  // ── La fecha se guarda aunque el status NO haya cambiado ──
  //
  // Es lo que hace posible el flip `active → expired` del dia que vence el
  // periodo. Colgarla del `if (!sinCambios)` seria un bug de la misma familia
  // que el del `terminal`: el caso normal de una baja es status `cancelled`
  // con derecho `active` y fecha nueva, y si esa fecha no se persiste, el
  // barrido no tiene contra que comparar.
  if (periodEnd !== null && !mismaFecha(periodEnd, planDoc?.currentPeriodEnd)) {
    await planRef.set({ currentPeriodEnd: periodEnd }, { merge: true });
  }

  // ── ⚠️ `terminal` SOLO cuando el derecho YA se apago ──
  //
  // El escritor del PF marca `terminal` apenas MP dice `cancelled`, y eso lo
  // saca del barrido para siempre. Para el PF es inofensivo: su
  // `currentPeriodEnd` vive en `users/{uid}.subscription` y
  // `effectiveWeightLimit` la relee en cada corrida de `sweepEntitlements`, asi
  // que el limite cae solo cuando la fecha pasa, sin que nadie escriba nada.
  //
  // **Para el alumno no existe ese mecanismo.** Su derecho es un string, y el
  // unico que puede cambiarlo de `active` a `expired` es una ESCRITURA. La
  // unica escritura que queda despues de la baja es la del barrido. Marcar
  // `terminal` ahi lo saca del barrido, y el alumno que se dio de baja se queda
  // con acceso **para siempre**.
  //
  // Por eso la condicion tiene dos partes: MP dijo `cancelled` **y** el periodo
  // pago ya termino. Mientras siga corriendo, el plan se queda en el barrido —
  // que es exactamente para lo que el barrido existe.
  if (status === "cancelled" && athleteStatus === "expired") {
    await planRef.set({ terminal: true }, { merge: true });
  }

  return {
    planId,
    outcome: sinCambios ? "unchanged" : "written",
    uid,
    producto: "athlete",
    status,
    athleteStatus,
    ...(periodEnd === null ? {} : { accesoHastaMs: periodEnd.toMillis() }),
  };
}

export async function reconcileSubscription(
  app: App,
  planId: string,
  deps: ReconcileDeps,
): Promise<ReconcileResult> {
  // ── GUARDA DE REEMPLAZO: lo que dimos de baja nosotros no escribe nada ──
  //
  // Se lee el documento del plan ANTES de salir a la red, y esa lectura de mas
  // —`lookupPlan` mas abajo vuelve a leerlo— se paga a proposito por dos cosas
  // que valen mas que un get de Firestore: acá ahorra una llamada a MP, y este
  // campo es de CONTROL del barrido, no parte del mapeo. Metérselo a `lookupPlan`
  // mezclaria "de que plan es esta suscripcion" con "hay que seguir mirandola",
  // que son dos preguntas distintas.
  //
  // El caso ocurre DENTRO de la misma corrida: `reconcileAllSubscriptions` toma
  // el snapshot de `mp_plans` una sola vez, al principio. Cuando el plan nuevo
  // se confirma y damos de baja el viejo, el barrido todavia tiene el viejo en
  // la mano como no-terminal — lo va a reconciliar, MP le va a contestar
  // `cancelled`, y `cancelled` SI puede bajar el limite. Sin esta guarda, la
  // ultima escritura de la noche seria un `cancelled` encima del plan que el PF
  // acaba de comprar, con su mail de degradacion y sus alumnos bloqueados.
  const planSnap = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .doc(planId)
    .get();
  const planDoc = planSnap.data();

  const reemplazadoPor = planDoc?.[CAMPO_REEMPLAZO];
  if (typeof reemplazadoPor === "string" && reemplazadoPor !== "") {
    logger.info("mp/reconcile: plan reemplazado — su estado ya no es el del PF", {
      planId,
      reemplazadoPor,
    });
    return { planId, outcome: "skipped-reemplazado" };
  }

  // Se busca POR PLAN y no por id de suscripcion, y esa es la diferencia con la
  // version anterior: el plan lo creamos NOSOTROS y su id ya esta guardado en
  // `mp_plans`. De la suscripcion no sabemos nada hasta que alguien paga — y no
  // esta verificado que herede el `external_reference` del plan, asi que
  // buscarla por ahi seria apostar a lo que no sabemos.
  let subs;
  try {
    subs = await deps.mpClient.searchPreapprovalsByPlan(planId);
  } catch (e) {
    const err = e as MpApiError;
    logger.error("mp/reconcile: no se pudieron buscar las suscripciones del plan", {
      planId: planId,
      status: err.status,
      retryable: err.retryable,
    });
    return { planId, outcome: "error-mp" };
  }

  // Cero suscripciones es el estado NORMAL de un plan recien creado: el PF
  // abrio el checkout y todavia no pago, o lo abandono. No es un error y no se
  // logea — con un plan por checkout, la mayoria de los planes viejos van a
  // estar asi para siempre.
  if (subs.length === 0) {
    return { planId, outcome: "sin-suscripcion" };
  }
  // Mas de una sobre el mismo plan no deberia pasar —cada checkout crea el
  // suyo— pero si pasa se toma la primera y se avisa, en vez de elegir en
  // silencio.
  if (subs.length > 1) {
    logger.warn("mp/reconcile: el plan tiene mas de una suscripcion", {
      planId: planId,
      cuantas: subs.length,
    });
  }
  const mp = subs[0];

  const monto = (mp.auto_recurring as { transaction_amount?: unknown } | undefined)
    ?.transaction_amount;
  const mapping = await lookupPlan(app, planId, monto);

  if (!mapping) {
    // Ni el documento ni el monto nos dicen de que plan es. Escribir un tier
    // adivinado seria regalar o robar cupo; no escribir deja el estado anterior,
    // que es el ultimo que SI entendimos.
    logger.error("mp/reconcile: no se pudo determinar el plan — no se escribe", {
      planId,
      monto,
    });
    return { planId, outcome: "skipped-sin-plan" };
  }

  // El uid sale del mapeo; si el mapeo cayo al fallback por monto no lo trae, y
  // ahi lo pone MP en `external_reference` — que lo mandamos nosotros al crear.
  const externo = mp.external_reference;
  const uid = mapping.uid || (typeof externo === "string" ? externo : "");
  if (!uid) {
    logger.error("mp/reconcile: sin uid ni en el mapeo ni en external_reference", {
      planId,
    });
    return { planId, outcome: "skipped-sin-plan" };
  }

  // Los dos existen y NO coinciden: o alguien toco el documento de mapeo, o MP
  // nos esta contestando por otro recurso. En cualquiera de los dos casos
  // escribir le daria el plan de una persona a otra.
  if (
    mapping.uid &&
    typeof externo === "string" &&
    externo !== "" &&
    externo !== mapping.uid
  ) {
    logger.error(
      "mp/reconcile: el uid del mapeo no coincide con external_reference",
      { planId, mapeo: mapping.uid, externalReference: externo },
    );
    return { planId, outcome: "skipped-uid-no-coincide" };
  }

  const { status, degraded } = mapMpStatus({
    raw: mp.status,
    cobroPendiente: hayCobroPendiente(mp.summarized),
    trainerId: uid,
  });

  if (degraded) {
    // Ver el encabezado: escribir el fallback bajaria al PF a Free y el barrido
    // de las 04:00 le bloquearia alumnos por un dato que no entendimos.
    logger.error("mp/reconcile: estado de MP ininteligible — NO se escribe", {
      planId,
      uid,
      producto: mapping.producto,
      recibido: mp.status,
    });
    return {
      planId,
      outcome: "skipped-degraded",
      uid,
      producto: mapping.producto,
      ...(mapping.producto === "trainer" ? { tier: mapping.tier } : {}),
    };
  }

  // ── EL CORTE POR PRODUCTO ──
  //
  // `mp_plans` es una sola coleccion para los dos, asi que este reconciliador
  // recibe planes de alumno tanto por el webhook como por el barrido, que
  // escanea la coleccion entera.
  //
  // Todo lo que viene DESPUES del corte escribe `users/{uid}.subscription` con
  // un tier de entrenador. Correrlo sobre un alumno no seria un no-op: le
  // escribiria un entitlement de PF, con cupo de alumnos y todo.
  //
  // El corte esta ACA y no antes de `mapMpStatus` porque los dos escritores
  // necesitan `status` y `degraded`: son dos proyecciones del MISMO estado de
  // MP, no dos lecturas distintas. Traducir dos veces seria la forma mas facil
  // de que un dia digan cosas diferentes.
  if (mapping.producto === "athlete") {
    return escribirSuscripcionDeAlumno({
      app,
      planId,
      uid,
      mp,
      status,
      planDoc,
      deps,
    });
  }

  const userRef = getFirestore(app).collection("users").doc(uid);
  const userData = (await userRef.get()).data();
  const actual = userData?.subscription as
    | Record<string, unknown>
    | undefined;

  // ── GUARDA DE NO-REGRESION: un `pending` NUNCA pisa un entitlement pago ──
  //
  // `effective-limit.ts` le da el limite FREE a un `pending`, asi que escribirlo
  // sobre alguien que hoy tiene plan pago no es informativo: es un DOWNGRADE. Y
  // no espera al barrido de las 04:00 — el write dispara
  // `syncEntitlementsOnSubscription`, que en la misma invocacion le bloquea
  // alumnos y le manda un mail de degradacion.
  //
  // El caso no es teorico y es justo el del PF que MAS nos paga: nada impide
  // abrir un checkout estando ya suscripto (`create-preapproval.ts` solo valida
  // el rol), asi que un plan2 que quiere pasar a plan3 queda con DOS documentos
  // en `mp_plans` con su uid. El barrido los recorre a los dos y escribe por
  // cada uno; sin esta guarda, el `pending` del plan nuevo le vacia el padron a
  // alguien que acaba de intentar pagarnos mas.
  //
  // Es la misma politica que ya gobierna `degraded` y que documenta
  // `subscription-state.ts`: **frenar trabajo nuevo nunca puede revocar
  // relaciones existentes.** Un `pending` es exactamente eso — trabajo nuevo
  // que todavia no se confirmo.
  //
  // Solo aplica a `pending`. `paused` y `cancelled` SI bajan el limite, y tienen
  // que poder hacerlo: ahi MP dijo algo terminal sobre la suscripcion que el PF
  // tenia, no sobre una que esta naciendo.
  // El estado saneado de lo que hay HOY. Se lee una sola vez y lo usan las dos
  // cosas que miran hacia atras: la guarda de `pending` y el piso prepago.
  const { state: previo } = toSubscriptionState(userData, uid);

  if (status === "pending") {
    const limitePrevio = effectiveWeightLimit(previo, deps.nowMs);
    // Se compara contra el limite de un PF SIN suscripcion, no contra un 2
    // escrito a mano: si algun dia Free cambia de tope, la guarda lo sigue sola.
    if (
      limitRank(limitePrevio) > limitRank(effectiveWeightLimit(null, deps.nowMs))
    ) {
      logger.info(
        "mp/reconcile: `pending` que no pisa un entitlement pago vigente",
        { planId, uid, tierEntrante: mapping.tier, limitePrevio },
      );
      return {
        planId,
        outcome: "skipped-pending-no-pisa",
        uid,
        producto: "trainer",
        tier: mapping.tier,
        status,
      };
    }
  }

  const periodEnd = resolverFinDePeriodo({
    deMp: parsePeriodEnd(mp.next_payment_date, planId),
    yaGuardada: actual?.currentPeriodEnd,
    autoRecurring: mp.auto_recurring,
    status,
    planId,
  });

  // ── EL PISO PREPAGO: lo que el PF ya pago y este write estaba tirando ──
  //
  // El dato no viene de ningun lado nuevo: `previo` es lo que estamos por PISAR,
  // y es exactamente lo que se perdia. Cero llamadas de mas a MP, y por lo tanto
  // el piso NO depende de que la baja de la vieja confirme — un 429 de Mercado
  // Pago no le toca el entitlement al PF.
  //
  // Va en el MISMO `set` que el resto, y eso no es prolijidad: cada escritura de
  // `users/{uid}` dispara `syncEntitlementsOnSubscription`. En dos escrituras,
  // la primera le bloquea alumnos y le manda el mail de degradacion, y la
  // segunda lo desbloquea. Una escritura, un disparo.
  //
  // Consecuencia que cae sola y es la mitad del valor: en el instante del cambio
  // de plan `limitBefore == limitAfter`, asi que `decideSubscriptionMail` no
  // manda nada y `sync-entitlements` no bloquea a nadie. Sin una sola rama nueva
  // en esos dos archivos.
  const piso = resolverPisoPrepago(previo, mapping.tier, status, deps.nowMs);
  const prepaidUntil = piso === null ? null : Timestamp.fromMillis(piso.untilMs);

  if (
    piso === null &&
    previo != null &&
    (status === "active" || status === "grace") &&
    limitRank(effectiveWeightLimit(previo, deps.nowMs)) >
      limitRank(effectiveWeightLimit({ tier: mapping.tier, status }, deps.nowMs))
  ) {
    // Le bajamos el cupo EN EL ACTO a alguien y no pudimos armarle piso —
    // tipicamente porque su `currentPeriodEnd` esta en null (los PF sembrados a
    // mano con el Admin SDK no lo tienen). Hay que poder encontrarlo despues.
    logger.warn(
      "mp/reconcile: downgrade sin piso prepago — el PF pierde cupo en el acto",
      { planId, uid, tierPrevio: previo.tier, tierEntrante: mapping.tier },
    );
  }

  const sinCambios =
    actual != null &&
    actual.tier === mapping.tier &&
    actual.status === status &&
    mismaFecha(periodEnd, actual.currentPeriodEnd) &&
    (actual.prepaidTier ?? null) === (piso === null ? null : piso.tier) &&
    mismaFecha(prepaidUntil, actual.prepaidUntil);

  if (!sinCambios) {
    await userRef.set(
      {
        subscription: {
          tier: mapping.tier,
          status,
          currentPeriodEnd: periodEnd,
          // EXPLICITOS y nunca omitidos: `merge` es superficial sobre el mapa
          // `subscription`, asi que omitirlos confiando en que se preserven es
          // apostar a un comportamiento que no existe.
          prepaidTier: piso === null ? null : piso.tier,
          prepaidUntil,
        },
      },
      // `merge` y no `set` pelado: el documento de usuario tiene el perfil
      // entero. Sin merge, reconciliar una suscripcion borraria la cuenta.
      { merge: true },
    );

    // La baja es terminal en MP: no se reactiva un preapproval cancelado, se
    // crea uno nuevo con otro id. Marcarlo saca este id del barrido y le ahorra
    // una llamada diaria a MP para siempre.
    if (status === "cancelled") {
      await getFirestore(app)
        .collection(MP_PLANS_COLLECTION)
        .doc(planId)
        .set({ terminal: true }, { merge: true });
    }

    logger.info("mp/reconcile: suscripcion actualizada", {
      planId,
      uid,
      tier: mapping.tier,
      status,
    });
  }

  // ── LA BAJA DE LO QUE ESTE PLAN REEMPLAZA ──
  //
  // Va DESPUES de escribir y fuera del `if`, por dos razones que son la misma:
  //
  //   - Corre tambien con `unchanged`. Si una noche MP rechaza la baja, la
  //     suscripcion nueva ya quedo escrita y la corrida siguiente la ve sin
  //     cambios. Colgada del `written`, un unico 429 dejaba el cobro doble vivo
  //     para siempre.
  //
  //   - Solo con la nueva CONFIRMADA. `active` y `grace` son las dos caras del
  //     `authorized` de MP: en las dos hay medio de pago cargado y la nueva va a
  //     cobrar. Un `pending` no — ahi el PF todavia no compro nada, y darle de
  //     baja lo que ya paga a cambio de una intencion es justo el error que este
  //     diseño evita.
  const dadosDeBaja =
    status === "active" || status === "grace"
      ? await darDeBajaLosReemplazados(
        app,
        uid,
        planId,
        comoTimestamp(planDoc?.createdAt),
        deps,
      )
      : 0;

  return {
    planId,
    outcome: sinCambios ? "unchanged" : "written",
    uid,
    producto: "trainer",
    tier: mapping.tier,
    status,
    dadosDeBaja,
    ...(periodEnd === null ? {} : { accesoHastaMs: periodEnd.toMillis() }),
  };
}

export interface SweepResult {
  total: number;
  written: number;
  unchanged: number;
  skipped: number;
  errors: number;
  /** Planes que se dieron de baja del barrido por checkout abandonado. */
  abandonados: number;
  /**
   * Suscripciones VIEJAS canceladas en MP por un cambio de plan. Cada una es un
   * cobro doble que dejo de ocurrir, asi que vale la pena verlo en el log de la
   * corrida: si empieza a subir, algo esta creando checkouts de mas.
   */
  dadosDeBaja: number;
}

/**
 * Cuanto se espera antes de dar por abandonado un plan que nunca tuvo
 * suscripcion.
 *
 * Existe por el costo del diseño de UN PLAN POR CHECKOUT: cada PF que toca
 * "ELEGIR PLAN" y no paga deja un plan que el barrido consultaria contra MP
 * todas las noches PARA SIEMPRE. Con cien PF mirando precios y la mitad
 * abandonando, en un año son miles de llamadas diarias por suscripciones que
 * nunca existieron.
 *
 * 30 dias y no 1: el `init_point` de un plan no vence en el acto, y alguien
 * que abrio el checkout el martes y pago el jueves tiene que seguir andando.
 * El costo de esperar de mas son unas pocas llamadas; el de cortar temprano es
 * un PF que paga y al que nunca le acreditamos el plan.
 */
const ABANDONO_MS = 30 * 24 * 60 * 60 * 1000;

/** Si un plan sin suscripcion ya es viejo como para dejar de consultarlo. */
export function esAbandonado(createdAt: unknown, nowMs: number): boolean {
  const ms = comoTimestamp(createdAt)?.toMillis();
  // Sin fecha NO se abandona. Un documento viejo sin `createdAt` —o con el
  // sentinel de serverTimestamp todavia sin resolver— se sigue consultando:
  // gastar una llamada de mas es infinitamente mas barato que dejar de mirar
  // una suscripcion que si existe.
  if (ms === undefined) return false;
  return nowMs - ms > ABANDONO_MS;
}

/**
 * Saca un plan del barrido. `merge` porque el resto del mapeo —uid, tier,
 * cycle— tiene que sobrevivir: sirve para auditar quien compro que, aunque ya
 * no se consulte.
 */
async function marcarTerminal(
  app: App,
  planId: string,
  motivo: string,
): Promise<void> {
  await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .doc(planId)
    .set({ terminal: true, terminalReason: motivo }, { merge: true });
  logger.info("mp/reconcile: plan sacado del barrido", { planId, motivo });
}

/**
 * Reconcilia todo lo que conocemos. Handler puro para poder testearlo sin el
 * arnes de `onSchedule`.
 *
 * Recorre `mp_preapprovals` salteando los terminales. Es un scan de coleccion:
 * a la escala de hoy —decenas de entrenadores— es trivial, y cada documento
 * salteado es una llamada menos a MP. Cuando el volumen lo justifique, el filtro
 * natural es un `where('terminal', '!=', true)` con su indice; hoy seria
 * infraestructura para un problema que no existe.
 *
 * SECUENCIAL a proposito. En paralelo son N requests simultaneos a MP, que
 * responde 429 y nos deja sin reconciliar a la mitad de los PF. El barrido tiene
 * toda la madrugada.
 */
export async function reconcileAllSubscriptions(
  app: App,
  deps: ReconcileDeps,
): Promise<SweepResult> {
  const snap = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .get();

  const r: SweepResult = {
    total: 0,
    written: 0,
    unchanged: 0,
    skipped: 0,
    errors: 0,
    abandonados: 0,
    dadosDeBaja: 0,
  };

  for (const doc of snap.docs) {
    const datos = doc.data();
    if (datos?.terminal === true) continue;
    r.total += 1;

    // El try es por-PF, igual que en `entitlement-triggers`: un documento roto
    // no puede frenar el barrido de todos los demas.
    try {
      const res = await reconcileSubscription(app, doc.id, deps);
      if (res.outcome === "written") r.written += 1;
      else if (res.outcome === "unchanged") r.unchanged += 1;
      else if (res.outcome === "error-mp") r.errors += 1;
      else r.skipped += 1;
      r.dadosDeBaja += res.dadosDeBaja ?? 0;

      if (
        res.outcome === "sin-suscripcion" &&
        esAbandonado(datos?.createdAt, deps.nowMs)
      ) {
        await marcarTerminal(app, doc.id, MOTIVO_ABANDONO);
        r.abandonados += 1;
      }
    } catch (err) {
      logger.error("mp/reconcile: error inesperado en un preapproval", {
        planId: doc.id,
        err,
      });
      r.errors += 1;
    }
  }

  return r;
}

export const reconcileMpSubscriptions = onSchedule(
  {
    // 03:00 ART, y la hora NO es arbitraria: `sweepEntitlements` corre a las
    // 04:00 y decide bloqueos leyendo `subscription`. Reconciliar despues
    // dejaria al barrido trabajando sobre el estado de ayer — un PF que pago
    // anoche seguiria con alumnos bloqueados un dia entero.
    schedule: "0 3 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
    secrets: [MP_ACCESS_TOKEN],
  },
  async () => {
    const r = await reconcileAllSubscriptions(ensureApp(), {
      mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
      nowMs: Date.now(),
    });
    logger.info("reconcileMpSubscriptions: corrida diaria", r);
  },
);
