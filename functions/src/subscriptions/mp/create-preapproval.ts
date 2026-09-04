/**
 * create-preapproval.ts — el UNICO punto de la app que abre un cobro.
 *
 * Patron: handler puro (`runCreatePreapproval`) + wrapper `onCall` fino
 * (`createPreapproval`), igual que `add-alias.ts` y `accept-trainer-link.ts`
 * (ADR-CXP-004), asi el handler se testea sin la maquinaria de onCall y sin red.
 *
 * ── LO QUE ESTA FUNCION NO HACE, Y ES LA MITAD DEL DISEÑO ──
 *
 * **No escribe `subscription`.** Ni siquiera `pending`. Crear un preapproval no
 * es cobrar: MP lo deja en `pending` hasta que el PF carga su medio de pago en
 * el `init_point`. Escribir el tier acá le daria el limite del plan a alguien
 * que todavia no pago nada — y como `subscription` es CF-write-only y esta
 * pineado en rules, quedaria ahi hasta que otra function lo saque.
 *
 * El tier lo escribe el RECONCILIADOR, cuando MP diga `authorized`. Es el mismo
 * principio que gobierna toda la integracion y que esta escrito en
 * `mp/client.ts`: la verdad se le pregunta a MP, no se asume.
 *
 * ── El monto NUNCA viene del cliente ──
 *
 * La entrada es `{ tier, cycle }`, dos enums. El precio sale de
 * `TIER_PRICES_ARS` en el servidor. Aceptar un `amount` del cliente seria
 * dejar que el PF elija cuanto pagar, y no hay validacion que arregle eso —
 * cualquier monto que "parezca razonable" tambien lo parece $1.
 *
 * ── El mail tampoco ──
 *
 * `payer_email` sale de `request.auth.token.email`, que lo firma Firebase Auth.
 * Un mail del cliente dejaria abrir suscripciones a nombre de otro.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";

import { SubscriptionCycle, SubscriptionTier } from "../tier-config";
import {
  CYCLES,
  PAID_TIERS,
  amountFor,
  frequencyMonthsFor,
  recordPreapproval,
} from "./tier-mapping";
import { MpApiError, MpClient, createMpClient } from "./client";

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

/**
 * A donde vuelve el navegador al salir del checkout. CONSTANTE del servidor, a
 * proposito: si viniera del cliente seria un open redirect firmado por nosotros
 * — MP mandaria al PF a donde diga el atacante, saliendo de una URL nuestra.
 *
 * `/ajustes` es la seccion de Facturacion del Coach Hub, el mismo destino que
 * usan los callsites web del paywall (`billingRoute: '/ajustes'`).
 */
const BACK_URL = "https://app.gettreino.com/ajustes";

/** Coleccion del checkout en curso por PF. Un doc por uid, se pisa. */
export const MP_CHECKOUTS_COLLECTION = "mp_checkouts";

/**
 * Cuanto vale reusar un checkout ya abierto.
 *
 * Sin esto, dos clicks en "ELEGIR PLAN" abren DOS suscripciones en MP, y si el
 * PF completa las dos paga dos veces. MP no deduplica: cada preapproval es
 * independiente.
 *
 * 30 minutos es la vida util razonable de una sesion de checkout. Pasado eso se
 * abre uno nuevo, porque un `init_point` viejo probablemente ya no le sirva a
 * nadie.
 */
const CHECKOUT_REUSE_MS = 30 * 60 * 1000;

export interface CreatePreapprovalRequest {
  tier: SubscriptionTier;
  cycle: SubscriptionCycle;
}

export interface CreatePreapprovalResult {
  /** La URL a la que hay que mandar al PF. Es lo unico que el cliente usa. */
  initPoint: string;
  preapprovalId: string;
  /** `reused` cuando se devolvio un checkout ya abierto (doble click). */
  status: "created" | "reused";
}

export interface CreatePreapprovalDeps {
  mpClient: MpClient;
  /** Reloj inyectable: el reuso de checkout se testea sin esperar 30 minutos. */
  nowMs: number;
}

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/** `unknown` → un miembro de la union, o `null`. Nunca un cast a ciegas. */
function parseTier(raw: unknown): SubscriptionTier | null {
  return typeof raw === "string" &&
    (PAID_TIERS as readonly string[]).includes(raw)
    ? (raw as SubscriptionTier)
    : null;
}

function parseCycle(raw: unknown): SubscriptionCycle | null {
  return typeof raw === "string" && (CYCLES as readonly string[]).includes(raw)
    ? (raw as SubscriptionCycle)
    : null;
}

/**
 * El handler. Todo lo que decide entra por parametro: el uid y el mail ya
 * verificados, la entrada cruda, y las dependencias.
 *
 * Recibe `uid` y `email` YA extraidos del token y no el `request` entero para
 * que sea imposible leer del body algo que tiene que salir del token.
 */
