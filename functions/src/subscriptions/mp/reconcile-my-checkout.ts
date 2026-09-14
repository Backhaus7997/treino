/**
 * reconcile-my-checkout.ts — acreditarle el pago al PF EN EL ACTO, cuando vuelve
 * del checkout de Mercado Pago.
 *
 * ── El problema que existe para resolver ──
 *
 * Hasta acá, lo unico que escribia `subscription` era el barrido de las 03:00
 * (`reconcile.ts`). O sea que un PF que pagaba a las 10 AM veia su plan al dia
 * siguiente: hasta 24 horas de "pague y no paso nada", justo en el minuto de
 * mas ansiedad de todo el producto.
 *
 * El barrido no se toca y no se reemplaza. Sigue siendo la red que agarra al que
 * paga y cierra la pestaña, al que paga desde otro dispositivo, y a cualquiera a
 * quien este camino se le pierda. Esto es LATENCIA, no correccion — el mismo
 * reparto que ya declara el encabezado de `client.ts` para el webhook.
 *
 * ── Por que el planId NO viene del cliente ──
 *
 * Es la unica decision de seguridad del archivo y es la de siempre en este
 * modulo: la entrada del handler es el uid del token y NADA MAS. Si el planId
 * viajara en el body, cualquiera podria pedir que reconciliemos el plan de otro
 * — y como `reconcileSubscription` escribe `users/{uid}` con el uid que sale del
 * mapeo, eso es pedir escrituras sobre cuentas ajenas y enumerar quien compro
 * que. Los planes salen de `mp_plans`, filtrados por el uid del token.
 *
 * ── Por que se reconcilian TODOS sus planes y no "el del checkout" ──
 *
 * `mp_checkouts/{uid}` es un puntero de UNA sola ranura: se pisa en cada
 * checkout nuevo. Un PF que mira plan2, no paga, despues abre plan3 y paga el
 * link viejo de plan2 —la pestaña sigue abierta y nada invalida un `init_point`—
 * tiene el puntero en plan3 y el pago en plan2. Reconciliando por el puntero le
 * diriamos "no vemos tu pago" a alguien que pago.
 *
 * `mp_plans` tiene el `uid` en cada documento, asi que preguntar por TODOS sus
 * planes es una query de igualdad de un solo campo: sin indice compuesto, sin
 * nada que desplegar. Son uno o dos documentos por PF.
 *
 * ── Que planes se SALTEAN, y la asimetria que importa ──
 *
 * Los `terminal` se saltean, pero NO todos por el mismo motivo, y por eso se
 * mira `terminalReason`:
 *
 *   - `terminal` SIN motivo lo puso el reconciliador al ver `cancelled`. Una
 *     baja no se revierte en MP —se crea un preapproval nuevo con otro id—, asi
 *     que volver a preguntar por ese id no puede traer nada nuevo NUNCA.
 *   - `terminal` con motivo **"checkout abandonado"** lo puso el barrido porque
 *     el plan cumplio 30 dias sin suscripcion. Eso es una apuesta sobre el
 *     futuro, no un hecho: si el PF guardo el `init_point` y paga al dia 31, el
 *     barrido no lo va a ver nunca mas. Este callable es el UNICO rescate
 *     posible de ese caso, y por eso si los consulta.
 *
 * OJO: la regla NO es "con motivo se consulta". Hay un segundo motivo,
 * **"reemplazado por otro plan"**, que pone la baja del cambio de plan
 * (`reconcile.ts`), y ese SI es un hecho — MP confirmo la cancelacion. Consultar
 * esos planes no rompe nada, porque la guarda de reemplazo los corta antes de
 * salir a la red, pero la distincion que importa vive en `puedeSeguirCobrando`
 * de `reconcile.ts` y es por MOTIVO, no por "tiene o no tiene".
 *
 * ── El cooldown va ACA, y no se puede delegar ──
 *
 * `reconcileSubscription` sale a MP con `searchPreapprovalsByPlan` antes del
 * corto-circuito `sinCambios`. (Desde la baja del cambio de plan hay UN read de
 * Firestore antes —la guarda de reemplazo—, pero solo corta los planes que ya
 * dimos de baja nosotros: para todo lo demas el GET sigue siendo lo primero.) O
 * sea que las tres capas que ya protegen contra la tormenta de mails no cubren
 * nada de esto: un F5 en un SPA es un aterrizaje, y N aterrizajes son N llamadas
 * a MP con nuestro token aunque el outcome sea `unchanged` las N veces.
 *
 * Y a MP eso le importa: el barrido se escribio SECUENCIAL a proposito porque
 * "en paralelo son N requests simultaneos a MP, que responde 429". Quemarle el
 * cupo al barrido desde un boton del navegador seria cambiar 24 horas de latencia
 * por reconciliaciones nocturnas que no corren.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";

import { SubscriptionTier } from "../tier-config";
import { MpClient, createMpClient } from "./client";
import { MP_CHECKOUTS_COLLECTION } from "./create-preapproval";
import { ReconcileResult, reconcileSubscription } from "./reconcile";
import { MP_PLANS_COLLECTION } from "./tier-mapping";

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

/**
 * Cuanto tiene que esperar un PF entre dos consultas.
 *
 * Diez segundos y no un minuto: el caso normal de este callable es alguien que
 * ACABA de pagar y a quien MP todavia puede estar diciendole `pending`. El front
 * necesita poder repreguntar unas pocas veces sin que le cerremos la puerta, y
 * un cooldown largo convertiria "estamos confirmando tu pago" en un estado del
 * que no se sale sin recargar.
 *
 * Diez alcanzan para lo que esto tiene que frenar, que no es la impaciencia sino
 * el LOOP: seis llamadas por minuto por PF es ruido, seiscientas son un 429 que
 * deja al barrido sin reconciliar a nadie.
 */
