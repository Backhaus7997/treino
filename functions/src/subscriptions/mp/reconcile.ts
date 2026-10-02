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
 * Por eso hay nueve casos donde esta funcion NO toca el documento:
 *
 *   1. El estado de MP no se entiende (`degraded`).
 *   2. No sabemos de que plan es la suscripcion.
 *   3. El uid del mapeo no coincide con el `external_reference` de MP.
 *   4. Lo que ibamos a escribir es identico a lo que ya esta.
 *   5. Es un `pending` y el PF ya tiene un entitlement pago vigente.
 *   6. El plan fue REEMPLAZADO por otro y lo dimos de baja nosotros.
 *   7. La cuenta del usuario se elimino.
 *   8. El plan ya no es el VIGENTE del PF y lo que trae no le gana a lo que
 *      hay escrito. Ver "EL PLAN VIGENTE" mas abajo.
 *   9. Solo del ALUMNO: el plan ya no le da acceso, pero OTRO plan suyo si. Es
 *      el (8) con otro mecanismo, porque su mapa no anota quien lo escribio: ver
 *      la guarda de los dos planes en `escribirSuscripcionDeAlumno`. Si para
 *      decidirlo hay que preguntarle a MP por el otro plan y MP no contesta, no
 *      se corta NI se escribe nada: sale `error-mp` y este plan, que no queda
 *      `terminal`, lo reintenta el barrido de las 03:00.
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
 *
 * ── EL PLAN VIGENTE, Y POR QUE EL MAPA ANOTA QUIEN LO ESCRIBIO ──
 *
 * La guarda (6) solo cubre la baja que decidimos NOSOTROS. La que hace el PF no
 * deja `supersededBy` —`puedeSeguirCobrando` la saltea, porque no hay nada que
 * cancelar— y eso dejaba un agujero (lo encontro la revision del #1290):
 *
 *   1. El PF da de baja el plan A: `cancelled`, y A queda `terminal`.
 *   2. Vuelve a contratar con el plan B: `active`.
 *   3. Llega TARDE un webhook de A (el dedupe de `mpWebhook` dura 10 minutos).
 *   4. Se reconcilia A. MP contesta `cancelled` sin fecha, la cascada de
 *      `resolverFinDePeriodo` cae en la fecha guardada —que ya es la de B— y se
 *      escribe {tier de A, cancelled, fecha de B} encima del `active` de B.
 *
 * Con el mismo tier, la pantalla dice "Plan dado de baja" y le ofrece VOLVER A
 * CONTRATAR a alguien que esta suscripto. Con otro tier le baja el cupo y le
 * manda el mail de degradacion. El barrido reafirma B esa noche, porque A es
 * terminal y no lo visita — pero el mail ya salio.
 *
 * Por eso `subscription.mpPlanId` dice QUE plan escribio el estado, y un plan
 * que no es ese solo lo pisa si lo que trae le GANA a lo que hay
 * (`puedePisarAlVigente`):
 *
 *   - Primero por estado: lo que cobra (`active`, `grace`) le gana a lo que esta
 *     naciendo (`pending`); eso, a la baja (`cancelled`, `paused`) de un plan que
 *     se pago; y eso, a la baja de un checkout que nunca cobro
 *     (`cobrosExitosos`).
 *   - Con el mismo estado, el plan mas nuevo por `mp_plans.createdAt`: el mismo
 *     criterio con el que `darDeBajaLosReemplazados` elige a quien cancelar, asi
 *     que las dos decisiones no se pueden contradecir.
 *
 * Ordenar SOLO por `createdAt` parece suficiente y no lo es: esa fecha es cuando
 * se ABRIO el checkout, no cuando se pago, y el `init_point` no vence. El PF que
 * abre A, abre B —que llega a escribir un `pending` y despues se cae— y al final
 * paga la pestaña vieja de A, quedaba con A cobrando y sin acreditar NUNCA:
 * ningun evento de A volvia a poder escribir. Con el estado primero, un pago real
 * siempre pasa por encima de un checkout que no se pago. Y la regla es simetrica:
 * el `cancelled` de un plan nuevo que nunca se pago tampoco pisa el `active` de
 * uno mas viejo que sigue cobrando.
 *
 * El ultimo escalon —la baja que cobro contra la que no— lo encontro la revision
 * adversarial de esta guarda. El boton de baja cancela TODAS las suscripciones
 * del PF, tambien la `pending` de un upgrade a medio camino, y sin el escalon el
 * `cancelled` de ese checkout —mas nuevo, sin un peso cobrado— quedaba como
 * vigente encima de la baja del plan que si se pago: el PF pasaba a tener el tier
 * de un plan que nunca cobro, con un fin de periodo que nadie habia pagado. En un
 * arrepentimiento era peor: `cortarElAcceso` solo reconcilia los planes que
 * tenian contrato al empezar el tramite, asi que el corte de A perdia el
 * desempate contra B y no entraba.
 *
 * Ese escalon necesita saber si el VIGENTE cobro, y es un dato que la baja ya
 * escrita no deja ver (`cancelled` es `cancelled`). Por eso el mapa lo guarda al
 * lado del plan, en `subscription.mpPlanCobro`: lo que el plan que escribio el
 * estado habia cobrado en ese momento. El supuesto que ocupaba su lugar —que el
 * vigente siempre cobro— era falso: B, un checkout que nunca cobro, queda como vigente
 * con su `cancelled`; el `cancelled` de A, que SI cobro pero nadie reconcilio a
 * tiempo, empataba contra el y perdia por fecha. Se rechazaba y quedaba terminal:
 * lo que el PF pago con A no se acreditaba nunca. Ahora se escribe. OJO con el
 * alcance: se acredita el TIER de A; su fin de periodo sale de la cascada de
 * `resolverFinDePeriodo`, y MP omite `next_payment_date` en una baja que cobro, asi
 * que cae en la fecha guardada —la de B— y no en la que A pago de verdad.
 *
 * Lo que la guarda NO hace, a proposito:
 *
 *   - Frenar al plan anotado. Su propia baja, su pausa o su cobro rebotado
 *     escriben siempre — si no, nadie perderia nunca el plan.
 *   - Saltearse la marca `terminal`. Que un plan no mande no cambia que MP haya
 *     confirmado su baja.
 *   - Decidir sin datos. Un estado escrito antes de que existiera la clave, o dos
 *     planes que no se pueden ordenar porque a uno le falta la fecha, se escriben
 *     como antes de la guarda. Frenar ahi podria dejar sin acreditar un pago para
 *     siempre, que es el peor de los dos errores.
 *   - Cerrar la carrera entre dos eventos SIMULTANEOS del mismo PF: leer y
 *     escribir `users/{uid}` no es una transaccion. El agujero era un evento
 *     tardio, no uno simultaneo.
 *   - Anotar el plan en el mapa del alumno. Su mapa es `{ status }` y nada mas,
 *     por decision y con un test que lo fija (ver `escribirSuscripcionDeAlumno`),
 *     asi que esta guarda no lo cubre. El mismo agujero —un plan que ya no
 *     otorga pisando a otro que si— lo frena el caso (9), con OTRO mecanismo: en
 *     vez de comparar contra el plan que escribio el mapa, mira lo que dejo
 *     guardado cada plan del alumno en `mp_plans.ultimoStatus` ([otroPlanQueOtorga]).
 *     Los dos caminos no comparten reglas ni helpers; unificarlos es otro cambio.
 *
 * ── LA PRUEBA DIFERIDA ──
 *
 * Un plan que nacio con dias de prueba (`mp_plans.diferidoHastaMs`, ver
 * `diferir-primer-cobro.ts`) se lee con reglas propias mientras su suscripcion
 * no haya tenido ningun cobro EXITOSO (un monto de $0 no cuenta). Una autorizada
 * mucho despues de abrir el checkout se trata como `pending`, y la guarda (5)
 * protege lo que el PF ya tenia pago; una autorizada a tiempo no pasa a `grace`
 * por un cobro que todavia no corresponde; y una prueba cancelada no estira el
 * fin de periodo mas alla de lo que el PF ya pago. Desde el primer cobro real se
 * lee como cualquier otro plan.
 *
 * Esas reglas descansan en supuestos sobre como MP cuenta una prueba que NO estan
 * medidos, y por eso los tres casos que piden que alguien mire loguean un warn: la
 * autorizacion tardia (deja sin plan a quien autorizo un pago), la prueba vencida
 * sin cobro (podria estar dando acceso gratis) y el plan con prueba que ya cobro
 * antes de tiempo (MP ignoro o acorto la prueba: el PF pago dos veces). Las
 * reglas, los supuestos y el por que de cada una estan en ese archivo.
 *
 * Valen igual para el alumno: su checkout tambien difiere el primer cobro cuando
 * vuelve con dias pagos o cuando cambia de plan con el viejo cobrando, y su
 * escritor pasa por la misma lectura (`leerPruebaDiferida`) con su propia guarda de
 * `pending`.
 *
 * ── EL CAMBIO DE PLAN DEL ALUMNO ──
 *
 * El alumno tambien da de baja el plan viejo cuando el nuevo se confirma
 * (`darDeBajaLosReemplazadosDelAlumno`). CUALES, con el mismo criterio que el PF: lo
 * estrictamente mas viejo por `createdAt`. CUANDO, con una diferencia: el PF da de
 * baja cuando el estado del nuevo, YA AJUSTADO por la prueba diferida, es `active` o
 * `grace`; el alumno, cuando MP dice `authorized`, aunque la prueba lo lea `pending`
 * (autorizada fuera de ventana). Ver por que en el llamador. Hasta que existio, la
 * rama del alumno retornaba antes de llegar a la baja del PF y las dos suscripciones
 * quedaban cobrando (la mitigacion del #1305 bloqueaba el checkout para que no
 * pasara).
 *
 * Lo que NO copia, a proposito: `supersededBy` y el `terminal` por reemplazo. El
 * plan viejo del alumno queda como si el alumno se hubiera dado de baja, otorgando
 * hasta el fin de lo que cobro y cortando despues, y lo que evita que ese corte pise
 * al plan nuevo es la guarda de los dos planes. Ver `darDeBajaUnPlanDelAlumno`.
 *
 * Y una cosa que el PF no tiene: si dar de baja el viejo le haria pagar dos veces
 * al alumno (el viejo ya tiene pago mas alla de la prueba del nuevo, por un link
 * pagado tarde o una renovacion que gano la carrera), se da de baja el NUEVO, que
 * todavia no cobro. Ver `elViejoPagaMasAllaDeLaPrueba`.
 *
 * Lo que queda sin cubrir: un viejo PAUSADO que el pagador reanuda desde MP entre el
 * checkout y la confirmacion del nuevo. Si se renueva y su fin pasa la prueba del
 * nuevo, cae en el caso de arriba (se da de baja el nuevo). Pero si el nuevo no
 * difirio (un pausado sin dias cobra al autorizar), su cobro pudo haber salido
 * igual: se da de baja uno de los dos con un ERROR en el log, y el periodo que se
 * solapa ya se cobro dos veces. No se detecta antes porque el plan nuevo no guarda
 * en que estado estaba el viejo al abrir el checkout.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";

import {
  SUBSCRIPTION_STATUSES,
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
  ADELANTO_MAXIMO_DEL_COBRO_MS,
  HOLGURA_PRUEBA_MS,
  PruebaDiferidaInput,
  aplicarPruebaDiferidaAlEstado,
  aplicarPruebaDiferidaAlPeriodo,
  cobroAntesDeLaPrueba,
  cobrosExitosos,
  pagadoHastaDe,
  situacionDeLaPrueba,
} from "./diferir-primer-cobro";
import {
  AthleteStatus,
  athleteStatusDesde,
  athleteStatusOtorga,
  hayCobroPendiente,
  mapMpStatus,
} from "./map-status";
import {
  CAMPO_ARREPENTIDO,
  MOTIVO_ABANDONO,
  MOTIVO_REEMPLAZO,
  arrepentidoAtDe,
  puedeSeguirCobrando,
} from "./motivos-terminal";
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
  /**
   * La cuenta del usuario se elimino (`deleteAccount`). Ver la guarda de cuenta
   * eliminada: escribir acá recrearia un `users/{uid}` vacio.
   */
  | "skipped-cuenta-eliminada"
  /**
   * El plan no es el que escribio el estado del PF (`subscription.mpPlanId`) y
   * lo que trae no le gana a lo que hay. Ver la guarda del plan vigente: el caso
   * tipico es el webhook TARDIO de un plan que el PF dio de baja, llegando
   * despues de que contrato otro.
   */
  | "skipped-plan-no-vigente"
  /**
   * Solo del alumno: el plan ya no le da acceso, pero OTRO plan suyo si. Ver la
   * guarda de los dos planes en `escribirSuscripcionDeAlumno`: escribirlo seria
   * cortarle el acceso a alguien que lo sigue pagando.
   */
  | "skipped-otro-plan-otorga"
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
  /**
   * Solo del alumno: la baja de lo que este plan reemplaza no se pudo hacer (MP no
   * contesto o no confirmo). Se reintenta en la proxima reconciliacion; el barrido
   * lo cuenta en `errors` para que se vea.
   */
  bajaFallida?: boolean;
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
 * `unknown` → ISO 8601 si es un numero de ms que da una fecha valida, si no
 * `null`. Solo para logs: un campo que vino mal de un documento no puede hacer que
 * el reconciliador tire un `RangeError` (que es lo que hace `toISOString` con una
 * fecha invalida) justo cuando intenta avisar que algo esta raro.
 */
function isoDeMs(ms: unknown): string | null {
  if (typeof ms !== "number" || !Number.isFinite(ms)) return null;
  const d = new Date(ms);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
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
      "mp/reconcile: sin fecha de fin de periodo por ningun camino — se pierde " +
        "el acceso pago en el acto",
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
 * El fin de periodo con el tope de la prueba diferida, o [base] sin tocar si el
 * plan no es diferido.
 *
 * La regla vive en `diferir-primer-cobro.ts`; acá solo se traduce entre
 * Timestamp y ms, y se deja registro cuando algo cambia. Devuelve el MISMO
 * objeto cuando no hay cambio, asi que para un plan normal es una identidad.
 */
function conTopeDeLaPruebaDiferida(
  base: Timestamp | null,
  prueba: PruebaDiferidaInput,
  // `producto` solo lo pasa el alumno: ver `LecturaDeLaPruebaDiferida.producto`.
  contexto: { planId: string; uid: string; producto?: "athlete" },
): Timestamp | null {
  const baseMs = base === null ? null : base.toMillis();
  const topeMs = aplicarPruebaDiferidaAlPeriodo({
    ...prueba,
    periodEndMs: baseMs,
  });
  if (topeMs === baseMs) return base;

  logger.info(
    "mp/reconcile: el fin de periodo de una prueba diferida se ajusta a lo " +
      `que ${quienPagoLaPrueba(contexto.producto)} ya pago`,
    {
      ...contexto,
      desdeIso: baseMs === null ? null : new Date(baseMs).toISOString(),
      haciaIso: topeMs === null ? null : new Date(topeMs).toISOString(),
    },
  );
  return topeMs === null ? null : Timestamp.fromMillis(topeMs);
}

/**
 * A quien nombran los logs de la prueba diferida. El del PF es el texto de
 * siempre, y hay tests que fijan sus mensajes enteros.
 */
function quienPagoLaPrueba(producto: "athlete" | undefined): string {
  return producto === "athlete" ? "el alumno" : "el PF";
}

/**
 * La entrada de las reglas de la prueba diferida para un plan y su suscripcion.
 * Pura: la usan [leerPruebaDiferida], que ademas avisa, y [derechoVivoDelHermano],
 * que lee a un hermano y no tiene que logear cosas de un plan que no esta
 * reconciliando.
 */
function pruebaDiferidaDe(
  planDoc: Record<string, unknown> | undefined,
  mp: MpPreapproval,
  statusDeMp: SubscriptionStatus,
  nowMs: number,
): PruebaDiferidaInput {
  return {
    diferidoHastaMs: planDoc?.diferidoHastaMs,
    planCreadoMs: comoTimestamp(planDoc?.createdAt)?.toMillis() ?? null,
    mpStatus: mp.status,
    statusHoy: statusDeMp,
    summarized: mp.summarized,
    mpDateCreated: mp.date_created,
    nowMs,
  };
}

/** Lo que [leerPruebaDiferida] necesita de un plan y de su suscripcion. */
interface LecturaDeLaPruebaDiferida {
  planId: string;
  uid: string;
  planDoc: Record<string, unknown> | undefined;
  mp: MpPreapproval;
  /** El estado al que llego el mapeo de siempre (`mapMpStatus`). */
  statusDeMp: SubscriptionStatus;
  nowMs: number;
  /**
   * Solo lo pasa el alumno, y solo cambia los LOGS: el sujeto de los mensajes
   * que nombran a quien pago y un `producto` en cada payload. Sin el, los logs del
   * PF salen exactamente como antes de que el alumno usara esta funcion.
   */
  producto?: "athlete";
}

/**
 * La prueba diferida de un plan, leida para el reconciliador: el estado ajustado
 * por sus reglas, y los avisos de los tres casos que piden que alguien mire.
 *
 * La usan los DOS escritores, el del PF y el del alumno: las reglas no dependen de
 * quien paga sino de como MP cobra una prueba (ver `diferir-primer-cobro.ts`), y
 * dos copias de estos avisos serian dos cosas que hay que acordarse de mover
 * juntas.
 *
 * Para un plan normal (sin `diferidoHastaMs`) o que ya cobro, el estado es
 * [LecturaDeLaPruebaDiferida.statusDeMp] tal cual y no se loguea nada.
 */
function leerPruebaDiferida(i: LecturaDeLaPruebaDiferida): {
  pruebaDiferida: PruebaDiferidaInput;
  status: SubscriptionStatus;
} {
  const { planId, uid, planDoc, mp, statusDeMp } = i;
  const quien = quienPagoLaPrueba(i.producto);
  // Solo para el alumno: los payloads del PF no cambian.
  const delProducto = i.producto === undefined ? {} : { producto: i.producto };

  const pruebaDiferida = pruebaDiferidaDe(planDoc, mp, statusDeMp, i.nowMs);
  const situacion = situacionDeLaPrueba(pruebaDiferida);
  const status = aplicarPruebaDiferidaAlEstado(pruebaDiferida);
  const contextoDeLaPrueba = {
    planId,
    uid,
    mpStatus: mp.status,
    desde: statusDeMp,
    hacia: status,
    diferidoHastaIso: isoDeMs(planDoc?.diferidoHastaMs),
    ...delProducto,
  };
  if (cobroAntesDeLaPrueba(pruebaDiferida)) {
    // WARN. Un plan con prueba ya cobro cuando todavia faltaba mas de
    // `MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS` (dos dias) para el fin de lo que el
    // usuario tenia pago: MP ignoro o acorto la prueba, y pago dos veces ese periodo.
    // El margen es ancho a proposito: un cobro que cae el mismo dia que E, unas
    // horas antes de su hora exacta, es lo esperado y no tiene que avisar. No
    // cambia el estado (un plan que cobro se lee como cualquiera), pero es el
    // aviso de que el supuesto central del diferimiento no se cumplio: hay que
    // revisar ese pago y evaluar apagar el interruptor
    // (`DIFERIR_PRIMER_COBRO_ENABLED`, en `diferir-primer-cobro.ts`).
    logger.warn(
      `mp/reconcile: un plan con prueba YA cobro antes de que venza lo que ${quien} ` +
        `tenia pago, MP ignoro o acorto la prueba y ${quien} pago dos veces`,
      {
        planId,
        uid,
        mpStatus: mp.status,
        diferidoHastaIso: isoDeMs(planDoc?.diferidoHastaMs),
        cobros: cobrosExitosos(mp.summarized),
        nowIso: isoDeMs(i.nowMs),
        ...delProducto,
      },
    );
  }
  if (situacion === "fuera-de-ventana") {
    // WARN y no info. Esto deja SIN el plan a alguien que autorizo un pago (hasta
    // el primer cobro real de MP) y que probablemente crea que ya lo tiene: tiene
    // que poder verse en el log para atender el reclamo.
    logger.warn(
      "mp/reconcile: prueba diferida autorizada fuera de ventana, se trata " +
        "como pending",
      {
        ...contextoDeLaPrueba,
        autorizadaEn: typeof mp.date_created === "string"
          ? mp.date_created.slice(0, 40)
          : null,
        planCreadoIso: isoDeMs(pruebaDiferida.planCreadoMs),
      },
    );
  } else if (situacion === "vencida" && statusDeMp === "active") {
    // WARN y no info. Pasado el horizonte, sin ningun cobro exitoso y sin un cobro
    // pendiente, el mapeo de siempre deja `active`: acceso pago sin que MP haya
    // cobrado ni intentado cobrar nada. No se corrige aca (no hay evidencia de que
    // sea un error, y bajarlo seria revocar), pero es acceso gratis posible.
    logger.warn(
      "mp/reconcile: prueba diferida vencida sin ningun cobro exitoso ni cobro " +
        "pendiente, posible acceso gratis",
      {
        ...contextoDeLaPrueba,
        // En `vencida`, E es siempre un numero (si no, la situacion seria `no-aplica`).
        horizonteIso: typeof pruebaDiferida.diferidoHastaMs === "number"
          ? isoDeMs(pruebaDiferida.diferidoHastaMs + HOLGURA_PRUEBA_MS)
          : null,
      },
    );
  } else if (status !== statusDeMp) {
    logger.info("mp/reconcile: prueba diferida, el estado se ajusta", contextoDeLaPrueba);
  }

  return { pruebaDiferida, status };
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
 * El campo de `mp_plans` que dice "la cuenta de este usuario se elimino".
 *
 * Lo pone `deleteAccount` (`cascade/subscriptions.ts`) sobre TODOS los planes del
 * usuario, despues de cancelar en MP. Sin el, el `cancelled` que MP avisa por
 * webhook a los pocos segundos —y el barrido de las 03:00, que sigue visitando
 * los planes no terminales— escribirian con `set` y `merge` sobre `users/{uid}` y
 * recrearian un documento vacio de alguien que ya no existe.
 *
 * Es un momento (ms) y no un booleano por coherencia con `CAMPO_ARREPENTIDO`, y
 * sirve para auditar cuando se elimino.
 */
export const CAMPO_CUENTA_ELIMINADA = "cuentaEliminadaAtMs";

// Los dos motivos de `terminal` que escribe este archivo (`MOTIVO_ABANDONO` y
// `MOTIVO_REEMPLAZO`) viven en `motivos-terminal.ts`, junto con la explicacion de
// las tres clases de `terminal`: `diferir-primer-cobro.ts` tambien los lee, y un
// import hacia este archivo seria circular. El tercer `terminal` no tiene motivo:
// es el de `status === cancelled`, y que la baja del PF sea la unica SIN motivo es
// deliberado (ver `puedeSeguirCobrando`).

// `puedeSeguirCobrando` (este plan todavia PUEDE estar cobrando, asi que hay que
// mirarlo) y el campo del arrepentimiento (`CAMPO_ARREPENTIDO`, `arrepentidoAtDe`)
// viven en `motivos-terminal.ts`: los lee tambien `diferir-primer-cobro.ts`, y un
// import hacia este archivo seria circular. Se re-exportan para quienes ya los
// importaban de aca.
export { CAMPO_ARREPENTIDO, arrepentidoAtDe, puedeSeguirCobrando };

/**
 * La clave de `users/{uid}.subscription` que dice QUE plan escribio ese estado.
 * Ver "EL PLAN VIGENTE" en el encabezado.
 *
 * Va adentro del mapa y no como campo hermano en `users/{uid}`: el mapa ya esta
 * pineado entero en `firestore.rules` (null en el create, igual al guardado en el
 * update), asi que la clave no cuesta ni una linea de reglas. El cliente la
 * ignora: `TrainerSubscription` no la declara y `json_serializable` descarta lo
 * que no conoce.
 */
const CAMPO_PLAN_VIGENTE = "mpPlanId";

/**
 * Hermana de [CAMPO_PLAN_VIGENTE], en el mismo mapa y en la misma escritura: si
 * el plan que escribio el estado habia cobrado (`cobrosExitosos > 0`, booleano).
 * La guarda lo lee para el escalon «la baja que cobro contra la que no», que sin
 * este dato tenia que suponer que el vigente siempre cobro (y ese supuesto
 * rechazaba el periodo pago de un plan viejo). Mismo trato que `mpPlanId` en
 * `firestore.rules` (el mapa esta pineado entero) y en el cliente (lo ignora).
 */
const CAMPO_COBRO_DEL_VIGENTE = "mpPlanCobro";

/**
 * Que tan vigente es un estado, para decidir entre dos planes del mismo PF.
 *
 *   3 — `active` / `grace`: las dos caras del `authorized` de MP. Hay medio de
 *       pago cargado y MP le sigue cobrando.
 *   2 — `pending`: un checkout que todavia no se confirmo.
 *   1 — `cancelled` / `paused` de un plan que COBRO: hubo un periodo pago.
 *   0 — `cancelled` / `paused` de un checkout que nunca cobro, o un estado que
 *       no entendemos.
 *
 * Contesta cual de los dos planes es el que el PF esta pagando —o el ultimo que
 * pago—, y nada mas.
 */
function rangoDeVigencia(status: unknown, cobro: boolean): number {
  if (status === "active" || status === "grace") return 3;
  if (status === "pending") return 2;
  if (status === "cancelled" || status === "paused") return cobro ? 1 : 0;
  return 0;
}

/** Un plan del PF, tal como lo compara [puedePisarAlVigente]. */
export interface PlanEnDisputa {
  planId: string;
  /** En el vocabulario del PF. Del vigente, lo que hay escrito hoy. */
  status: unknown;
  /** `mp_plans/{planId}.createdAt` en ms, o `null` si no se pudo leer. */
  altaMs: number | null;
  /**
   * Si la suscripcion tuvo algun cobro exitoso: `cobrosExitosos`, la misma
   * evidencia de pago que usa la prueba diferida. Solo separa dos bajas —la de un
   * plan que se pago y la de un checkout que nunca cobro—; con otro estado no
   * cambia nada. Del vigente, lo que anoto `subscription.mpPlanCobro`.
   */
  cobro: boolean;
}

/**
 * Si el estado que trae [entrante] puede pisar al que escribio [vigente] —el plan
 * anotado en `subscription.mpPlanId`—.
 *
 * Pura y total. El por que de cada regla esta en "EL PLAN VIGENTE", en el
 * encabezado, y los `if` van en el mismo orden.
 */
export function puedePisarAlVigente(
  entrante: PlanEnDisputa,
  vigente: PlanEnDisputa,
): boolean {
  // El plan que escribio el estado lo actualiza siempre: su baja, su pausa, su
  // cobro rebotado. Si no, nadie perderia nunca el plan.
  if (entrante.planId === vigente.planId) return true;

  // Primero el estado. Es lo que deja pasar el pago de una pestaña vieja por
  // encima de un checkout mas nuevo que nunca se pago, y lo que no deja que la
  // baja de ese checkout pise la de un plan que si se pago.
  const rangoEntrante = rangoDeVigencia(entrante.status, entrante.cobro);
  const rangoVigente = rangoDeVigencia(vigente.status, vigente.cobro);
  if (rangoEntrante !== rangoVigente) return rangoEntrante > rangoVigente;

  // Mismo estado: manda el mas nuevo, como en `darDeBajaLosReemplazados`. Sin las
  // dos fechas —o con la misma— no hay orden, y se escribe como antes de la
  // guarda: frenar podria dejar un pago sin acreditar para siempre.
  if (entrante.altaMs === null || vigente.altaMs === null) return true;
  return entrante.altaMs >= vigente.altaMs;
}

/** `mp_plans/{planId}.createdAt` en ms, o `null` si el plan no existe o no la tiene. */
async function altaDelPlanMs(app: App, planId: string): Promise<number | null> {
  const snap = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .doc(planId)
    .get();
  return comoTimestamp(snap.data()?.createdAt)?.toMillis() ?? null;
}

/**
 * Marca `terminal` —sin motivo, que es lo que distingue a la baja (ver
 * `motivos-terminal.ts`)— cuando MP confirmo que el plan esta `cancelled`.
 * Idempotente: si ya estaba, no escribe.
 *
 * La llaman los dos caminos que reconcilian un PF: el que escribe su estado y el
 * del plan que ya no es el vigente. Que un plan no mande no cambia que MP haya
 * confirmado su baja.
 */
async function marcarTerminalSiSeDioDeBaja(
  app: App,
  planId: string,
  status: SubscriptionStatus,
  planDoc: Record<string, unknown> | undefined,
): Promise<void> {
  if (status !== "cancelled" || planDoc?.terminal === true) return;
  await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .doc(planId)
    .set({ terminal: true }, { merge: true });
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

/** El plan del ALUMNO que MP acaba de confirmar, tal como lo ve su baja. */
interface PlanNuevoDelAlumno {
  planId: string;
  /** `mp_plans/{planId}`, tal como salio de Firestore. */
  planDoc: Record<string, unknown> | undefined;
  /** La suscripcion de MP que se acaba de confirmar. */
  mp: MpPreapproval;
}

/** Lo que dejo la baja del alumno. */
interface BajaDelAlumno {
  /** Cuantas suscripciones se dieron de baja en MP (viejas, o la nueva). */
  cancelados: number;
  /** Si algo no se pudo leer o no confirmo: el barrido lo cuenta como error. */
  fallo: boolean;
}

/** `summarized.last_charged_date` de MP en ms, o `null` si no vino o no se entiende. */
function ultimoCobroMs(sub: MpPreapproval): number | null {
  const resumen = sub.summarized as { last_charged_date?: unknown } | null | undefined;
  const raw = resumen?.last_charged_date;
  if (typeof raw !== "string") return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Si dar de baja la suscripcion VIEJA [viejo] le haria pagar dos veces al alumno:
 * el viejo tiene pago MAS ALLA de lo que cubre la prueba del nuevo, asi que dado de
 * baja seguiria otorgando (lo que ya cobro) mientras el nuevo empieza a cobrar.
 *
 * ── El caso que lo pide ──
 *
 * El `init_point` no vence. El alumno abre el anual B dos dias antes de que se
 * renueve el mensual O (prueba de 2 dias, hasta P), no lo paga, y lo paga una semana
 * despues. Para entonces MP ya renovo O en P: esta pago hasta P+30. Si se diera de
 * baja O, otorgaria hasta P+30 (lo que cobro), y la prueba de B, que corre desde que
 * se autoriza, cobraria a los dos dias: el alumno pagaria dos veces casi un mes (casi
 * un año si O es anual). Ahi se da de baja B, que todavia no cobro nada, y O sigue
 * como estaba: es lo unico que no mueve plata. El alumno tiene que volver a hacer el
 * cambio, y el equipo se entera por un ERROR en el log.
 *
 * ── Como se decide ──
 *
 * Una suscripcion vieja que NUNCA cobro ([cobrosExitosos] en 0) no es conflicto: no
 * puede tener pago mas alla de nada. Es tipicamente un checkout del mismo cambio que
 * el alumno dejo a medias (`pending`) antes de pagar el nuevo, y se da de baja como
 * siempre. Sin esta regla, la falta de fechas de una `pending` se leia como conflicto
 * y se daba de baja el plan que el alumno ACABABA de pagar.
 *
 * Para una que cobro: lo que cubre la prueba de B es su `diferidoHastaMs` (E); un B
 * sin prueba cobra al autorizar, y cubre hasta su alta. Hay conflicto si el fin pago
 * de O pasa de E por mas que el adelanto que ya se tolera en el cobro de una prueba
 * (`ADELANTO_MAXIMO_DEL_COBRO_MS`). El fin de O es su `next_payment_date` vivo; es la
 * condicion EXACTA del solapamiento, y por eso es mejor que "O cobro despues de
 * abrir B": si E viene de un plan dado de baja que paga mas lejos que la renovacion
 * de O, dar de baja O no solapa nada (esa renovacion ya estaba de mas y no se
 * recupera dando de baja B).
 *
 * Si MP no mando `next_payment_date`, el fin es el `currentPeriodEnd` guardado, que
 * puede estar viejo (una renovacion que el barrido todavia no vio). Ahi, ademas, es
 * conflicto que O haya cobrado despues de que se abrio B (`last_charged_date`). Sin
 * ninguna fecha de O, decide solo eso; y si tampoco se sabe, es conflicto. Las salidas
 * dudosas terminan en dar de baja B (si no cobro), que no mueve plata: el alumno
 * vuelve a intentar, O no se toca.
 *
 * ── Y la autorizacion fuera de ventana SOLA no es conflicto ──
 *
 * Un B pagado tarde sin que O se haya renovado (su fin sigue en E) se trata como
 * siempre: se da de baja O. Las reglas de la prueba ya lo hacen seguro: O otorga
 * hasta E; B se lee `pending` (no otorga) hasta su primer cobro, que cae en la
 * autorizacion mas los dias de prueba, o sea DESPUES de E; y en el medio el alumno no
 * tiene acceso porque tampoco pago nada. No hay dias gratis ni pagados dos veces, y
 * el cambio se hace igual. Si mientras tanto O se renueva (la baja no llego antes de
 * P), su fin pasa de E y la proxima reconciliacion de B cae en el conflicto de arriba.
 */
function elViejoPagaMasAllaDeLaPrueba(
  viejo: MpPreapproval,
  datosViejo: Record<string, unknown>,
  nuevo: PlanNuevoDelAlumno,
): { conflicto: boolean; finDelViejoMs: number | null; cubreHastaMs: number | null } {
  const altaNuevoMs = comoTimestamp(nuevo.planDoc?.createdAt)?.toMillis() ?? null;
  const e = nuevo.planDoc?.diferidoHastaMs;
  const cubreHastaMs =
    typeof e === "number" && Number.isFinite(e) ? e : altaNuevoMs;

  const deMp = parsePeriodEnd(viejo.next_payment_date, "viejo");
  const finDelViejo = deMp ?? comoTimestamp(datosViejo.currentPeriodEnd);
  const finDelViejoMs = finDelViejo === null ? null : finDelViejo.toMillis();

  // Nunca cobro: no puede tener pago mas alla de la prueba.
  if (cobrosExitosos(viejo.summarized) < 1) {
    return { conflicto: false, finDelViejoMs, cubreHastaMs };
  }

  const ultimo = ultimoCobroMs(viejo);
  const cobroDespuesDeAbrirElNuevo =
    ultimo === null || altaNuevoMs === null || ultimo > altaNuevoMs;

  if (finDelViejoMs !== null && cubreHastaMs !== null) {
    const pasaLaPrueba = finDelViejoMs > cubreHastaMs + ADELANTO_MAXIMO_DEL_COBRO_MS;
    // Con la fecha de MP manda solo ella; con la guardada, que puede estar vieja,
    // tambien cuenta un cobro posterior a la apertura del nuevo (si se sabe).
    const cobroPosterior =
      deMp === null && ultimo !== null && altaNuevoMs !== null && ultimo > altaNuevoMs;
    return { conflicto: pasaLaPrueba || cobroPosterior, finDelViejoMs, cubreHastaMs };
  }
  return { conflicto: cobroDespuesDeAbrirElNuevo, finDelViejoMs, cubreHastaMs };
}

/** Una suscripcion viva de un plan viejo del alumno, ya evaluada. */
interface SuscripcionViejaDelAlumno {
  planId: string;
  datos: Record<string, unknown>;
  sub: MpPreapproval;
  solapa: ReturnType<typeof elViejoPagaMasAllaDeLaPrueba>;
}

/**
 * Hasta cuando esta pago el NUEVO, cuando ya cobro: su `next_payment_date` o, si no
 * vino, lo que cubre su ultimo cobro. `null` si no se sabe.
 */
function finPagoDelNuevoMs(nuevo: PlanNuevoDelAlumno): number | null {
  const deMp = parsePeriodEnd(nuevo.mp.next_payment_date, nuevo.planId);
  return deMp !== null ? deMp.toMillis() : pagadoHastaDe(nuevo.mp);
}

/**
 * Da de baja la suscripcion NUEVA, porque dar de baja la vieja le haria pagar dos
 * veces al alumno (ver [elViejoPagaMasAllaDeLaPrueba]). Total: nunca tira.
 *
 * Deja el acceso como estaba: el viejo sigue cobrando y otorgando. El nuevo dado de
 * baja otorga a lo sumo hasta lo que ya cubre (antes de su primer cobro, las reglas
 * de la prueba cancelada lo acotan a E, que el viejo cubre), y su corte no pisa al
 * viejo por la guarda de los dos planes. No hay vaiven: la proxima reconciliacion
 * del viejo no da de baja nada (el nuevo es mas nuevo que el), y la del nuevo ve
 * `cancelled` y no llega aca. Si el PUT no confirma, la proxima reconciliacion del
 * nuevo vuelve a decidir lo mismo, porque los datos no cambiaron.
 *
 * El ERROR lleva el uid, los dos planes y el motivo: el alumno no se entera desde la
 * app, y alguien tiene que poder explicarselo (o devolver, si ya cobraron los dos).
 */
async function darDeBajaElNuevoDelAlumno(
  uid: string,
  nuevo: PlanNuevoDelAlumno,
  conflictos: SuscripcionViejaDelAlumno[],
  motivo: string,
  deps: ReconcileDeps,
): Promise<BajaDelAlumno> {
  const contexto = {
    uid,
    planNuevo: nuevo.planId,
    planViejo: conflictos[0]?.planId,
    planesViejos: conflictos.map((c) => c.planId),
    motivo,
    finDelViejoIso: isoDeMs(conflictos[0]?.solapa.finDelViejoMs),
    cubreHastaIso: isoDeMs(conflictos[0]?.solapa.cubreHastaMs),
  };
  const preapprovalId = nuevo.mp.id;
  if (typeof preapprovalId !== "string" || preapprovalId === "") {
    logger.error(
      "mp/reconcile: el plan nuevo del alumno solaparia al viejo y su suscripcion " +
        "vino sin id — no se da de baja nada, puede haber un COBRO DOBLE",
      contexto,
    );
    return { cancelados: 0, fallo: true };
  }
  try {
    await deps.mpClient.cancelPreapproval(preapprovalId);
  } catch (e) {
    const err = e as Partial<MpApiError>;
    logger.error(
      "mp/reconcile: el plan nuevo del alumno solaparia al viejo y su baja no " +
        "confirmo — se reintenta, puede haber un COBRO DOBLE",
      { ...contexto, preapprovalId, status: err.status, body: err.body },
    );
    return { cancelados: 0, fallo: true };
  }
  logger.error(
    "mp/reconcile: dar de baja el plan viejo del alumno le cobraria dos veces — se " +
      "da de baja el NUEVO, el viejo sigue; el alumno tiene que volver a hacer el cambio",
    { ...contexto, preapprovalId },
  );
  return { cancelados: 1, fallo: false };
}

/**
 * Da de baja UNA suscripcion vieja del alumno. Total: nunca tira. `true` si MP
 * confirmo.
 *
 * Antes del PUT, si la suscripcion esta `authorized`, se guarda en el plan su
 * `next_payment_date` cuando falta o difiere de lo guardado. Es lo que el escritor
 * guardaria para una suscripcion viva (la cascada de [resolverFinDePeriodo] empieza
 * por ahi), y es la fecha de la que va a depender el acceso del plan viejo: MP omite
 * `next_payment_date` en una baja que cobro, asi que despues de la baja la cascada
 * cae en lo guardado. Sin esto, un plan cuya fecha no estaba al dia (un cobro que el
 * barrido todavia no vio) perderia dias que el alumno pago.
 */
async function darDeBajaUnaSuscripcionVieja(
  app: App,
  uid: string,
  vieja: SuscripcionViejaDelAlumno,
  planVigente: string,
  deps: ReconcileDeps,
): Promise<boolean> {
  const { planId: planViejo, datos, sub } = vieja;
  const preapprovalId = sub.id;
  if (typeof preapprovalId !== "string" || preapprovalId === "") {
    logger.error("mp/reconcile: una suscripcion a dar de baja vino sin id", {
      planViejo,
      planVigente,
      uid,
      producto: "athlete",
    });
    return false;
  }

  if (sub.status === "authorized") {
    const proximo = parsePeriodEnd(sub.next_payment_date, planViejo);
    if (proximo !== null && !mismaFecha(proximo, datos.currentPeriodEnd)) {
      await getFirestore(app)
        .collection(MP_PLANS_COLLECTION)
        .doc(planViejo)
        .set({ currentPeriodEnd: proximo }, { merge: true });
    }
  }

  try {
    await deps.mpClient.cancelPreapproval(preapprovalId);
  } catch (e) {
    const err = e as Partial<MpApiError>;
    // "No confirmo" y no "MP la rechazo": como en el PF, un timeout con la baja ya
    // aplicada no se distingue de un 400. La proxima reconciliacion del plan
    // nuevo le pregunta a MP cual de las dos fue.
    logger.error(
      "mp/reconcile: la baja de la suscripcion vieja del alumno no confirmo — " +
        "puede haber un COBRO DOBLE vivo",
      {
        planViejo,
        planVigente,
        uid,
        preapprovalId,
        status: err.status,
        retryable: err.retryable,
        body: err.body,
      },
    );
    return false;
  }

  logger.info("mp/reconcile: suscripcion vieja del alumno dada de baja en MP", {
    planViejo,
    planVigente,
    uid,
    preapprovalId,
  });
  return true;
}

/**
 * Si vale la pena buscar en MP las suscripciones de un plan viejo del alumno para
 * darlas de baja. Ver "Que planes se miran" en [darDeBajaLosReemplazadosDelAlumno].
 */
function puedeTenerUnaSuscripcion(datos: Record<string, unknown>, nowMs: number): boolean {
  if (datos[CAMPO_ULTIMO_STATUS] !== undefined || datos.currentPeriodEnd != null) {
    return true;
  }
  if (datos.terminalReason !== MOTIVO_ABANDONO) return false;
  const altaMs = comoTimestamp(datos.createdAt)?.toMillis();
  return altaMs !== undefined && nowMs - altaMs < VENTANA_DEL_ABANDONADO_PAGADO_TARDE_MS;
}

/**
 * Da de baja lo que el plan del ALUMNO [nuevo] —recien confirmado por MP—
 * reemplaza: los planes de alumno del mismo uid ESTRICTAMENTE MAS VIEJOS, por
 * `mp_plans.createdAt`, que todavia pueden cobrar. El criterio de CUALES es el de
 * [darDeBajaLosReemplazados], por las mismas razones (ver "EL CAMBIO DE PLAN" en
 * el encabezado): se actua sobre lo que MP confirmo y no sobre la intencion de
 * abrir un checkout, y nunca sobre "los otros", que en el orden del barrido le daria
 * de baja al alumno el plan que acaba de comprar. Sin la fecha del confirmado, o la
 * del viejo, no se da de baja nada. El de CUANDO no es el mismo: ver el llamador.
 *
 * Es la otra mitad del cambio de plan del alumno: el checkout del nuevo difiere su
 * primer cobro hasta que vence lo que el viejo cobro
 * (`decidirCambioDePlanDelAlumno`), y esto hace que el viejo no vuelva a cobrar.
 * Como la prueba corre hasta ese fin, la baja tiene todo el periodo pago del viejo
 * para confirmar: si MP falla, cada reconciliacion del nuevo la reintenta.
 *
 * ── En dos fases: primero se mira todo, despues se decide UNA vez ──
 *
 * Primero se buscan en MP las suscripciones vivas de TODOS los planes viejos y se
 * evalua cada una ([elViejoPagaMasAllaDeLaPrueba]); recien despues se actua. Las
 * bajas no se pueden deshacer, y decidir plan por plan en el orden en que vienen los
 * documentos dejaba resultados que dependian de ese orden: con un checkout a medias
 * y el viejo, dar de baja el viejo y despues el nuevo por culpa del otro dejaba al
 * alumno sin ningun plan que se renueve. Si una busqueda falla, no se da de baja
 * nada: sin ver todo no se puede decidir, y la proxima reconciliacion reintenta.
 *
 * La decision:
 *
 *   - **Ningun conflicto:** se dan de baja todas las viejas vivas, que es el caso
 *     normal.
 *   - **Conflicto y el nuevo todavia no cobro:** se da de baja el NUEVO, que no movio
 *     plata, y no se toca ninguna vieja.
 *   - **Conflicto y el nuevo ya cobro** (los dos cobraron el solapamiento: la plata
 *     ya se movio y hay que devolver, ERROR en cualquier caso): se queda el que mas
 *     lejos tiene pago y se da de baja el otro. Si el viejo cubre mas (un anual
 *     renovado contra un mensual nuevo), dar de baja el viejo dejaria al nuevo
 *     cobrando todos los meses lo que el anual ya cubre; si cubre mas el nuevo, al
 *     reves. Sin la fecha del nuevo, se queda el nuevo (lo que el alumno eligio).
 *
 * ── Que planes se miran ──
 *
 * Los que el reconciliador vio alguna vez con una suscripcion (tienen `ultimoStatus`
 * o `currentPeriodEnd`). Un checkout que nadie pago no tiene nada que dar de baja, y
 * `puedeSeguirCobrando` deja para siempre a los abandonados (se pueden pagar tarde):
 * buscar todos costaba una busqueda en MP por cada uno en cada reconciliacion de un
 * plan activo, todas las noches, para siempre.
 *
 * Las dos excepciones, por quien reconcilia un plan pagado tarde:
 *
 *   - un checkout sin pagar que NO es `terminal` no se busca: lo reconcilia el
 *     barrido de las 03:00 todas las noches, y si se pago, desde ahi tiene
 *     `ultimoStatus` y entra (a mas tardar en la reconciliacion siguiente del nuevo);
 *   - un abandonado (`terminal` por [MOTIVO_ABANDONO]) SI se busca mientras sea
 *     reciente ([VENTANA_DEL_ABANDONADO_PAGADO_TARDE_MS]): el barrido no lo visita
 *     nunca mas, y si su webhook falla antes de escribir `ultimoStatus`, esta baja es
 *     la unica red. Pasada la ventana, un abandonado que nunca tuvo suscripcion ya no
 *     se busca, y si se pagara despues y su webhook fallara, cobraria junto al nuevo:
 *     queda como hueco conocido.
 *
 * Una suscripcion de OTRO uid sobre un plan viejo no se toca: es un dato raro (el
 * plan es de este alumno), se logea como error, y dar de baja el cobro de otra
 * persona no es una decision que se pueda tomar desde aca. Es el mismo criterio que
 * [derechoVivoDelHermano], que no la cuenta como derecho de este alumno.
 *
 * Lo que NO se marca en los viejos, a proposito, ni `supersededBy` ni `terminal`:
 *
 *   - **`supersededBy`** saca al plan de toda escritura (la guarda de reemplazo de
 *     `reconcileSubscription`), porque en el PF su `cancelled` pisaria el tier del
 *     nuevo. El alumno no tiene tiers, y el viejo dado de baja TIENE que seguir
 *     hablando: otorga hasta el fin de lo que cobro (rama `cancelled` de
 *     `athleteStatusDesde`) y deja de otorgar despues. Si lo silenciaramos, nadie
 *     cortaria el acceso en ese fin cuando el nuevo no otorga (una prueba autorizada
 *     fuera de ventana es `pending` hasta su primer cobro: acceso gratis desde el fin
 *     del viejo hasta ese cobro), y [otroPlanQueOtorga] no lo contaria mientras le
 *     quedan dias: si el nuevo dejara de otorgar por su cuenta (se corta solo el
 *     nuevo), el alumno perderia dias que el viejo si cobro. OJO: el tramite de
 *     arrepentimiento (`arrepentimiento-por-mail.ts`) hoy marca arrepentidos a TODOS
 *     los planes con una suscripcion contratada, el viejo dado de baja incluido, asi
 *     que ahi el viejo tambien se corta: eso es de ese tramite, no de esta baja. Lo que
 *     evita que el corte del viejo pise al nuevo es la guarda de los dos planes de
 *     [escribirSuscripcionDeAlumno], igual que con cualquier otro par de planes.
 *   - **`terminal`**: un plan del alumno sale del barrido recien cuando su derecho
 *     se apago (ver la guarda de `terminal` del escritor), y lo saca su propio
 *     escritor. Hasta entonces la reconciliacion del nuevo lo vuelve a mirar en cada
 *     pasada: si la baja no confirmo, se reintenta; si confirmo, MP lo devuelve
 *     `cancelled` y no se manda ningun PUT. Eso es lo que la hace idempotente.
 *
 * O sea: dado de baja por nosotros, el viejo queda EXACTAMENTE como si el alumno se
 * hubiera dado de baja desde la web, que es lo que la mitigacion del #1305 le pedia
 * hacer a mano. No hay una regla de acceso nueva.
 *
 * Total: nunca tira (salvo que falle Firestore, como el resto del escritor).
 */
async function darDeBajaLosReemplazadosDelAlumno(
  app: App,
  uid: string,
  nuevo: PlanNuevoDelAlumno,
  deps: ReconcileDeps,
): Promise<BajaDelAlumno> {
  const planVigente = nuevo.planId;
  const altaVigente = comoTimestamp(nuevo.planDoc?.createdAt);
  if (altaVigente === null) {
    logger.warn(
      "mp/reconcile: el plan confirmado del alumno no tiene createdAt legible — no " +
        "se da de baja nada",
      { planVigente, uid },
    );
    return { cancelados: 0, fallo: false };
  }

  // La misma consulta de un solo campo que el resto del archivo: indice
  // automatico, uno o dos documentos por alumno.
  const otros = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .where("uid", "==", uid)
    .get();

  // ── Fase 1: mirar todo ──
  const vivas: SuscripcionViejaDelAlumno[] = [];
  for (const doc of otros.docs) {
    if (doc.id === planVigente) continue;
    const datos = doc.data();
    if (datos?.producto !== "athlete") continue;
    // NO `terminal === true` a secas: un abandonado puede tener una suscripcion
    // viva (ver `puedeSeguirCobrando`).
    if (!puedeSeguirCobrando(datos)) continue;
    if (!puedeTenerUnaSuscripcion(datos, deps.nowMs)) continue;
    const alta = comoTimestamp(datos?.createdAt);
    if (alta === null || alta.toMillis() >= altaVigente.toMillis()) continue;

    let subs: MpPreapproval[];
    try {
      // Estricta: una respuesta rota no es «no hay nada que dar de baja».
      subs = await deps.mpClient.searchPreapprovalsByPlan(doc.id, { estricto: true });
    } catch (e) {
      const err = e as Partial<MpApiError>;
      logger.error(
        "mp/reconcile: no se pudo buscar que dar de baja del plan reemplazado del " +
          "alumno — no se da de baja nada hasta poder ver todo",
        { planViejo: doc.id, planVigente, uid, status: err.status, retryable: err.retryable },
      );
      return { cancelados: 0, fallo: true };
    }

    for (const sub of subs) {
      if (!sigueViva(sub.status)) continue;
      const externo = sub.external_reference;
      if (typeof externo === "string" && externo !== "" && externo !== uid) {
        logger.error(
          "mp/reconcile: el plan reemplazado del alumno tiene una suscripcion de OTRO " +
            "uid — no se da de baja",
          { planViejo: doc.id, planVigente, uid, externalReference: externo },
        );
        continue;
      }
      vivas.push({
        planId: doc.id,
        datos,
        sub,
        solapa: elViejoPagaMasAllaDeLaPrueba(sub, datos, nuevo),
      });
    }
  }
  if (vivas.length === 0) return { cancelados: 0, fallo: false };

  // ── Fase 2: decidir una vez ──
  const conflictos = vivas.filter((v) => v.solapa.conflicto);
  if (conflictos.length > 0) {
    if (cobrosExitosos(nuevo.mp.summarized) < 1) {
      return darDeBajaElNuevoDelAlumno(uid, nuevo, conflictos, "viejo-pago-mas-alla", deps);
    }
    // Los dos cobraron el solapamiento: se queda el que mas lejos tiene pago.
    const finDelNuevo = finPagoDelNuevoMs(nuevo);
    const finDelViejo = Math.max(
      ...conflictos.map((c) => c.solapa.finDelViejoMs ?? Number.NEGATIVE_INFINITY),
    );
    const contexto = {
      uid,
      planNuevo: planVigente,
      planesViejos: conflictos.map((c) => c.planId),
      finDelNuevoIso: isoDeMs(finDelNuevo),
      finDelViejoIso: isoDeMs(finDelViejo),
    };
    if (finDelNuevo !== null && finDelViejo > finDelNuevo) {
      return darDeBajaElNuevoDelAlumno(
        uid,
        nuevo,
        conflictos,
        "ya-cobraron-los-dos-y-el-viejo-cubre-mas",
        deps,
      );
    }
    logger.error(
      "mp/reconcile: el plan nuevo del alumno ya cobro y el viejo tiene pago mas " +
        "alla de lo que cubria su prueba — el solapamiento ya se cobro dos veces; se " +
        "da de baja el viejo, que cubre menos (revisar y devolver)",
      contexto,
    );
  }

  let cancelados = 0;
  let fallo = false;
  for (const vieja of vivas) {
    if (await darDeBajaUnaSuscripcionVieja(app, uid, vieja, planVigente, deps)) {
      cancelados += 1;
    } else {
      fallo = true;
    }
  }
  return { cancelados, fallo };
}

/**
 * El campo de `mp_plans` con el estado de MP con el que el escritor del ALUMNO
 * decidio la ultima vez que llego a ese plan, en el vocabulario de
 * `effective-limit.ts`. Los caminos de `reconcileSubscription` que salen ANTES
 * del escritor —estado degradado, sin suscripcion, error de MP, mapeo roto,
 * plan reemplazado, cuenta eliminada, uid que no coincide— no
 * lo tocan, y ahi queda el anterior.
 *
 * Existe para una sola pregunta: si OTRO plan del mismo alumno le sigue dando
 * acceso (ver [otroPlanQueOtorga]). Se guarda el estado de MP y no el derecho
 * ya proyectado porque el derecho de un plan dado de baja depende del reloj
 * —`active` hasta `currentPeriodEnd`, `expired` despues— y guardado asi se
 * proyecta al momento de leerlo, con la misma regla que el escritor
 * ([derechoDelPlan]), en vez de quedarse con el `active` de anoche.
 *
 * Vive en el plan y no en `athleteSubscription` por la misma razon que la fecha
 * de fin: ese mapa tiene UNA clave. `mp_plans` es CF-only por regla, asi que no
 * cuesta ni una linea de `firestore.rules`.
 *
 * ── El despliegue: el primer barrido corre con TODOS los planes sin este campo ──
 *
 * Ningun plan lo tiene hasta que el escritor lo visita, y el barrido recorre los
 * planes de un alumno en cualquier orden: el vencido puede tocar antes que el
 * hermano que paga. Leer la ausencia como «no otorga» le corta el acceso a quien
 * lo esta pagando, y el `active` que el hermano restaura despues llega tarde —los
 * dos triggers de `users/{uid}` no tienen orden y cada uno consume el snapshot de
 * SU evento—, con un mail falso de perdida de cobertura o el paywall prendido.
 * Leerla como «otorga» deja acceso para siempre: el plan que vence queda
 * `terminal` y, si el otro era un checkout abandonado, nadie mas lo corta.
 *
 * Entonces la ausencia no se interpreta: se PREGUNTA (ver [otroPlanQueOtorga]),
 * y la respuesta se guarda aca, asi que cada plan se paga una sola vez.
 */
export const CAMPO_ULTIMO_STATUS = "ultimoStatus";

/**
 * El derecho que un plan le da HOY al alumno: la proyeccion de
 * `athleteStatusDesde` con el corte del arrepentimiento encima. Devuelve tambien
 * el momento del arrepentimiento, que el escritor reporta como fin del acceso.
 *
 * Es UNA funcion porque la leen dos: el plan que se esta reconciliando, con lo
 * que MP acaba de contestar, y sus hermanos, con lo que dejaron guardado
 * ([derechoGuardado]). Si un dia las dos lecturas dijeran cosas distintas, la
 * guarda de los dos planes compararia dos reglas en vez de dos planes.
 */
function derechoDelPlan(i: {
  status: SubscriptionStatus;
  periodEndMs: number | null;
  planDoc: Record<string, unknown> | undefined;
  nowMs: number;
}): { derecho: AthleteStatus; arrepentidoAt: number | null } {
  // El arrepentimiento corta el acceso en el acto y lo mantiene cortado: sin
  // esto, el próximo evento de MP volvería a calcular «cancelado, con período
  // hasta el día X» y a devolvérselo. Ver `arrepentidoAtDe`.
  const arrepentidoAt =
    i.status === "cancelled" ? arrepentidoAtDe(i.planDoc) : null;
  return {
    derecho: arrepentidoAt !== null
      ? "expired"
      : athleteStatusDesde(i.status, i.periodEndMs, i.nowMs),
    arrepentidoAt,
  };
}

/**
 * El derecho que el plan [datos] le da HOY al alumno, leido de lo que el
 * reconciliador dejo en su documento, o `null` si no hay con que decidirlo.
 *
 * El `null` NO quiere decir «no otorga»: quiere decir «esto no lo sabe» —un plan
 * que nadie reconcilio desde que existe [CAMPO_ULTIMO_STATUS], que es TODO plan
 * en el primer barrido despues del despliegue—, y quien lo recibe tiene que
 * preguntarle a MP ([derechoVivoDelHermano]). Ni como «no otorga» (corta a quien
 * paga) ni como «otorga» (acceso para siempre) se puede resolver en silencio.
 */
function derechoGuardado(
  datos: Record<string, unknown> | undefined,
  nowMs: number,
): AthleteStatus | null {
  const status = datos?.[CAMPO_ULTIMO_STATUS];
  if (
    typeof status !== "string" ||
    !(SUBSCRIPTION_STATUSES as readonly string[]).includes(status)
  ) {
    return null;
  }
  return derechoDelPlan({
    status: status as SubscriptionStatus,
    periodEndMs: comoTimestamp(datos?.currentPeriodEnd)?.toMillis() ?? null,
    planDoc: datos,
    nowMs,
  }).derecho;
}

/**
 * Cuanto tiempo despues de abrirse un plan hermano una lista VACIA de MP todavia
 * no prueba que no hay suscripcion.
 *
 * El indice de busqueda de MP tarda en reflejar una alta: medido en ~93 s (ver
 * [conLaConocidaPrimero]). 15 minutos es un margen de diez veces ese numero, y
 * el costo esta del lado barato: pasarse de largo solo demora el corte de un
 * plan vencido hasta el proximo barrido o webhook, mientras que quedarse corto
 * lo corta por error —un `expired` seguido, segundos despues, del `active` que
 * restaura el webhook del hermano, con los dos triggers de `users/{uid}` sin
 * orden—. El caso real es `reconcile-my-checkout`: el mensual vencido y el
 * alumno todavia `active` hasta las 03:00 compra el anual, y el callable
 * reconcilia los dos planes sin la suscripcion a mano.
 */
const VENTANA_INDICE_MP_MS = 15 * 60 * 1000;

/**
 * El derecho que el plan hermano [hermanoId] le da HOY al alumno, leido de MP en
 * vivo. Solo para el hermano que no tiene [CAMPO_ULTIMO_STATUS] (ver
 * [otroPlanQueOtorga]). **Tira** si no puede decidirlo.
 *
 * Aplica las MISMAS reglas que el escritor: `mapMpStatus`, la prueba diferida
 * (`aplicarPruebaDiferidaAlEstado` y `aplicarPruebaDiferidaAlPeriodo`, ver
 * [pruebaDiferidaDe]), la cascada de `resolverFinDePeriodo` y [derechoDelPlan]. En
 * particular, MP omite
 * `next_payment_date` en una baja que cobro, asi que un hermano `cancelled` con
 * dias pagos sale de la fecha que dejo guardada en su plan o, sin ella, de
 * `start_date + frequency`. **Si ninguna fecha se puede establecer, NO otorga**:
 * es el mismo piso de `athleteStatusDesde`, y falla hacia cortar el hermano —que
 * es lo que hace el escritor con ese plan cuando es el unico—.
 *
 * ── Varias suscripciones sobre el mismo plan ──
 *
 * No deberia pasar, pero el escritor se queda con la primera y avisa. Aca el
 * hermano solo sirve para NO cortar, asi que otorga si CUALQUIERA de sus
 * suscripciones otorga: una baja vieja no puede tapar a la que cobra, en el orden
 * que MP las devuelva. Lo que se guarda en el plan es el estado de la que otorga
 * y, si ninguna lo hace, el de la que elegiria el escritor (la primera): asi el
 * `ultimoStatus` no contradice lo que el escritor dejaria al reconciliar ese plan.
 * Las de otro uid no cuentan (ver abajo), y un estado ininteligible solo tira si
 * ninguna otra otorga.
 *
 * ── Que no otorga, que tira ──
 *
 * No otorgan, sin tirar: una lista vacia de un plan que ya tiene mas de
 * [VENTANA_INDICE_MP_MS] (un checkout que nunca se pago; no hay estado que
 * guardar, y la pregunta se repite si el cruce vuelve a darse) y las
 * suscripciones de otro uid (un dato raro: se logea como error y no se las
 * regalamos a este alumno). Un plan sin `createdAt` legible tampoco recibe el
 * beneficio de la duda: la lista vacia cuenta como «no hay nada».
 *
 * Tiran, para que quien llama no escriba nada: que MP no conteste; que la
 * respuesta venga rota (`estricto`: una lista vacia de una respuesta sin
 * `results` no puede afirmar que no hay nada cobrando); un estado ininteligible
 * —cortar por algo que no entendimos es lo que la politica de
 * `subscription-state.ts` prohibe—; y una lista vacia de un plan RECIEN abierto,
 * que puede ser el retraso del indice.
 *
 * Guarda lo que aprendio en el plan hermano, igual que lo haria el escritor
 * (el estado y la fecha), para que el barrido y el proximo cruce no vuelvan a
 * preguntar.
 */
async function derechoVivoDelHermano(
  app: App,
  uid: string,
  hermanoId: string,
  datos: Record<string, unknown>,
  deps: ReconcileDeps,
): Promise<AthleteStatus> {
  const subs = await deps.mpClient.searchPreapprovalsByPlan(hermanoId, {
    estricto: true,
  });

  if (subs.length === 0) {
    const creadoMs = comoTimestamp(datos.createdAt)?.toMillis() ?? null;
    if (creadoMs !== null && deps.nowMs - creadoMs < VENTANA_INDICE_MP_MS) {
      throw new Error(
        `mp/reconcile: el plan hermano ${hermanoId} es reciente y MP no lo ` +
          "devuelve todavia — puede ser el retraso del indice, no se decide",
      );
    }
    return "expired";
  }

  const evaluadas: {
    status: SubscriptionStatus;
    derecho: AthleteStatus;
    periodEnd: Timestamp | null;
  }[] = [];
  let ininteligibles = 0;
  for (const mp of subs) {
    const externo = mp.external_reference;
    if (typeof externo === "string" && externo !== "" && externo !== uid) {
      logger.error("mp/reconcile: el plan hermano trae otro uid — no cuenta", {
        hermanoId,
        uid,
        externalReference: externo,
      });
      continue;
    }

    const { status: statusDeMp, degraded } = mapMpStatus({
      raw: mp.status,
      cobroPendiente: hayCobroPendiente(mp.summarized),
      trainerId: uid,
    });
    if (degraded) {
      ininteligibles += 1;
      continue;
    }

    // La prueba diferida del hermano, con las mismas reglas del escritor (ver el
    // orden en el encabezado de [escribirSuscripcionDeAlumno]): un hermano que
    // nacio con prueba otorga por lo que le da HOY al alumno y no por el estado
    // crudo de MP. Sin esto, una prueba autorizada fuera de ventana (que el
    // escritor lee `pending` y no otorga) contaria aca como derecho, y le
    // sostendria al alumno un acceso que ese plan no da. No logea: el que se
    // reconcilia es otro plan, y sus avisos los da cuando le toque a el.
    const pruebaDiferida = pruebaDiferidaDe(datos, mp, statusDeMp, deps.nowMs);
    const status = aplicarPruebaDiferidaAlEstado(pruebaDiferida);

    const finDeMp = resolverFinDePeriodo({
      deMp: parsePeriodEnd(mp.next_payment_date, hermanoId),
      yaGuardada: datos.currentPeriodEnd,
      autoRecurring: mp.auto_recurring,
      status,
      planId: hermanoId,
    });
    // El tope de la prueba (sin arrepentimiento, igual que el escritor; el corte
    // lo aplica [derechoDelPlan]): una prueba cancelada antes de su primer cobro
    // conserva el acceso hasta E y no hasta un mes que nunca se cobro.
    const finDeMpMs = finDeMp === null ? null : finDeMp.toMillis();
    const topeMs =
      status === "cancelled" && arrepentidoAtDe(datos) !== null
        ? finDeMpMs
        : aplicarPruebaDiferidaAlPeriodo({
          ...pruebaDiferida,
          periodEndMs: finDeMpMs,
        });
    const periodEnd = topeMs === null ? null : Timestamp.fromMillis(topeMs);
    const { derecho } = derechoDelPlan({
      status,
      periodEndMs: periodEnd === null ? null : periodEnd.toMillis(),
      planDoc: datos,
      nowMs: deps.nowMs,
    });
    evaluadas.push({ status, derecho, periodEnd });
  }

  const quienOtorga = evaluadas.find((e) => athleteStatusOtorga(e.derecho));
  // Si ninguna otorga y alguna no se entendio, no se puede afirmar que no hay
  // acceso: esa podia ser la que cobra.
  if (quienOtorga === undefined && ininteligibles > 0) {
    throw new Error(
      `mp/reconcile: estado de MP ininteligible en el plan hermano ${hermanoId}`,
    );
  }
  // Sin ninguna que otorgue, la que elegiria el escritor: la primera.
  const elegida = quienOtorga ?? evaluadas[0];
  if (elegida === undefined) return "expired";

  await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .doc(hermanoId)
    .set(
      {
        [CAMPO_ULTIMO_STATUS]: elegida.status,
        ...(elegida.periodEnd !== null &&
        !mismaFecha(elegida.periodEnd, datos.currentPeriodEnd)
          ? { currentPeriodEnd: elegida.periodEnd }
          : {}),
      },
      { merge: true },
    );
  return elegida.derecho;
}

/**
 * El id de OTRO plan de [uid] —no [planId]— que todavia le da acceso al alumno,
 * o `null` si no hay ninguno. **Tira** si hace falta preguntarle a MP y no
 * contesta: ver [derechoVivoDelHermano].
 *
 * Primero lee lo que cada plan dejo guardado ([derechoGuardado]), y solo le
 * pregunta a MP por los hermanos que NO tienen nada guardado. Dos pasadas a
 * proposito: un hermano con estado guardado que otorga corta la busqueda antes de
 * gastar una llamada —y un posible error— en otro.
 *
 * Preguntar solo en ese caso, y no siempre, porque lo guardado es la lectura
 * barata y casi siempre alcanza: preguntar por cada hermano en cada cruce costaria
 * una llamada por plan en caminos que alguien esta mirando
 * (`reconcile-my-checkout`, `cancel-my-subscription`), y el indice de busqueda de
 * MP tarda ~90 s en reflejar un cambio (ver `conLaConocidaPrimero`), asi que
 * tampoco da un dato mejor justo cuando los flujos que cambian varios planes los
 * reconcilian de a uno. Pero la AUSENCIA no se puede leer sin preguntar: es el
 * estado de todos los planes en el primer barrido despues del despliegue, y ver
 * ahi «no otorga» le corta el acceso a quien paga, mientras que ver «otorga» deja
 * acceso para siempre al que era un checkout abandonado. Ver
 * [CAMPO_ULTIMO_STATUS]. Como cada respuesta se guarda, cada plan se paga una vez.
 *
 * Lo guardado puede estar atrasado, y la guarda lo tolera porque solo lo usa para
 * NO revocar: nunca da acceso con eso. El costo de un atraso es acceso de mas
 * hasta que ese plan vuelva a pasar por el escritor, y a uno que no es `terminal`
 * el barrido lo visita esa misma noche. Dos casos se quedan sin ese reaseguro: el
 * checkout abandonado que se pago tarde —es `terminal` por abandono, aca cuenta y
 * el barrido no lo visita; lo refrescan su webhook o `reconcile-my-checkout`— y
 * el plan que el barrido visita pero sale antes del escritor (ver
 * [CAMPO_ULTIMO_STATUS]). En los dos lo guardado queda como estaba, que es el
 * mismo limite que ya tiene ese plan cuando es el unico del alumno: su propio
 * corte tampoco se escribiria.
 *
 * Limite de la pregunta: un hermano recien pagado puede no estar todavia en el
 * indice de MP (~90 s). Solo importa si ademas vence otro plan en esa ventana y el
 * hermano nunca fue reconciliado; su propio webhook lo restaura.
 *
 * Se saltean los planes que ya no pueden otorgar nada, digan lo que digan: los
 * terminales que no son un abandono (ver `puedeSeguirCobrando`), los reemplazados,
 * los de una cuenta eliminada y los ARREPENTIDOS. La marca del arrepentimiento se
 * escribe recien despues de que MP confirmo la baja de cada suscripcion viva que
 * encontro del alumno (paso 3c de `arrepentimiento-por-mail`) y devuelve lo
 * pagado, asi que ese plan no sostiene acceso aunque lo guardado sea el `active`
 * de antes de la baja. Sin esto, si la reconciliacion del segundo plan fallaba a mitad del
 * flujo, el primero no cortaba, y el alumno conservaba hasta el reintento o el
 * barrido el acceso que acababa de devolver.
 */
async function otroPlanQueOtorga(
  app: App,
  uid: string,
  planId: string,
  deps: ReconcileDeps,
): Promise<string | null> {
  // La misma consulta de un solo campo que `darDeBajaLosReemplazados`: indice
  // automatico, sin compuesto que desplegar, y uno o dos documentos por alumno.
  const planes = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .where("uid", "==", uid)
    .get();

  const sinEstado: { id: string; datos: Record<string, unknown> }[] = [];
  for (const doc of planes.docs) {
    if (doc.id === planId) continue;
    const datos = doc.data();
    if (datos?.producto !== "athlete") continue;
    if (!puedeSeguirCobrando(datos)) continue;
    const reemplazadoPor = datos?.[CAMPO_REEMPLAZO];
    if (typeof reemplazadoPor === "string" && reemplazadoPor !== "") continue;
    if (typeof datos?.[CAMPO_CUENTA_ELIMINADA] === "number") continue;
    if (arrepentidoAtDe(datos) !== null) continue;

    const derecho = derechoGuardado(datos, deps.nowMs);
    if (derecho === null) {
      sinEstado.push({ id: doc.id, datos });
    } else if (athleteStatusOtorga(derecho)) {
      return doc.id;
    }
  }

  // De a uno y cortando en el primero que otorga: uno o dos planes por alumno, y
  // cada llamada de mas es una oportunidad de error que frena el corte.
  for (const { id, datos } of sinEstado) {
    const derecho = await derechoVivoDelHermano(app, uid, id, datos, deps);
    if (athleteStatusOtorga(derecho)) return id;
  }
  return null;
}

/**
 * Reconcilia UNA suscripcion contra MP.
 *
 * Total: nunca tira. Cualquier fallo se reporta en el `outcome` — un barrido
 * que se cae por un PF deja a todos los demas sin reconciliar.
 */
/**
 * Escribe el derecho del ALUMNO. El espejo de lo que el resto de
 * `reconcileSubscription` hace para el PF, con cuatro diferencias que importan.
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
 *
 * ── 4. Un plan que ya no otorga no le revoca al alumno lo que otorga OTRO ──
 *
 * El PF tiene un plan que manda: cuando el nuevo se confirma, el viejo se da de
 * baja y queda `supersededBy`, porque sus planes tienen tiers distintos y alguno
 * tiene que decidir el cupo. El alumno no tiene tiers, asi que la pregunta es
 * otra: si ALGUN plan suyo le sigue dando acceso. Es el criterio que ya usa
 * `estadoDesdeResultados` para la vuelta del checkout: el mejor de los planes,
 * no el ultimo.
 *
 * Hacia falta porque el barrido recorre todos los planes no terminales y el
 * ultimo en escribir ganaba. El alumno que da de baja el mensual con dias pagos
 * y contrata el anual perdia el acceso la noche que vencia el mensual, con el
 * anual cobrando. Ver la guarda de los dos planes, y [otroPlanQueOtorga] para
 * cuando lee lo guardado y cuando le pregunta a MP.
 *
 * Es tambien lo que sostiene el cambio de plan con el viejo cobrando: cuando el
 * nuevo se confirma, `reconcileSubscription` da de baja el viejo
 * (`darDeBajaLosReemplazadosDelAlumno`) SIN `supersededBy`, asi que el viejo sigue
 * pasando por este escritor, y el dia que vencen sus dias pagos es esta guarda la
 * que impide que su corte pise al plan nuevo.
 *
 * ── Lo que SI es igual al PF: la prueba diferida ──
 *
 * Pasa por la misma lectura que el PF (`leerPruebaDiferida`), y por eso un plan
 * que nacio con prueba no le da `grace` al alumno durante la prueba ni le estira
 * el acceso mas alla de lo que pago.
 *
 * ── El orden de las dos cosas, y por que importa ──
 *
 * Primero la prueba diferida, despues la guarda de los dos planes. El `status`
 * con el que decide TODO lo demas (el derecho, la fecha, lo que se guarda en
 * `ultimoStatus` y lo que lee [otroPlanQueOtorga]) es el ya ajustado por la
 * prueba, no el crudo de MP. Asi un plan en prueba cuenta para sus hermanos
 * exactamente por lo que le da al alumno HOY: una prueba autorizada a tiempo es
 * `active` y otorga —el alumno tiene acceso durante la prueba, que es lo que
 * pago con el plan anterior—; una autorizada fuera de ventana es `pending` y no
 * otorga; una cancelada antes de su primer cobro conserva el acceso hasta E y no
 * hasta un mes que nunca se cobro. Si el hermano se leyera con el estado crudo,
 * el plan de un alumno que vuelve con dias pagos (el caso para el que existe el
 * diferimiento) podria contar como derecho una autorizacion que el reconciliador
 * ya trata como `pending`.
 */
async function escribirSuscripcionDeAlumno(i: {
  app: App;
  planId: string;
  uid: string;
  mp: MpPreapproval;
  /** El estado al que llego el mapeo de siempre, ANTES de la prueba diferida. */
  statusDeMp: SubscriptionStatus;
  planDoc: Record<string, unknown> | undefined;
  deps: ReconcileDeps;
}): Promise<ReconcileResult> {
  const { app, planId, uid, mp, planDoc, deps } = i;

  // ── LA PRUEBA DIFERIDA, con las mismas reglas que el PF ──
  //
  // Un plan que nacio con dias de prueba (el alumno volvio a suscribirse con dias
  // pagos, ver `decidirDiferimientoDeAlumno`) se lee con las reglas de
  // `diferir-primer-cobro.ts`. Desde aca `status` es el ajustado: una autorizacion
  // fuera de ventana sale `pending`, y la guarda de no-regresion de abajo le
  // conserva al alumno lo que ya tenia pago; una prueba a tiempo no pasa a `grace`
  // por un cobro que todavia no corresponde. Para un plan normal es `statusDeMp`.
  const { pruebaDiferida, status } = leerPruebaDiferida({
    planId,
    uid,
    planDoc,
    mp,
    statusDeMp: i.statusDeMp,
    nowMs: deps.nowMs,
    producto: "athlete",
  });

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
  const finDePeriodo = resolverFinDePeriodo({
    deMp: parsePeriodEnd(mp.next_payment_date, planId),
    yaGuardada: planDoc?.currentPeriodEnd,
    autoRecurring: mp.auto_recurring,
    status,
    planId,
  });

  // El corte del arrepentimiento: el instante gana sobre cualquier fin de periodo.
  // Solo con `cancelled`, como en [derechoDelPlan], que lo vuelve a leer con la
  // misma regla para el derecho.
  const arrepentidoAt = status === "cancelled" ? arrepentidoAtDe(planDoc) : null;

  // La fecha de fin de periodo ya esta calculada con el `status` ajustado por la
  // prueba. El tope de la prueba diferida va aparte, y como en el PF solo sin
  // arrepentimiento: el instante del arrepentimiento gana sobre cualquier fin de
  // periodo. Una prueba cancelada conserva el acceso hasta E, que es lo que el
  // alumno pago con el plan anterior, y no hasta un mes que nunca se cobro. Para
  // un plan normal no cambia nada.
  const periodEnd =
    arrepentidoAt !== null
      ? finDePeriodo
      : conTopeDeLaPruebaDiferida(finDePeriodo, pruebaDiferida, {
        planId,
        uid,
        producto: "athlete",
      });

  // Con el corte del arrepentimiento adentro: ver [derechoDelPlan]. Es la misma
  // regla que dio `arrepentidoAt` arriba; aca interesa el derecho resultante.
  const { derecho: athleteStatus } = derechoDelPlan({
    status,
    periodEndMs: periodEnd === null ? null : periodEnd.toMillis(),
    planDoc,
    nowMs: deps.nowMs,
  });

  // ── Lo que MP acaba de decir de ESTE plan queda en su documento ──
  //
  // Antes de las guardas de este escritor y en todos sus caminos, tambien en los
  // que no tocan al alumno: es lo que leen sus hermanos para saber si este plan
  // otorga (ver [otroPlanQueOtorga]), y un plan que una guarda frena sigue
  // teniendo un estado. Lo que sale de `reconcileSubscription` antes de llegar
  // aca no lo toca (ver [CAMPO_ULTIMO_STATUS]). Sin cambios no escribe: casi
  // todas las noches es el mismo.
  //
  // Se guarda el `status` AJUSTADO por la prueba diferida, no el de MP crudo: el
  // hermano proyecta el derecho desde lo guardado ([derechoGuardado]), y tiene
  // que ver lo mismo que este escritor dejaria. Ver el orden en el encabezado.
  if (planDoc?.[CAMPO_ULTIMO_STATUS] !== status) {
    await planRef.set({ [CAMPO_ULTIMO_STATUS]: status }, { merge: true });
  }

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

  // ── GUARDA DE LOS DOS PLANES: lo que no otorga no revoca lo que otorga otro ──
  //
  // Solo frena un CORTE: este plan ya no da acceso, lo escrito si, y otro plan
  // del alumno lo sigue dando. Nunca da acceso: un plan que otorga escribe como
  // siempre, y un corte sin otro plan que otorgue, tambien. La consulta se paga
  // solo en ese cruce, no en cada evento.
  //
  // Lo que es de ESTE plan se guarda igual —su fecha y su `terminal`, mas
  // abajo—, porque eso no depende de nadie: un mensual vencido no vuelve a
  // otorgar. Cuando el otro plan deje de otorgar, el corte lo escribe él al
  // reconciliarse, con los limites que cuenta [otroPlanQueOtorga].
  const revocaria =
    !athleteStatusOtorga(athleteStatus) &&
    statusPrevio !== undefined &&
    athleteStatusOtorga(statusPrevio as AthleteStatus);
  //
  // Si hay que preguntarle a MP por el otro plan y no contesta, este reconcile no
  // escribe NADA mas: ni el corte, ni la fecha, ni `terminal`. Un corte sin saber
  // si otro plan paga es el mismo corte equivocado que la guarda existe para
  // evitar, y `terminal` sacaria a este plan del barrido que lo reintenta. Sale
  // `error-mp`, y cada llamador lo trata a su manera: el barrido lo cuenta y
  // reintenta esta noche; `reconcile-my-checkout` lo muestra como no disponible;
  // `arrepentimiento-por-mail` tira para que se reintente el tramite; y el webhook
  // NO lo trata como fallo —marca el evento visto por 10 minutos, logea y contesta
  // 200, asi que MP no reintenta—: ahi la recuperacion es el barrido de las 03:00,
  // y este plan sigue en el. Solo queda escrito el `ultimoStatus` de arriba, que es
  // un hecho de este plan.
  let otorgaOtro: string | null = null;
  if (revocaria) {
    try {
      otorgaOtro = await otroPlanQueOtorga(app, uid, planId, deps);
    } catch (e) {
      logger.error(
        "mp/reconcile: no se pudo saber si otro plan del alumno otorga — no se corta",
        {
          planId,
          uid,
          producto: "athlete",
          mpStatus: (e as Partial<MpApiError>).status,
          retryable: (e as Partial<MpApiError>).retryable,
          mensaje: e instanceof Error ? e.message : String(e),
        },
      );
      return { planId, outcome: "error-mp", uid, producto: "athlete", status };
    }
  }
  if (otorgaOtro !== null) {
    logger.info(
      "mp/reconcile: el plan ya no otorga, pero otro plan del alumno si — no se corta",
      { planId, uid, producto: "athlete", status, athleteStatus, otorgaOtro },
    );
  }

  const sinCambios = statusPrevio === athleteStatus;

  if (otorgaOtro === null && !sinCambios) {
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

  if (otorgaOtro !== null) {
    // Sin `athleteStatus` ni `accesoHastaMs`: no se escribio nada, y el fin del
    // acceso de ESTE plan no es el del alumno. `cancel-my-subscription` toma la
    // primera fecha que encuentra para decirle «conservás el acceso hasta…».
    return {
      planId,
      outcome: "skipped-otro-plan-otorga",
      uid,
      producto: "athlete",
      status,
    };
  }

  return {
    planId,
    outcome: sinCambios ? "unchanged" : "written",
    uid,
    producto: "athlete",
    status,
    athleteStatus,
    ...(arrepentidoAt !== null
      ? { accesoHastaMs: arrepentidoAt }
      : periodEnd === null ? {} : { accesoHastaMs: periodEnd.toMillis() }),
  };
}

/**
 * La suscripcion leida POR ID, puesta adelante de lo que devolvio la busqueda.
 *
 * ── ⚠️ El indice de busqueda de MP llega tarde ──
 *
 * `searchPreapprovalsByPlan` sale de un indice que MP actualiza con demora.
 * Medido el 2026-09-24 contra el sandbox: una suscripcion recien creada NO
 * aparecia a los 979 ms y SI a los ~93 s. `getPreapproval`, en cambio, lee por
 * id y la devuelve al instante.
 *
 * El webhook llega ~1 s despues del pago, o sea adentro de esa ventana. Sin
 * esto, la busqueda volvia vacia, el alta salia como `sin-suscripcion`, el
 * webhook la marcaba procesada y contestaba 200 —MP no reintenta— y el dedupe
 * se comia los avisos siguientes. **El webhook no acreditaba ninguna alta**:
 * quien pagaba y cerraba la pestaña esperaba al barrido de las 03:00.
 *
 * Si la busqueda SI la trae, igual gana la leida por id: es la mas fresca de
 * las dos, y es la que MP acaba de confirmar.
 */
export function conLaConocidaPrimero(
  subs: MpPreapproval[],
  conocida: MpPreapproval | undefined,
  planId: string,
): MpPreapproval[] {
  if (!conocida) return subs;
  // La de otro plan no se mezcla: escribiria el estado de una suscripcion
  // ajena sobre el mapeo de este plan.
  if (conocida.preapproval_plan_id !== planId) return subs;
  const id = conocida.id;
  if (typeof id !== "string" || id === "") return subs;
  return [conocida, ...subs.filter((s) => s.id !== id)];
}

/**
 * @param conocida - La suscripcion de ESTE plan, ya leida por id. La pasa el
 *   webhook, que la tiene en la mano. Ver [conLaConocidaPrimero]: sin ella, un
 *   alta recien pagada puede no aparecer todavia en la busqueda.
 */
export async function reconcileSubscription(
  app: App,
  planId: string,
  deps: ReconcileDeps,
  conocida?: MpPreapproval,
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

  // ── GUARDA DE CUENTA ELIMINADA: no hay a quien escribirle ──
  //
  // Antes de salir a la red, por lo mismo que la de reemplazo: ahorra la llamada
  // a MP, y vale tambien para el webhook, que llega con la suscripcion en
  // `conocida` y por eso nunca pasaria por la consulta.
  if (typeof planDoc?.[CAMPO_CUENTA_ELIMINADA] === "number") {
    logger.info("mp/reconcile: la cuenta se elimino — no se escribe", { planId });
    return { planId, outcome: "skipped-cuenta-eliminada" };
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
  subs = conLaConocidaPrimero(subs, conocida, planId);

  // Cero suscripciones es el estado NORMAL de un plan recien creado: el PF
  // abrio el checkout y todavia no pago, o lo abandono. No es un error y no se
  // logea — con un plan por checkout, la mayoria de los planes viejos van a
  // estar asi para siempre.
  //
  // Vale para el BARRIDO. Para el webhook no: MP le acaba de avisar que la
  // suscripcion existe, y por eso la pasa en `conocida`.
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

  // `statusDeMp` y no `status`: los dos escritores lo ajustan despues por la
  // prueba diferida, cada uno en su rama (`leerPruebaDiferida`).
  const { status: statusDeMp, degraded } = mapMpStatus({
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
    const resultado = await escribirSuscripcionDeAlumno({
      app,
      planId,
      uid,
      mp,
      statusDeMp,
      planDoc,
      deps,
    });

    // ── LA BAJA DE LO QUE ESTE PLAN REEMPLAZA, del lado del alumno ──
    //
    // Con el `authorized` de MP (`active` o `grace` en el mapeo de siempre), y no
    // con el estado ya ajustado por la prueba diferida. Una prueba autorizada fuera
    // de ventana se lee `pending` para el ACCESO (no da nada hasta su primer cobro),
    // pero para MP es una suscripcion confirmada, con medio de pago, que va a
    // cobrar: si el viejo siguiera vivo cobrarian los dos. Darlo de baja ahi no le
    // regala nada al alumno: el viejo otorga hasta el fin de lo que cobro y despues
    // lo corta su propia reconciliacion, porque el nuevo en `pending` no otorga.
    //
    // Es la diferencia con el PF, que da de baja con el estado ya ajustado (alli una
    // prueba fuera de ventana no da de baja nada y los dos planes quedan cobrando).
    //
    // Despues del escritor y con cualquier resultado, por lo mismo que en el PF: si
    // una noche MP rechaza la baja, la corrida siguiente encuentra al nuevo sin
    // cambios, y colgada del `written` el cobro doble quedaria vivo para siempre.
    const baja =
      statusDeMp === "active" || statusDeMp === "grace"
        ? await darDeBajaLosReemplazadosDelAlumno(app, uid, { planId, planDoc, mp }, deps)
        : { cancelados: 0, fallo: false };
    return {
      ...resultado,
      dadosDeBaja: baja.cancelados,
      ...(baja.fallo ? { bajaFallida: true } : {}),
    };
  }

  // ── LA PRUEBA DIFERIDA: un plan que nacio con dias de prueba se lee distinto ──
  //
  // Va ANTES de la guarda de no-regresion de abajo porque una suscripcion
  // autorizada fuera de ventana sale de acá como `pending`, y es esa guarda la
  // que le conserva al PF lo que ya tenia pago.
  //
  // Para un plan normal (sin `diferidoHastaMs`) o que ya cobro, esto devuelve el
  // mismo `statusDeMp`. Las reglas y su por que: `diferir-primer-cobro.ts`. El
  // alumno pasa por la misma funcion, adentro de `escribirSuscripcionDeAlumno`.
  const { pruebaDiferida, status } = leerPruebaDiferida({
    planId,
    uid,
    planDoc,
    mp,
    statusDeMp,
    nowMs: deps.nowMs,
  });

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

  // ── GUARDA DEL PLAN VIGENTE: un plan que ya no manda no pisa el estado ──
  //
  // Ver "EL PLAN VIGENTE" en el encabezado: el caso es el webhook TARDIO de un
  // plan que el PF dio de baja, llegando despues de que contrato otro.
  //
  // Va DESPUES de la de `pending`, que ya explicaba sus casos (el upgrade en
  // curso sigue saliendo como `skipped-pending-no-pisa`), y ANTES de todo lo que
  // viene: la fecha, el piso y la baja de los reemplazados le tocan al plan que
  // manda, no a este.
  //
  // El `createdAt` del vigente cuesta una lectura, y solo se paga cuando el
  // estado lo escribio OTRO plan: fuera de un cambio de plan, casi nunca.
  const anotado = actual?.[CAMPO_PLAN_VIGENTE];
  const cobroAnotado = actual?.[CAMPO_COBRO_DEL_VIGENTE];
  // Lo que ESTE plan cobro, tal como se compara y tal como se anota si escribe.
  const cobro = cobrosExitosos(mp.summarized) > 0;
  if (typeof anotado === "string" && anotado !== "" && anotado !== planId) {
    const pisa = puedePisarAlVigente(
      {
        planId,
        status,
        altaMs: comoTimestamp(planDoc?.createdAt)?.toMillis() ?? null,
        cobro,
      },
      {
        planId: anotado,
        status: actual?.status,
        altaMs: await altaDelPlanMs(app, anotado),
        // Lo que anoto el plan que escribio el estado. Asumir `true` NO era
        // inocuo: dejaba perder el periodo pago de un plan viejo contra la baja de
        // un checkout nuevo que nunca cobro. Sin booleano —inalcanzable por
        // construccion: `mpPlanId` nace en el mismo `set` que esta clave— se
        // conserva el `true` de antes.
        cobro: typeof cobroAnotado === "boolean" ? cobroAnotado : true,
      },
    );
    if (!pisa) {
      logger.info("mp/reconcile: el plan ya no es el vigente del PF — no pisa su estado", {
        planId,
        uid,
        planVigente: anotado,
        status,
        statusVigente: actual?.status,
      });
      // La baja de ESTE plan sigue siendo un hecho de MP, aunque no mande.
      await marcarTerminalSiSeDioDeBaja(app, planId, status, planDoc);
      return {
        planId,
        outcome: "skipped-plan-no-vigente",
        uid,
        producto: "trainer",
        tier: mapping.tier,
        status,
      };
    }
  }

  // El arrepentimiento devuelve TODO lo pagado, así que el acceso de ESTE plan
  // termina en el momento en que se confirmó: el fin de período es ese instante
  // (ver `arrepentidoAtDe`). Sin esto, el próximo evento de MP recalcularía
  // «cancelado, período hasta el día X».
  //
  // El piso prepago, más abajo, NO se toca: es el resto YA PAGADO de un plan
  // anterior, y quitárselo sería revocar algo que este arrepentimiento no
  // devuelve (política de `subscription-state.ts`). Si el equipo devuelve
  // también ese pago, tiene que quitarlo a mano — el aviso lo advierte.
  const arrepentidoAt = status === "cancelled" ? arrepentidoAtDe(planDoc) : null;

  // El tope de la prueba diferida se aplica SOLO en la rama sin arrepentimiento:
  // el instante del arrepentimiento gana sobre cualquier fin de periodo, y ahi ni
  // se pregunta. Para un plan normal `conTopeDeLaPruebaDiferida` no cambia nada.
  const periodEnd =
    arrepentidoAt !== null
      ? Timestamp.fromMillis(arrepentidoAt)
      : conTopeDeLaPruebaDiferida(
        resolverFinDePeriodo({
          deMp: parsePeriodEnd(mp.next_payment_date, planId),
          yaGuardada: actual?.currentPeriodEnd,
          autoRecurring: mp.auto_recurring,
          status,
          planId,
        }),
        pruebaDiferida,
        { planId, uid },
      );

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

  // `mpPlanCobro` es MONOTONO por plan: un cobro que ya anotamos no se desanota.
  // `summarized` puede venir atrasado (el indice de busqueda de MP tarda), y un
  // re-reconcile del mismo plan que lo viera en cero reescribiria `true` -> `false`;
  // si eso pasa en la baja, el dato se congela (el plan sale del barrido) y el
  // plan que llegue despues lo lee mal. Solo aplica al mismo plan: si el estado
  // lo escribio OTRO, lo que cobro este es lo que corresponde anotar.
  const cobroAnotar =
    cobro || (anotado === planId && cobroAnotado === true);

  // El plan que escribe es parte de lo escrito. Un estado de antes de que
  // existiera `mpPlanId` o `mpPlanCobro` se reescribe UNA vez para anotarlos:
  // dispara `syncEntitlementsOnSubscription` (compara el mapa serializado), pero
  // no manda mail ni bloquea a nadie, porque el limite no cambia.
  const sinCambios =
    actual != null &&
    actual[CAMPO_PLAN_VIGENTE] === planId &&
    // Un `active` cuyo primer cobro cae sin cambio de estado igual tiene que
    // dejar el dato al dia: el que lo lee es el plan que llegue despues.
    actual[CAMPO_COBRO_DEL_VIGENTE] === cobroAnotar &&
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
          [CAMPO_PLAN_VIGENTE]: planId,
          [CAMPO_COBRO_DEL_VIGENTE]: cobroAnotar,
        },
      },
      // `merge` y no `set` pelado: el documento de usuario tiene el perfil
      // entero. Sin merge, reconciliar una suscripcion borraria la cuenta.
      { merge: true },
    );

    logger.info("mp/reconcile: suscripcion actualizada", {
      planId,
      uid,
      tier: mapping.tier,
      status,
    });
  }

  // La baja es terminal en MP: no se reactiva un preapproval cancelado, se
  // crea uno nuevo con otro id. Marcarlo saca este id del barrido y le ahorra
  // una llamada diaria a MP para siempre.
  //
  // ── FUERA del `if (!sinCambios)`, y es el arreglo ──
  //
  // Las dos escrituras (el usuario y el plan) no son atomicas. Con la marca
  // adentro del `if`, una falla entre las dos dejaba el `subscription` ya
  // escrito y el plan sin marcar, y la corrida siguiente veia `sinCambios` y
  // nunca la reintentaba: el plan quedaba sin `terminal` PARA SIEMPRE. No era
  // solo ruido en el barrido. `terminal` es lo que distingue, para
  // `planesARevisar`, un plan que tuvo una suscripcion de verdad de un checkout
  // que nadie pago, asi que un plan pagado y sin marca dejaba de contar como
  // evidencia de pago y a ese PF se le cobraba en el acto lo que ya tenia pago.
  //
  // Ahora se escribe siempre que MP diga `cancelled` y el plan no la tenga. Es
  // idempotente (`merge`, sin motivo): la unica clase de `terminal` sin motivo
  // es justamente la baja (ver `motivos-terminal.ts`).
  await marcarTerminalSiSeDioDeBaja(app, planId, status, planDoc);

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

/**
 * Cuanto despues de su alta se sigue buscando en MP un checkout ABANDONADO que nunca
 * tuvo suscripcion, cuando el alumno confirma un plan nuevo
 * (`darDeBajaLosReemplazadosDelAlumno`).
 *
 * El barrido marca un plan abandonado recien cuando lleva [ABANDONO_MS] (30 dias) sin
 * suscripcion, y desde ahi no lo visita mas. Una ventana de 30 dias quedaria vacia:
 * todo abandonado ya tiene mas. Por eso es [ABANDONO_MS] mas 30 dias: el primer mes
 * despues de marcarlo. Cuanto vive de verdad un `init_point` no lo sabemos (no vence
 * mientras no se pruebe lo contrario), y la ventana de reuso de un checkout son 30
 * minutos, asi que no hay un numero que salga de MP: es un tope de costo. Cada
 * abandonado reciente cuesta una busqueda por reconciliacion de un plan activo del
 * alumno, durante un mes; pasado, ya no se busca (ver el hueco que deja en
 * `darDeBajaLosReemplazadosDelAlumno`).
 */
const VENTANA_DEL_ABANDONADO_PAGADO_TARDE_MS = ABANDONO_MS + 30 * 24 * 60 * 60 * 1000;

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
      // Solo lo pone el alumno: la baja de su plan reemplazado no se pudo hacer, y
      // la proxima corrida la reintenta. Un plan del PF nunca lo trae.
      if (res.bajaFallida === true) r.errors += 1;

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
