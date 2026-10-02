/**
 * create-athlete-preapproval.ts — el callable que abre el checkout del ALUMNO.
 *
 * Espejo de `create-preapproval.ts`, que hace lo mismo para el PF. La mecanica
 * la comparten en `abrir-checkout.ts`; lo que vive en cada uno es lo que los
 * hace distintos.
 *
 * ── Por que un archivo y no una rama del callable del PF ──
 *
 * Tres cosas que no se pueden compartir sin que alguna quede mintiendo:
 *
 *   1. El gate de rol es el opuesto: `athlete` contra `trainer`.
 *   2. El `BACK_URL` del PF carga un comentario largo sobre el hash routing
 *      del Coach Hub, el App Link y `coachHubRedirect`. Nada de eso le aplica
 *      al alumno, que vuelve a la landing. Un `BACK_URL` que es funcion del rol
 *      deja ese comentario mintiendole a la mitad de sus lectores.
 *   3. La atestacion registrada de `createPreapproval` dice «el tier y el ciclo
 *      son enums cerrados, el monto sale de TIER_PRICES_ARS». Con una rama de
 *      alumno esa frase deja de ser cierta, y no hay forma de corregirla sin
 *      describir dos productos en una sola exencion.
 *
 * ── Lo que NO cambia respecto del PF ──
 *
 * El monto **nunca** viene del cliente: la entrada es `{cycle, locale}` y los
 * dos son enums cerrados. El precio sale de `athlete-plan-config.ts`. El uid
 * sale del token y de ningun otro lado.
 *
 * ── Si vuelve con dias pagos, el primer cobro se difiere ──
 *
 * Igual que el PF: un alumno dado de baja conserva el acceso hasta el fin de lo
 * que pago, y si vuelve a suscribirse antes, el plan nuevo se abre con una prueba
 * de tantos dias de calendario argentino como le quedan, para que MP cobre recien
 * cuando vence lo que ya pago. La decision vive en `diferir-primer-cobro.ts`
 * (`decidirDiferimientoDeAlumno`), y no alcanza con `athleteSubscription`: ese
 * mapa no distingue a quien se dio de baja de quien paga, asi que se le pregunta
 * a MP por cada plan que puede cobrar.
 *
 * ── Cambiar de plan con el viejo cobrando: el nuevo difiere, el viejo se da de baja ──
 *
 * El que paga mensual y pide anual (o al reves) no tiene que darse de baja primero.
 * El plan nuevo se abre con una prueba hasta que vence lo que el viejo ya cobro
 * (`decidirCambioDePlanDelAlumno`), y cuando MP lo confirma el reconciliador da de
 * baja el viejo (`darDeBajaLosReemplazadosDelAlumno`, en `reconcile.ts`). Asi el
 * alumno usa lo que pago, despues la prueba, despues los cobros del nuevo, sin dos
 * cobros por el mismo periodo. Si abandona el checkout no se da de baja nada.
 *
 * ── Una sola pasada por MP: bloquea, cambia o difiere ──
 *
 * Antes de abrir nada el callable recorre en serie los planes del alumno que
 * pueden cobrar y le pregunta a MP por sus suscripciones
 * (`consultarPlanesDelAlumno`, con `estricto` y fallando cerrado). De esa lectura
 * sale una de estas cosas: una sola suscripcion que MP todavia cobra, y entonces es
 * un cambio de plan (que difiere, o se bloquea si no se puede establecer hasta
 * cuando esta pago; ver el cuerpo); mas de una, y se bloquea; ninguna pero un cobro
 * real con dias por delante, y el plan nuevo difiere su primer cobro; o ninguna de
 * las dos, y el checkout es el de siempre. Todo sale del mismo dato, asi que las
 * decisiones no pueden contradecirse.
 *
 * La fecha vuelve en la respuesta (`diferidoHastaIso`) porque el checkout de MP
 * rinde la prueba como «¡Tenés N días gratis!» (medido en produccion con el del
 * PF, PR #1291) y no hay un campo que cambie ese texto: la landing la usa para
 * avisar antes de mandar al alumno ahi.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

import {
  ATHLETE_PRICES_ARS,
  athleteAmountFor,
} from "../athlete-plan-config";
import { SubscriptionCycle } from "../tier-config";
import { CYCLES, MP_PLANS_COLLECTION, frequencyMonthsFor } from "./tier-mapping";
import { AthleteStatus, athleteStatusOtorga } from "./map-status";
import { puedeSeguirCobrando } from "./reconcile";
import { MpApiError, MpClient, createMpClient } from "./client";
import { CheckoutAbierto, abrirCheckout } from "./abrir-checkout";
import {
  CambioDePlanDelAlumno,
  Diferimiento,
  PlanDeLaCuenta,
  consultarPlanesDelAlumno,
  decidirCambioDePlanDelAlumno,
  decidirDiferimientoDeAlumno,
} from "./diferir-primer-cobro";

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

/**
 * Los locales a los que se puede volver despues de pagar.
 *
 * Son los dos que la landing declara en `src/i18n/routing.ts` del repo
 * `treino-app`. Lista blanca y no passthrough: ver [backUrlPara].
 */
