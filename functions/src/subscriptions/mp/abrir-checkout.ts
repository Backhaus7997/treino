/**
 * abrir-checkout.ts — la mecanica de abrir un checkout de Mercado Pago, comun
 * a los DOS productos.
 *
 * Salio de `create-preapproval.ts` cuando aparecio el segundo producto. Lo que
 * vive aca no es "codigo repetido" sino ~90 lineas de decisiones caras que no
 * pueden existir por duplicado:
 *
 *   - La ventana anti-doble-click. Dos copias es un cobro doble esperando.
 *   - El mapeo de un error de MP a `HttpsError`, que distingue `unavailable`
 *     de `internal` para que el cliente pueda ofrecer "probá de nuevo" sin
 *     mentir.
 *   - La validacion de `planId` e `init_point`, que falla ruidoso en vez de
 *     devolver un string vacio que el cliente intentaria abrir.
 *   - El ORDEN de las dos escrituras: el mapeo primero, el doc de checkout
 *     despues.
 *
 * ── Lo que NO vive aca, y por que ──
 *
 * El precio, el gate de rol y el `backUrl` se quedan en el callable de cada
 * producto. Son justamente lo que los hace distintos: el PF tiene una escalera
 * de tiers y vuelve al Coach Hub; el alumno tiene un solo plan y vuelve a la
 * landing. Meterlos aca obligaria a este archivo a saber de productos, que es
 * lo contrario de por que existe.
 */

import { App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { MpApiError, MpClient } from "./client";
import { PreapprovalMapping, recordPlan } from "./tier-mapping";

/** Coleccion del checkout en curso por usuario. Un doc por uid, se pisa. */
export const MP_CHECKOUTS_COLLECTION = "mp_checkouts";

/**
 * Cuanto vale reusar un checkout ya abierto.
 *
 * **Sin esto, dos clicks en el boton abren DOS suscripciones en MP, y si el
 * usuario completa las dos paga dos veces.** MP no deduplica: cada preapproval
 * es independiente.
 *
 * 30 minutos es la vida util razonable de una sesion de checkout. Pasado eso se
 * abre uno nuevo, porque un `init_point` viejo probablemente ya no le sirva a
 * nadie.
 */
export const CHECKOUT_REUSE_MS = 30 * 60 * 1000;

export interface CheckoutAbierto {
  /** La URL a la que hay que mandar al usuario. Es lo unico que el cliente usa. */
  initPoint: string;
  planId: string;
  /** `reused` cuando se devolvio un checkout ya abierto (doble click). */
  status: "created" | "reused";
}

export interface AbrirCheckoutInput {
  app: App;
  uid: string;
  /**
   * Lo que distingue UN checkout de otro para la ventana de reuso, y lo que se
   * guarda en el documento.
   *
   * ⚠️ **La huella del PF tiene que seguir siendo exactamente `{tier, cycle}`.**
   * Es la misma que se venia escribiendo antes de que existiera este archivo, y
   * los documentos de `mp_checkouts` que hay en produccion tienen esos dos
   * campos y ninguno mas. Agregarle un `producto: "trainer"` haria que ningun
   * doc previo matchee, y el primer PF que vuelva a tocar el boton dentro de su
   * ventana se lleva un plan de mas en MP.
   *
   * La del alumno es `{producto: "athlete", cycle}`. No colisionan: `role` es
   * inmutable y el documento esta keyeado por uid, asi que un mismo uid no
   * puede alternar entre los dos.
   */
  huella: Record<string, string>;
  /** Lo que el usuario ve como concepto del cobro en el resumen de MP. */
  reason: string;
  /** CONSTANTE del servidor. Nunca puede venir del cliente: seria un open redirect. */
  backUrl: string;
  /** En ARS. Sale del servidor, NUNCA del cliente. */
  amount: number;
  frequencyMonths: number;
  /** Lo que se escribe en `mp_plans` para que el cobro sea reconciliable. */
  mapping: PreapprovalMapping;
  mpClient: MpClient;
  /** Reloj inyectable: la ventana de reuso se testea sin esperar 30 minutos. */
  nowMs: number;
}

/**
 * Abre un checkout, o devuelve el que ya estaba abierto.
 *
 * Total respecto de MP: cualquier falla de la API sale como `HttpsError`, nunca
 * como una excepcion cruda.
 */
export async function abrirCheckout(
  i: AbrirCheckoutInput,
): Promise<CheckoutAbierto> {
  const { app, uid, huella, mapping, nowMs } = i;

  const checkoutRef = getFirestore(app)
    .collection(MP_CHECKOUTS_COLLECTION)
    .doc(uid);

  // ── Reuso: el mismo plan, pedido de nuevo, dentro de la ventana ──
  const previo = (await checkoutRef.get()).data();
  if (previo) {
    const creado = previo.createdAtMs;
    const vigente =
      typeof creado === "number" && nowMs - creado < CHECKOUT_REUSE_MS;
    const mismaHuella = Object.entries(huella)
      .every(([k, v]) => previo[k] === v);
    if (
      vigente &&
      mismaHuella &&
      typeof previo.initPoint === "string" && previo.initPoint !== "" &&
      typeof previo.planId === "string" && previo.planId !== ""
    ) {
      logger.info("mp/abrir-checkout: se reusa el checkout abierto", {
        uid,
        ...huella,
        planId: previo.planId,
      });
      return {
        initPoint: previo.initPoint,
        planId: previo.planId,
        status: "reused",
      };
    }
  }

  let creado;
  try {
    creado = await i.mpClient.createPreapprovalPlan({
      reason: i.reason,
      externalReference: uid,
      backUrl: i.backUrl,
      transactionAmount: i.amount,
      frequencyMonths: i.frequencyMonths,
    });
  } catch (e) {
    const err = e as MpApiError;
    logger.error("mp/abrir-checkout: MP rechazo la creacion", {
      uid,
      ...huella,
      status: err.status,
      body: err.body,
    });
    // `unavailable` solo cuando reintentar sirve: el cliente puede ofrecer
    // "probá de nuevo" sin mentir. Lo demas es `internal` — un 401 nuestro no
    // se arregla porque el usuario vuelva a tocar el boton.
    throw new HttpsError(
      err.retryable ? "unavailable" : "internal",
      "no se pudo abrir el checkout de Mercado Pago",
    );
  }

  const planId = creado.id;
  const initPoint = (creado as { init_point?: unknown }).init_point;
  if (typeof planId !== "string" || planId === "") {
    throw new HttpsError("internal", "MP no devolvio un id de plan");
  }
  if (typeof initPoint !== "string" || initPoint === "") {
    // Sin `init_point` el usuario no tiene a donde ir. Falla ruidoso en vez de
    // devolver un string vacio que el cliente intentaria abrir.
    throw new HttpsError("internal", "MP no devolvio init_point");
  }

  // El mapeo va PRIMERO, antes del doc de checkout: si algo falla despues, lo
  // que no se puede perder es de que plan es esta suscripcion. El checkout es
  // una comodidad; el mapeo es lo que hace reconciliable el cobro.
  await recordPlan(app, planId, mapping);

  await checkoutRef.set({
    planId,
    ...huella,
    initPoint,
    // Milisegundos y no serverTimestamp: la ventana de reuso se compara contra
    // un reloj inyectado, y un sentinel no se puede leer en el mismo request.
    createdAtMs: nowMs,
  });

  logger.info("mp/abrir-checkout: checkout abierto", { uid, ...huella, planId });

  return { initPoint, planId, status: "created" };
}