export async function runCreatePreapproval(
  app: admin.app.App,
  uid: string,
  email: string,
  raw: unknown,
  deps: CreatePreapprovalDeps,
): Promise<CreatePreapprovalResult> {
  const body = (raw ?? {}) as Record<string, unknown>;

  const tier = parseTier(body.tier);
  if (!tier) {
    // `free` cae acá y esta bien: no es un plan que se compre, es la ausencia
    // de plan. Ofrecerlo en el checkout seria cobrarle a alguien por nada.
    throw new HttpsError(
      "invalid-argument",
      `tier invalido: ${JSON.stringify(body.tier)}`,
    );
  }

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
  const userSnap = await app.firestore().collection("users").doc(uid).get();
  if (!userSnap.exists || userSnap.data()?.role !== "trainer") {
    throw new HttpsError(
      "permission-denied",
      "solo un entrenador puede contratar un plan",
    );
  }

  const amount = amountFor(tier, cycle);
  if (amount === null) {
    // Inalcanzable: `parseTier` ya excluyo `free`. Existe para que agregar un
    // tier a PAID_TIERS sin precio falle acá y no con un monto `undefined`
    // viajando a MP.
    throw new HttpsError("internal", `sin precio para ${tier}/${cycle}`);
  }

  const checkoutRef = app
    .firestore()
    .collection(MP_CHECKOUTS_COLLECTION)
    .doc(uid);

  // ── Reuso: el mismo plan, pedido de nuevo, dentro de la ventana ──
  const previo = (await checkoutRef.get()).data();
  if (previo) {
    const creado = previo.createdAtMs;
    const vigente =
      typeof creado === "number" && deps.nowMs - creado < CHECKOUT_REUSE_MS;
    if (
      vigente &&
      previo.tier === tier &&
      previo.cycle === cycle &&
      typeof previo.initPoint === "string" && previo.initPoint !== "" &&
      typeof previo.preapprovalId === "string" && previo.preapprovalId !== ""
    ) {
      logger.info("mp/create-preapproval: se reusa el checkout abierto", {
        uid,
        tier,
        cycle,
        preapprovalId: previo.preapprovalId,
      });
      return {
        initPoint: previo.initPoint,
        preapprovalId: previo.preapprovalId,
        status: "reused",
      };
    }
  }

  let creado;
  try {
    creado = await deps.mpClient.createPreapproval({
      reason: `TREINO — ${tier} (${cycle === "annual" ? "anual" : "mensual"})`,
      externalReference: uid,
      payerEmail: email,
      backUrl: BACK_URL,
      transactionAmount: amount,
      frequencyMonths: frequencyMonthsFor(cycle),
    });
  } catch (e) {
    const err = e as MpApiError;
    logger.error("mp/create-preapproval: MP rechazo la creacion", {
      uid,
      tier,
      cycle,
      status: err.status,
      body: err.body,
    });
    // `unavailable` solo cuando reintentar sirve: el cliente puede ofrecer
    // "probá de nuevo" sin mentir. Lo demas es `internal` — un 401 nuestro no
    // se arregla porque el PF vuelva a tocar el boton.
    throw new HttpsError(
      err.retryable ? "unavailable" : "internal",
      "no se pudo abrir el checkout de Mercado Pago",
    );
  }

  const preapprovalId = creado.id;
  const initPoint = (creado as { init_point?: unknown }).init_point;
  if (typeof preapprovalId !== "string" || preapprovalId === "") {
    throw new HttpsError("internal", "MP no devolvio un id de preapproval");
  }
  if (typeof initPoint !== "string" || initPoint === "") {
    // Sin `init_point` el PF no tiene a donde ir. Falla ruidoso en vez de
    // devolver un string vacio que el cliente intentaria abrir.
    throw new HttpsError("internal", "MP no devolvio init_point");
  }

  // El mapeo va PRIMERO, antes del doc de checkout: si algo falla despues, lo
  // que no se puede perder es de que plan es esta suscripcion. El checkout es
  // una comodidad; el mapeo es lo que hace reconciliable el cobro.
  await recordPreapproval(app, preapprovalId, { uid, tier, cycle });

  await checkoutRef.set({
    preapprovalId,
    tier,
    cycle,
    initPoint,
    // Milisegundos y no serverTimestamp: la ventana de reuso se compara contra
    // un reloj inyectado, y un sentinel no se puede leer en el mismo request.
    createdAtMs: deps.nowMs,
  });

  logger.info("mp/create-preapproval: checkout abierto", {
    uid,
    tier,
    cycle,
    preapprovalId,
  });

  return { initPoint, preapprovalId, status: "created" };
}

export const createPreapproval = functions.onCall(
  // SIN enforceAppCheck, por el mismo motivo que `acceptTrainerLink`: el Coach
  // Hub web no activa App Check, y este callable se llama EXACTAMENTE desde
  // ahi. Con el flag puesto, todo checkout desde la web seria rechazado.
  //
  // La cerradura es otra: `request.auth`, el rol leido del documento, y el
  // hecho de que ni el monto ni el mail ni la URL de retorno vengan del
  // cliente.
  {
    region: "southamerica-east1",
    secrets: [MP_ACCESS_TOKEN],
  },
  async (request): Promise<CreatePreapprovalResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "hay que estar logueado");
    }
    const email = request.auth.token.email;
    if (typeof email !== "string" || email === "") {
      // MP exige un mail de pagador. Sin uno verificado por Firebase Auth no
      // se abre nada: el fallback obvio —pedirselo al cliente— es justo el
      // agujero que este chequeo cierra.
      throw new HttpsError(
        "failed-precondition",
        "la cuenta no tiene un mail asociado",
      );
    }

    return runCreatePreapproval(
      getApp(),
      request.auth.uid,
      email,
      request.data,
      {
        mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
        nowMs: Date.now(),
      },
    );
  },
);