export const LOCALES_DE_RETORNO = ["es", "en"] as const;

export type LocaleDeRetorno = (typeof LOCALES_DE_RETORNO)[number];

const LOCALE_POR_DEFECTO: LocaleDeRetorno = "es";

/**
 * A donde vuelve el navegador al salir del checkout.
 *
 * ── Por que la arma el servidor y no viaja en el body ──
 *
 * Una URL de retorno que venga del cliente es un **open redirect firmado por
 * nosotros**: el atacante manda a la victima a un checkout real de TREINO y la
 * devuelve a su propio dominio, con la confianza ya construida. Es el mismo
 * motivo por el que el `BACK_URL` del PF es una constante.
 *
 * Lo que SI viaja es el locale, y no rompe la propiedad: se valida contra
 * [LOCALES_DE_RETORNO] y el servidor construye la URL. Un valor que no este en
 * la lista cae al default en vez de convertirse en un destino.
 *
 * ── Por que `/suscripcion/resultado` y no `/gracias` ──
 *
 * `/gracias` existe en la landing y parece la pagina obvia, pero su componente
 * `ThankYou` dispara `gtag("generate_lead")` y `fbq("Lead")` al montar — es la
 * pagina de la lista de espera. Mandar ahi el retorno de un pago haria que cada
 * cobro se cuente como un lead de waitlist en GA4 y en Meta. El evento de un
 * pago es `purchase`, y va en una ruta propia.
 *
 * ⚠️ Esta ruta TODAVIA NO EXISTE en `treino-app`. Se construye en el bloque W
 * del plan. Hasta entonces el retorno cae en un 404 — visible y arreglable, que
 * es preferible a mandarlo a una pagina que hace lo que no corresponde.
 */
export function backUrlPara(locale: unknown): string {
  const valido = (LOCALES_DE_RETORNO as readonly string[]).includes(
    locale as string,
  )
    ? (locale as LocaleDeRetorno)
    : LOCALE_POR_DEFECTO;
  return `https://gettreino.com/${valido}/suscripcion/resultado`;
}

export interface CreateAthletePreapprovalRequest {
  cycle: SubscriptionCycle;
  /** Opcional: sin el, se vuelve al locale por defecto. */
  locale?: LocaleDeRetorno;
}

export interface CreateAthletePreapprovalDeps {
  mpClient: MpClient;
  /** Reloj inyectable: el reuso de checkout se testea sin esperar 30 minutos. */
  nowMs: number;
  /**
   * El interruptor del diferimiento (`DIFERIR_PRIMER_COBRO_ENABLED`, el mismo del
   * PF). Ausente vale la constante, que es lo que usa el callable. Existe para que
   * los tests fijen el estado que prueban, como en `create-preapproval.ts`.
   */
  diferirHabilitado?: boolean;
}

/**
 * Lo que devuelve el checkout del alumno: el de siempre, mas la fecha del primer
 * cobro cuando se difiere.
 */
