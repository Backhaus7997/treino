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
import { diasDePrueba } from "./diferir-primer-cobro";
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
  /**
   * Hasta cuando (ms) ya tiene pago el periodo este usuario, o `null` / ausente
   * para un checkout normal, que cobra al autorizar. Lo decide
   * `diferir-primer-cobro.ts`; aca solo se aplica.
   *
   * Es el UNICO dato del diferimiento que viaja. Los dias de prueba se calculan
   * en esta funcion a partir de el y de [nowMs], para que el plan de MP, el
   * documento de checkout y el de `mp_plans` no puedan contradecirse.
   *
   * Cuenta para la ventana de reuso y se compara APARTE de [huella], con un
   * `?? null` de cada lado. Dos razones:
   *
   *   - Un checkout diferido NO se puede reusar para un pedido normal (ni al
   *     reves): el reusado cobraria en el acto, o difiriria lo que ya no esta
   *     pago. Cualquiera de los dos es un cobro mal hecho.
   *   - La huella no puede ganar campos (ver su dartdoc), y este NO la gana. Un
   *     documento de checkout anterior a esto no trae el campo, y con el `?? null`
   *     sigue siendo igual a un pedido normal: el doble click de un PF que ya
   *     tenia un checkout abierto cuando se desplego esto sigue deduplicandose.
   */
  diferidoHastaMs?: number | null;
  mpClient: MpClient;
  /** Reloj inyectable: la ventana de reuso se testea sin esperar 30 minutos. */
  nowMs: number;
}

/** Un checkout abierto, tal como esta guardado en `mp_checkouts/{uid}`. */
export interface CheckoutGuardado {
  initPoint: string;
  planId: string;
  /**
   * El `diferidoHastaMs` guardado, o `null` si el documento no lo tiene (un
   * checkout normal, o uno anterior al diferimiento). SIN interpretar: puede no
   * ser un numero, y quien lo compara lo hace con `===`.
   */
  diferidoHastaMs: unknown;
}

/**
 * El checkout abierto de [previo] SI todavia sirve para este pedido, o `null`.
 *
 * Sirve cuando se creo dentro de [CHECKOUT_REUSE_MS], coincide la [huella] ENTERA,
 * y tiene `initPoint` y `planId`. NO mira el diferimiento: eso lo compara quien
 * llama, porque `create-preapproval.ts` necesita LEER cual es antes de decidir si
 * sale a MP.
 *
 * Es la UNICA definicion de "el checkout vigente". La usan `abrirCheckout` para
 * reusar y `create-preapproval.ts` para saltearse la busqueda en MP cuando un
 * doble click va a reusar un checkout diferido: con dos copias, la ventana de
 * una podria divergir de la de la otra y un pedido se saltearia la verificacion
 * para despues NO reusar.
 */
export function checkoutVigente(
  previo: Record<string, unknown> | undefined,
  huella: Record<string, string>,
  nowMs: number,
): CheckoutGuardado | null {
  if (!previo) return null;

  const creado = previo.createdAtMs;
  const vigente =
    typeof creado === "number" && nowMs - creado < CHECKOUT_REUSE_MS;
  const mismaHuella = Object.entries(huella)
    .every(([k, v]) => previo[k] === v);
  if (!vigente || !mismaHuella) return null;

  const { initPoint, planId } = previo;
  if (typeof initPoint !== "string" || initPoint === "") return null;
  if (typeof planId !== "string" || planId === "") return null;

  return { initPoint, planId, diferidoHastaMs: previo.diferidoHastaMs ?? null };
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
  // `null` = checkout normal. Se normaliza una sola vez: ausente, `undefined` y
  // `null` quieren decir lo mismo en la entrada y en lo que se guarda.
  const diferidoHastaMs = i.diferidoHastaMs ?? null;

  const checkoutRef = getFirestore(app)
    .collection(MP_CHECKOUTS_COLLECTION)
    .doc(uid);

  // ── Reuso: el mismo plan, pedido de nuevo, dentro de la ventana ──
  //
  // Ver el dartdoc de `AbrirCheckoutInput.diferidoHastaMs`: el diferimiento se
  // compara aparte de la huella, y con `?? null` (adentro de `checkoutVigente`)
  // para que un documento sin el campo siga valiendo como "normal".
  const abierto = checkoutVigente((await checkoutRef.get()).data(), huella, nowMs);
  if (abierto && abierto.diferidoHastaMs === diferidoHastaMs) {
    logger.info("mp/abrir-checkout: se reusa el checkout abierto", {
      uid,
      ...huella,
      planId: abierto.planId,
    });
    return {
      initPoint: abierto.initPoint,
      planId: abierto.planId,
      status: "reused",
    };
  }

  // Los dias de prueba salen de aca y de ningun otro lado, a partir de la fecha
  // y del reloj de ESTE request. `diasDePrueba` cuenta los dias de CALENDARIO
  // ARGENTINO entre hoy y el dia en que vence lo que el PF ya pago (del 2/10 al
  // 1/11 son 30). Que MP cuente la prueba como suponemos (N corridas de 24 h desde
  // la autorizacion, o sea que el primer cobro cae ese mismo dia argentino) NO esta
  // medido: ver "Lo que se ASUME de MP" en `diferir-primer-cobro.ts`.
  const freeTrialDays =
    diferidoHastaMs === null ? undefined : diasDePrueba(diferidoHastaMs, nowMs);

  let creado;
  try {
    creado = await i.mpClient.createPreapprovalPlan({
      reason: i.reason,
      externalReference: uid,
      backUrl: i.backUrl,
      transactionAmount: i.amount,
      frequencyMonths: i.frequencyMonths,
      // Solo cuando hay prueba: el pedido normal llega a MP exactamente como antes.
      ...(freeTrialDays === undefined ? {} : { freeTrialDays }),
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
  await recordPlan(app, planId, mapping, diferidoHastaMs);

  await checkoutRef.set({
    planId,
    ...huella,
    initPoint,
    // Milisegundos y no serverTimestamp: la ventana de reuso se compara contra
    // un reloj inyectado, y un sentinel no se puede leer en el mismo request.
    createdAtMs: nowMs,
    // SOLO cuando hay diferimiento: el documento de un checkout normal queda con
    // la forma de siempre, y es la que el reuso espera de los ya guardados.
    ...(diferidoHastaMs === null ? {} : { diferidoHastaMs }),
  });

  logger.info("mp/abrir-checkout: checkout abierto", {
    uid,
    ...huella,
    planId,
    ...(freeTrialDays === undefined ? {} : { diasDePrueba: freeTrialDays }),
  });

  return { initPoint, planId, status: "created" };
}