export const RECONCILE_COOLDOWN_MS = 10_000;

/**
 * El estado que ve el PF. Es vocabulario del PRODUCTO, no de Mercado Pago ni de
 * `ReconcileOutcome`.
 *
 * La traduccion se hace acá y no en el cliente por una razon concreta: el
 * outcome `written` NO significa exito. Un `written` con status `pending` es
 * justo el caso de alguien a quien no se le acredito nada, y un front que
 * tratara `written` como "listo" le diria que ya tiene el plan a alguien que no
 * lo tiene. La condicion de exito son las DOS cosas juntas, y el unico lugar
 * donde estan las dos es este.
 */
export type EstadoDeAcreditacion =
  /** MP confirmo y el plan ya esta escrito. Es el unico exito. */
  | "acreditado"
  /** Hay un alta en curso que MP todavia no autorizo. Volver a preguntar sirve. */
  | "pendiente"
  /** No hay ningun plan que reconciliar. El PF entro a Ajustes por su cuenta. */
  | "sin-checkout"
  /** No pudimos preguntarle a MP. Reintentar sirve; el barrido lo cubre igual. */
  | "no-disponible";

export interface ReconcileMyCheckoutResult {
  estado: EstadoDeAcreditacion;
  /** Solo cuando `estado === "acreditado"`. El plan que quedo vigente. */
  tier?: SubscriptionTier;
  /**
   * `true` cuando la consulta se corto por el cooldown y se devuelve lo que ya
   * sabiamos. El front lo usa para no contar el intento como "MP dijo que no".
   */
  enfriando?: boolean;
}