export interface CheckoutDelAlumno extends CheckoutAbierto {
  /**
   * SOLO cuando el primer cobro se difiere: hasta cuando ya tiene pago el periodo
   * (E), en ISO 8601. Es el dia en que se espera el primer cobro, y lo que la
   * landing le muestra al alumno antes de mandarlo a MP. Ausente, el checkout cobra
   * al autorizar, como siempre.
   *
   * Se calcula a partir del mismo valor que se le paso a `abrirCheckout`, asi que
   * vale igual para un checkout creado que para uno reusado: el reuso exige que
   * coincida el diferimiento.
   */
  diferidoHastaIso?: string;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** `unknown` → un miembro de la union, o `null`. Nunca un cast a ciegas. */
function parseCycle(raw: unknown): SubscriptionCycle | null {
  return typeof raw === "string" && (CYCLES as readonly string[]).includes(raw)
    ? (raw as SubscriptionCycle)
    : null;
}

/**
 * Si este alumno ya tiene derecho vigente Y su plan activo es de este ciclo.
 *
 * Las DOS condiciones hacen falta:
 *
 *   - Sin la del derecho, alguien cuyo plan vencio no podria volver a
 *     suscribirse nunca, porque el documento de `mp_plans` sigue ahi.
 *   - La del ciclo da el mensaje preciso para el caso comun (apretar de nuevo el
 *     mismo plan). El cambio de ciclo lo decide la pasada por MP que hace el
 *     callable (`consultarPlanesDelAlumno` y `decidirCambioDePlanDelAlumno`).
 *
 * Lee `mp_plans` con la misma consulta por uid que usa el resto del modulo
 * (`leerPlanes`, compartida con el diferimiento), y filtra EN MEMORIA: un
 * segundo `where` la convertiria en compuesta y exigiria desplegar un indice,
 * para uno o dos documentos por usuario.
 */
async function yaPagaEsteCiclo(
  leerPlanes: () => Promise<PlanDeLaCuenta[]>,
  userData: Record<string, unknown> | undefined,
  cycle: SubscriptionCycle,
): Promise<boolean> {
  const sub = userData?.athleteSubscription as { status?: unknown } | undefined;
  const status = typeof sub?.status === "string" ? sub.status : null;
  if (status === null || !athleteStatusOtorga(status as AthleteStatus)) {
    return false;
  }

  return (await leerPlanes()).some(({ data: datos }) =>
    datos.producto === "athlete" &&
      datos.cycle === cycle &&
      puedeSeguirCobrando(datos));
}

/**
 * El cuerpo del callable, sin el envoltorio de Firebase. Testeable en local.
 */
export async function runCreateAthletePreapproval(
  app: App,
  uid: string,
  raw: unknown,
  deps: CreateAthletePreapprovalDeps,
): Promise<CheckoutDelAlumno> {
  const body = (raw ?? {}) as Record<string, unknown>;

  const cycle = parseCycle(body.cycle);
  if (!cycle) {
    throw new HttpsError(
      "invalid-argument",
      `cycle invalido: ${JSON.stringify(body.cycle)}`,
    );
  }

  // El rol se lee del documento, no del token: `role` es intrinseco y se
  // provisiona server-side (AGENTS.md regla 3). Un custom claim viejo en un
  // token sin refrescar seria una fuente mas debil.
  //
  // Y el gate es POSITIVO (`!== "athlete"`) y no negativo (`=== "trainer"`): un
  // documento sin `role`, o con un rol que todavia no existe, no puede comprar.
  const userSnap = await getFirestore(app).collection("users").doc(uid).get();
  if (!userSnap.exists || userSnap.data()?.role !== "athlete") {
    throw new HttpsError(
      "permission-denied",
      "solo un alumno puede contratar este plan",
    );
  }

  // ── El alumno VINCULADO no paga, nunca ──
  //
  // Su PF ya paga por ese cupo: es la regla de `docs/paywall-alumno-suelto.md`
  // §2 y la que ya implementa `resolveAthletePaywallEnforced`, que lo exime del
  // paywall mientras tenga un vinculo activo.
  //
  // Sin esta guarda, el que paga acá se lleva un cobro por algo que ya tiene
  // gratis — y encima el reconciliador se lo acredita, porque el derecho pago y
  // la exencion por vinculo son dos caminos distintos al mismo resultado.
  //
  // La query es la misma que `hasActiveTrainerLink`: no se reusa la funcion
  // porque vive en `athlete-paywall-enforced.ts`, que importa el interruptor
  // maestro del paywall — y este callable tiene que funcionar con el paywall
  // apagado.
  const vinculo = await getFirestore(app)
    .collection("trainer_links")
    .where("athleteId", "==", uid)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (!vinculo.empty) {
    throw new HttpsError(
      "failed-precondition",
      "tu entrenador ya paga tu lugar — no necesitas suscribirte",
    );
  }

  // Los planes de la cuenta se leen UNA vez y se comparten: los usan la pasada por
  // MP, el diferimiento y la guarda del mismo ciclo. Como el bloqueo mira a todo
  // alumno con planes (tenga o no acceso pago hoy: un plan pausado figura
  // `expired`), la lectura ya no depende del derecho; es una query por uid de uno
  // o dos documentos.
  const db = getFirestore(app);
  let planes: Promise<PlanDeLaCuenta[]> | null = null;
  const leerPlanes = (): Promise<PlanDeLaCuenta[]> =>
    (planes ??= db
      .collection(MP_PLANS_COLLECTION)
      .where("uid", "==", uid)
      .get()
      .then((snap) => snap.docs.map((d) => ({ id: d.id, data: d.data() }))));

  // ── UNA pasada por MP, y de ahi salen todas las respuestas ──
  //
  // Antes de abrir nada se le pregunta a MP, plan por plan y en serie, por las
  // suscripciones de los planes del alumno que todavia pueden cobrar. De esa misma
  // lectura sale:
  //
  //   1. ¿Hay UNA que MP todavia cobra? Es un cambio de plan:
  //      `decidirCambioDePlanDelAlumno` dice si el nuevo difiere su primer cobro
  //      hasta que vence lo que el viejo cobro, o si se bloquea (mas abajo).
  //   2. ¿Mas de una? Se bloquea.
  //   3. Si ninguna cobra: ¿hay un cobro real que respalde dias pagos? Entonces el
  //      plan nuevo difiere su primer cobro (`decidirDiferimientoDeAlumno`, que lee
  //      de lo que ya se contesto y no vuelve a salir a la red).
  //
  // Cada plan se paga una vez y las decisiones no pueden contradecirse: salen del
  // mismo dato. Va despues del gate de rol y del vinculo: un PF o un alumno
  // vinculado no tienen que gastar una sola llamada.
  //
  // Si algo falla se TIRA, y lo que falla es o la lectura de `mp_plans` o una
  // consulta a MP. Seguir sin saber si cobra algo es abrir un segundo cobro, y
  // seguir sin saber si tiene dias pagos es abrir un checkout que cobra en el acto:
  // el doble cobro que esto viene a cerrar. `unavailable` porque reintentar sirve.
  //
  // `estricto`: una respuesta rota de MP (sin `results` como array) falla en vez de
  // leerse como «no hay nada cobrando», que es lo que abriria el segundo cobro.
  //
  // Sin atajo del doble click, a diferencia del PF: el atajo no le pregunta nada a
  // MP, y aca esa pregunta es la que levanta la guarda del mismo ciclo y la que
  // frena un segundo toque sobre un checkout diferido que ya se autorizo (su plan
  // nuevo se consulta, esta vivo, y es el mismo ciclo o una segunda viva). Un doble
  // click que no pago vuelve a verificar y llega a la misma fecha, que es lo que
  // `abrirCheckout` necesita para reusar el checkout abierto.
  let consulta: Awaited<ReturnType<typeof consultarPlanesDelAlumno>>;
  let cambio: CambioDePlanDelAlumno | null = null;
  let diferimiento: Diferimiento;
  try {
    consulta = await consultarPlanesDelAlumno({
      planes: await leerPlanes(),
      leerSuscripciones: (planId) =>
        deps.mpClient.searchPreapprovalsByPlan(planId, { estricto: true }),
    });
    if (consulta.vivo) {
      // Con una viva no se pregunta por "volver con dias pagos": es un cambio.
      cambio = decidirCambioDePlanDelAlumno({
        uid,
        cycle,
        vivas: consulta.vivas,
        planes: await leerPlanes(),
        suscripciones: consulta.suscripciones,
        nowMs: deps.nowMs,
        habilitado: deps.diferirHabilitado,
      });
      diferimiento = cambio.tipo === "diferir"
        ? { diferir: true, diferidoHastaMs: cambio.diferidoHastaMs }
        : { diferir: false, motivo: "no-esta-cancelada" };
    } else {
      const suscripciones = consulta.suscripciones;
      diferimiento = await decidirDiferimientoDeAlumno({
        uid,
        userData: userSnap.data(),
        nowMs: deps.nowMs,
        habilitado: deps.diferirHabilitado,
        leerPlanes,
        // Lo que la pasada ya trajo. Un plan que no esta es un error de armado de
        // los dos conjuntos de planes (el de la decision es un subconjunto del de
        // la pasada), no algo para pedirle a MP por la espalda.
        leerSuscripciones: async (planId) => {
          const subs = suscripciones.get(planId);
          if (subs === undefined) {
            throw new Error(`mp/create-athlete: el plan ${planId} no se consulto`);
          }
          return subs;
        },
      });
    }
  } catch (e) {
    const err = e as Partial<MpApiError>;
    logger.error(
      "mp/create-athlete-preapproval: no se pudo verificar la suscripcion " +
        "del alumno (plan vigente y dias pagos), no se abre el checkout",
      { uid, cycle, status: err.status, error: String(e) },
    );
    throw new HttpsError(
      "unavailable",
      "no pudimos verificar tu suscripcion actual, proba de nuevo en un rato",
    );
  }

  // ── No se puede comprar dos veces el MISMO ciclo ──
  //
  // La ventana de `abrirCheckout` cubre el doble click, pero sólo 30 minutos.
  // El caso que queda afuera es real y no tiene nada que ver con las tiendas:
  // alguien que ya paga vuelve a la pagina de precios un mes despues y aprieta
  // de nuevo, porque no se acuerda o porque no hay nada que se lo diga.
  //
  // Sin esta guarda MP le abre un segundo cobro.
  //
  // Y NO bloquea si el primer cobro se difiere. Hay dos formas de llegar ahi, y en
  // ninguna se compra dos veces lo mismo:
  //
  //   - `decidirDiferimientoDeAlumno`: solo difiere si, en ESTE pedido, MP contesto
  //     por cada plan del alumno que puede cobrar sin ninguna suscripcion viva
  //     (salvo los checkouts abandonados sin fecha, que al cerrarse no tenian
  //     ninguna; ver su encabezado). No hay un segundo cobro que evitar, y el plan
  //     nuevo empieza a cobrar recien cuando vence lo que ya pago. Sin esta
  //     excepcion, el que se dio de baja y cambio de idea no podria volver a su
  //     mismo plan hasta que se le corte el acceso, porque su plan dado de baja
  //     sigue sin ser `terminal` hasta entonces.
  //   - `decidirCambioDePlanDelAlumno`: solo difiere si la UNICA suscripcion viva
  //     es de OTRO ciclo (la del mismo sale `mismo-ciclo`), y esa se da de baja
  //     cuando el nuevo se confirma. Que quede otro plan del ciclo pedido que todavia
  //     da acceso (uno dado de baja con dias) no es comprarlo dos veces: ya no cobra.
  //
  // Va ANTES del bloqueo de abajo porque con una suscripcion viva en el mismo
  // ciclo el mensaje preciso es este; el de abajo cubre el resto.
  if (
    !diferimiento.diferir &&
    await yaPagaEsteCiclo(leerPlanes, userSnap.data(), cycle)
  ) {
    throw new HttpsError(
      "failed-precondition",
      "ya tenes una suscripcion activa con este ciclo",
    );
  }

  // ── Y no se abre un plan NUEVO mientras otro siga cobrando, salvo un cambio ──
  // ── de plan que se pueda hacer sin cobrar dos veces ──
  //
  // Hasta el #1305 esto abria el checkout y las DOS suscripciones quedaban
  // cobrando, porque la rama del alumno de `reconcile.ts` no daba de baja la vieja.
  // El #1305 lo bloqueo entero (el alumno tenia que darse de baja primero), y este
  // bloque era esa mitigacion. Hoy la vieja se da de baja cuando el nuevo se
  // confirma (`darDeBajaLosReemplazadosDelAlumno`), asi que el cambio de ciclo pasa
  // en un paso cuando `decidirCambioDePlanDelAlumno` puede diferirlo (o, desde un
  // plan pausado sin dias pagos, cobrar al autorizar). Se sigue bloqueando:
  //
  //   - con mas de una suscripcion viva (ya hay un cobro doble; un tercer plan no lo
  //     arregla), con el mismo ciclo, o con un estado que no deja cambiar de un paso
  //     (un cobro pendiente, un estado que no conocemos);
  //   - cuando el viejo autorizado se renueva en menos de `MIN_PAGO_PARA_CAMBIAR_MS`
  //     (con su propio mensaje: pasada la renovacion, el cambio se puede hacer);
  //   - cuando no se puede establecer hasta cuando esta pago el viejo. NO se cobra
  //     en el acto: con la baja del viejo al confirmar, el alumno perderia los dias
  //     que pago. Se da de baja desde la web y vuelve, y ahi el que vuelve con dias
  //     pagos se difiere;
  //   - con el interruptor del diferimiento apagado: sin prueba, lo unico que queda
  //     es cobrar en el acto, que es el caso anterior.
  //
  // Los dos huecos que la mitigacion tampoco cerraba siguen abiertos, y esta baja los
  // achica sin cerrarlos:
  //
  //   (a) el indice de busqueda de MP llega tarde (~93 s, ver `reconcile.ts`): un
  //       plan recien autorizado puede no aparecer todavia. El alumno autoriza el
  //       plan diferido B y aprieta de nuevo dentro de esos ~93 s: B vuelve vacio, y
  //       la pasada ve solo al viejo (si su baja tampoco se ve todavia) o a ninguno.
  //       Dentro de la ventana de reuso de 30 minutos vuelve el mismo `init_point`;
  //       pasada, se abre un plan C con prueba. Si C tambien se autoriza, cuando se
  //       confirma da de baja lo MAS VIEJO que cobre (B incluido) y el cobro doble se
  //       cierra antes del primer cobro, que es en E. Ventana minuscula.
  //   (b) dos `init_point` abiertos (una pestaña vieja sin pagar y el checkout
  //       nuevo) que se pagan los dos despues: el `init_point` no vence. El que se
  //       confirma da de baja solo lo mas viejo que el, asi que si el viejo se paga
  //       DESPUES, lo da de baja la proxima reconciliacion del nuevo (el barrido de
  //       las 03:00 lo visita todas las noches); hasta entonces cobran los dos, y si
  //       el viejo no difiere, ese primer cobro ya salio.
  //
  // El mensaje evita las palabras «entrenador» y «ciclo» a proposito: la landing
  // (`motivoDeLaPrecondicion`, treino-app) decide el copy buscandolas en el texto,
  // y cualquiera de las dos mostraria un motivo que aca es falso.
  // La baja del alumno vive en la web (`/suscripcion/baja`, treino-app), no en
  // la app.
  if (cambio !== null && (cambio.tipo === "bloquear" || cambio.tipo === "mismo-ciclo")) {
    logger.info(
      "mp/create-athlete-preapproval: hay un plan que sigue cobrando y el cambio " +
        "no se puede hacer de un paso, no se abre otro checkout",
      {
        uid,
        cycle,
        planVivo: consulta.vivo ? consulta.planId : null,
        motivo: cambio.tipo === "bloquear" ? cambio.motivo : "mismo-ciclo",
      },
    );
    // El plan viejo se renueva en pocos dias (`MIN_PAGO_PARA_CAMBIAR_MS`): pasada
    // la renovacion el cambio difiere normalmente, y eso es lo que se le dice.
    if (cambio.tipo === "bloquear" && cambio.motivo === "pago-vence-pronto") {
      throw new HttpsError(
        "failed-precondition",
        "tu plan actual se renueva en los proximos dias — proba cambiar de plan " +
          "despues de esa renovacion, o dalo de baja primero desde la web (Suscripcion > Baja)",
      );
    }
    throw new HttpsError(
      "failed-precondition",
      "ya tenes un plan que se sigue cobrando — para cambiar de plan, " +
        "dalo de baja primero desde la web (Suscripcion > Baja) y despues contrata el nuevo",
    );
  }

  const diferidoHastaMs = diferimiento.diferir
    ? diferimiento.diferidoHastaMs
    : null;

  const checkout = await abrirCheckout({
    app,
    uid,
    // Sin `tier`: el alumno tiene UN plan. La huella del PF es `{tier, cycle}` y
    // no colisiona con esta — `role` es inmutable y el doc esta keyeado por uid,
    // asi que un mismo uid no puede alternar entre las dos.
    huella: { producto: "athlete", cycle },
    reason: `TREINO Pro (${cycle === "annual" ? "anual" : "mensual"})`,
    backUrl: backUrlPara(body.locale),
    amount: athleteAmountFor(cycle),
    frequencyMonths: frequencyMonthsFor(cycle),
    mapping: { producto: "athlete", uid, cycle },
    // `null` es el checkout de siempre. El campo NO va en la huella: ver el
    // dartdoc de `AbrirCheckoutInput.diferidoHastaMs`.
    diferidoHastaMs,
    mpClient: deps.mpClient,
    nowMs: deps.nowMs,
  });

  return diferidoHastaMs === null
    ? checkout
    : { ...checkout, diferidoHastaIso: new Date(diferidoHastaMs).toISOString() };
}

export const createAthletePreapproval = functions.onCall(
  { region: "southamerica-east1", secrets: [MP_ACCESS_TOKEN] },
  async (request): Promise<CheckoutDelAlumno> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "hay que estar logueado");
    }
    return runCreateAthletePreapproval(
      ensureApp(),
      request.auth.uid,
      request.data,
      {
        mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
        nowMs: Date.now(),
      },
    );
  },
);

