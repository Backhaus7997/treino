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
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
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
import { MpClient, createMpClient } from "./client";
import { CheckoutAbierto, abrirCheckout } from "./abrir-checkout";

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
 *   - Sin la del ciclo, el que quiere pasar de mensual a anual queda trabado.
 *
 * Lee `mp_plans` con la misma consulta por uid que usa el resto del modulo, y
 * filtra EN MEMORIA: un segundo `where` la convertiria en compuesta y exigiria
 * desplegar un indice, para uno o dos documentos por usuario.
 */
async function yaPagaEsteCiclo(
  app: App,
  uid: string,
  userData: Record<string, unknown> | undefined,
  cycle: SubscriptionCycle,
): Promise<boolean> {
  const sub = userData?.athleteSubscription as { status?: unknown } | undefined;
  const status = typeof sub?.status === "string" ? sub.status : null;
  if (status === null || !athleteStatusOtorga(status as AthleteStatus)) {
    return false;
  }

  const snap = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .where("uid", "==", uid)
    .get();

  return snap.docs.some((d) => {
    const datos = d.data();
    return datos.producto === "athlete" &&
      datos.cycle === cycle &&
      puedeSeguirCobrando(datos);
  });
}

/**
 * El cuerpo del callable, sin el envoltorio de Firebase. Testeable en local.
 */
export async function runCreateAthletePreapproval(
  app: App,
  uid: string,
  raw: unknown,
  deps: CreateAthletePreapprovalDeps,
): Promise<CheckoutAbierto> {
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

  // ── No se puede comprar dos veces el MISMO ciclo ──
  //
  // La ventana de `abrirCheckout` cubre el doble click, pero sólo 30 minutos.
  // El caso que queda afuera es real y no tiene nada que ver con las tiendas:
  // alguien que ya paga vuelve a la pagina de precios un mes despues y aprieta
  // de nuevo, porque no se acuerda o porque no hay nada que se lo diga.
  //
  // Sin esta guarda MP le abre un segundo cobro. El reconciliador lo corrige
  // despues —`darDeBajaLosReemplazados` da de baja el plan viejo cuando el
  // nuevo confirma— pero "se corrige despues" significa que en el medio existio
  // un momento con dos suscripciones vivas, y esa ventana la paga el alumno.
  //
  // ⚠️ **Sólo bloquea el MISMO ciclo, y eso es el punto.** Un alumno que paga
  // mensual y quiere pasarse a anual tiene que poder hacerlo: ese camino es
  // exactamente para lo que existe `darDeBajaLosReemplazados`, y bloquearlo
  // seria cerrarle la puerta al que quiere pagarnos mas.
  if (await yaPagaEsteCiclo(app, uid, userSnap.data(), cycle)) {
    throw new HttpsError(
      "failed-precondition",
      "ya tenes una suscripcion activa con este ciclo",
    );
  }

  return abrirCheckout({
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
    mpClient: deps.mpClient,
    nowMs: deps.nowMs,
  });
}

export const createAthletePreapproval = functions.onCall(
  { region: "southamerica-east1", secrets: [MP_ACCESS_TOKEN] },
  async (request): Promise<CheckoutAbierto> => {
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