export interface ReconcileMyCheckoutDeps {
  mpClient: MpClient;
  /** Reloj inyectable: el cooldown se testea sin esperar diez segundos. */
  nowMs: number;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** Un plan del PF que todavia vale la pena consultarle a MP. */
interface PlanConsultable {
  planId: string;
}

/**
 * Los planes de este PF que hay que consultar, en el orden en que Firestore los
 * devuelva.
 *
 * El filtro de `terminal` se hace EN MEMORIA y no en la query a proposito:
 * `where('uid','==',uid)` sola es una igualdad de un campo y anda con los
 * indices automaticos, pero agregarle `where('terminal','!=',true)` la convierte
 * en compuesta y exige desplegar un indice. Con uno o dos documentos por PF,
 * filtrar acá no cuesta nada y no agrega infraestructura.
 */
async function planesDelPf(
  app: App,
  uid: string,
): Promise<PlanConsultable[]> {
  const snap = await getFirestore(app)
    .collection(MP_PLANS_COLLECTION)
    .where("uid", "==", uid)
    .get();

  return snap.docs
    .filter((d) => {
      const datos = d.data();
      // Ver el encabezado: un `terminal` sin motivo es una baja y no puede
      // traer nada nuevo; uno con motivo es un abandono presunto, y este
      // callable es el unico que puede desmentirlo.
      return datos?.terminal !== true || typeof datos?.terminalReason === "string";
    })
    .map((d) => ({ planId: d.id }));
}

/**
 * Traduce lo que dijo el reconciliador a lo que ve el PF.
 *
 * Se queda con el MEJOR de todos sus planes, no con el ultimo: un PF que hizo
 * upgrade tiene dos, y que el plan viejo diga `active` mientras el nuevo dice
 * `pending` significa que SI tiene plan — decirle "estamos confirmando" seria
 * mentirle sobre lo que ya tiene.
 */
export function estadoDesdeResultados(
  resultados: ReconcileResult[],
): { estado: EstadoDeAcreditacion; tier?: SubscriptionTier } {
  if (resultados.length === 0) return { estado: "sin-checkout" };

  // `written` y `unchanged` son los dos unicos outcomes que traen `status`, y
  // `active`/`grace` los dos unicos status con derecho al tier pago
  // (`effective-limit.ts`). `grace` cuenta como acreditado a proposito: el plan
  // esta vigente y MP esta reintentando un cobro — el aviso de eso es un mail,
  // no la pantalla de "gracias por tu compra".
  const acreditado = resultados.find(
    (r) =>
      (r.outcome === "written" || r.outcome === "unchanged") &&
      (r.status === "active" || r.status === "grace"),
  );
  if (acreditado) return { estado: "acreditado", tier: acreditado.tier };

  // Que MP no conteste es distinto de que MP diga que no hay nada: en el primer
  // caso reintentar sirve, en el segundo hay que esperar. Se prioriza el error
  // porque es el unico de los dos que el PF puede accionar.
  if (resultados.some((r) => r.outcome === "error-mp")) {
    return { estado: "no-disponible" };
  }

  // Todo lo demas —`sin-suscripcion`, `pending`, y CUALQUIER `skipped-*`— es lo
  // mismo para el PF: hay un alta en curso que todavia no se pudo acreditar.
  //
  // Sin enumerarlos ni contarlos a proposito: la lista crece (el ultimo fue
  // `skipped-reemplazado`, con la baja de la suscripcion vieja al cambiar de
  // plan) y un cartel que dice "los tres" envejece mal sin que nadie lo note.
  // Los `skipped-*` son bugs nuestros o datos raros de MP, y ya se logearon con
  // detalle adentro del reconciliador; al PF no le sirve saber cual fue.
  return { estado: "pendiente" };
}

/**
 * El handler. Recibe el `uid` YA extraido del token, igual que
 * `runCreatePreapproval`, para que sea imposible leer del body algo que tiene
 * que salir del token. Acá es literal: NO HAY body.
 */
export async function runReconcileMyCheckout(
  app: App,
  uid: string,
  deps: ReconcileMyCheckoutDeps,
): Promise<ReconcileMyCheckoutResult> {
  const db = getFirestore(app);
  const checkoutRef = db.collection(MP_CHECKOUTS_COLLECTION).doc(uid);
  const checkout = (await checkoutRef.get()).data();

  // ── El cooldown, ANTES de cualquier llamada a MP ──
  const ultima = checkout?.lastReconcileMs;
  if (
    typeof ultima === "number" &&
    deps.nowMs - ultima < RECONCILE_COOLDOWN_MS
  ) {
    // No es un error y no se logea como tal: es el camino esperado de alguien
    // que recarga. Se devuelve `pendiente` y no el ultimo estado conocido
    // porque no lo tenemos sin preguntar — y `enfriando` le dice al front que
    // esto no es una respuesta de MP.
    return { estado: "pendiente", enfriando: true };
  }

  const planes = await planesDelPf(app, uid);
  if (planes.length === 0) {
    // Ni un plan a su nombre. Es el caso normal de un PF que entro a Ajustes
    // por su cuenta, y de todo el que nunca abrio un checkout. No se toca el
    // cooldown: no hubo ninguna llamada a MP que valga la pena frenar.
    return { estado: "sin-checkout" };
  }

  // El cooldown se marca ANTES de salir a MP, no despues. Si se marcara al
  // final, una funcion que tarda o revienta dejaria la puerta abierta para el
  // proximo click — y el caso en el que mas se clickea es justo ese.
  //
  // `merge: true` es obligatorio: sin el, esto BORRARIA el `initPoint` y el
  // `planId` del checkout en curso, que es lo que `createPreapproval` reusa
  // dentro de su ventana de 30 minutos. El PF perderia el link de pago que
  // estaba por usar.
  await checkoutRef.set({ lastReconcileMs: deps.nowMs }, { merge: true });

  // SECUENCIAL, por el mismo motivo que el barrido: en paralelo son N requests
  // simultaneos a MP, que contesta 429. Son uno o dos planes.
  const resultados: ReconcileResult[] = [];
  for (const { planId } of planes) {
    resultados.push(await reconcileSubscription(app, planId, deps));
  }

  const resuelto = estadoDesdeResultados(resultados);

  logger.info("mp/reconcile-my-checkout: consulta del PF al volver del pago", {
    uid,
    planes: planes.length,
    estado: resuelto.estado,
    outcomes: resultados.map((r) => r.outcome),
  });

  return resuelto;
}

export const reconcileMyCheckout = functions.onCall(
  // SIN enforceAppCheck, por el mismo motivo que `createPreapproval` y
  // `acceptTrainerLink`: el Coach Hub web no activa App Check, y este callable
  // se llama EXACTAMENTE desde ahi. Con el flag puesto, toda consulta desde
  // Ajustes seria rechazada en produccion — y por la capa de transporte, o sea
  // sin que ningun test del repo lo agarre.
  //
  // La cerradura es que la entrada es el uid del token y nada mas: no hay body,
  // no hay planId, no hay nada que elegir. Lo peor que puede hacer alguien
  // logueado es preguntar por sus propios planes, y para eso esta el cooldown.
  {
    region: "southamerica-east1",
    secrets: [MP_ACCESS_TOKEN],
  },
  async (request): Promise<ReconcileMyCheckoutResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "hay que estar logueado");
    }

    return runReconcileMyCheckout(ensureApp(), request.auth.uid, {
      mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
      nowMs: Date.now(),
    });
  },
);