/**
 * El precio del plan del alumno, para que la landing lo muestre.
 *
 * ── Por que un callable y no una constante en el bundle ──
 *
 * Porque la landing vive en otro repositorio. Un numero de plata escrito en un
 * JSON de next-intl se desincroniza de `ATHLETE_PRICES_ARS` el dia que alguien
 * cambie uno de los dos, y el modo de falla es que le mostramos al alumno un
 * precio y le cobramos otro — que en Argentina es, ademas, publicidad enganosa.
 *
 * Cuesta un round-trip y elimina toda una clase de bug.
 *
 * ── Por que NO exige auth ──
 *
 * Es la unica lectura publica del repo, a proposito: la pagina de precios tiene
 * que poder mostrar cuanto sale ANTES de que el alumno se loguee. Pedirle
 * cuenta para ver un precio es exactamente la friccion que este canal viene a
 * sacar.
 *
 * No hay nada que proteger: el precio es publico por definicion — se va a
 * publicar en la landing — y este callable no escribe nada ni lee datos de
 * nadie.
 */
export const getAthletePricing = functions.onCall(
  { region: "southamerica-east1" },
  async () => ({
    currency: "ARS",
    /** Con impuestos incluidos, como exige el §6 de la spec legal web. */
    taxIncluded: true,
    monthly: ATHLETE_PRICES_ARS.monthly,
    annual: ATHLETE_PRICES_ARS.annual,
  }),
);
