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
 * ── NO se le pregunta el mail a nadie, y esa es la historia de este archivo ──
 *
 * La primera version creaba la suscripcion con `POST /preapproval`, que EXIGE
 * `payer_email`. Y MP ATA el cobro a ese mail: quien paga tiene que estar
 * logueado con el. O sea que un PF que se registra en TREINO con
 * `juan@gmail.com` pero cuya cuenta de Mercado Pago es `jperez@hotmail.com`
 * **no podia pagar nunca**, y el error le aparecia recien adentro del checkout
 * —"Tu e-mail no coincide con el de la suscripcion"— donde ya no lo puede
 * corregir. No es un caso raro: es la mitad de la gente.
 *
 * Se intento preguntarselo en un dialogo antes de comprar y era peor: friccion
 * en el camino de pago para el 90% que tiene los dos mails iguales, por un
 * detalle de la pasarela que no deberia ver nunca.
 *
 * Ahora el checkout va contra un PLAN (`POST /preapproval_plan`), que NO pide
 * `payer_email`: devuelve su propio `init_point` y MP le pregunta al pagador
 * quien es. Cualquier cuenta, cualquier mail. Verificado a mano contra la API.
 *
 * Se crea un plan POR CHECKOUT y no seis fijos, porque el `external_reference`
 * vive en el plan: con planes compartidos perderiamos a quien acreditarle el
 * cupo. Ver el encabezado de `client.ts`.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

import { SubscriptionCycle, SubscriptionTier } from "../tier-config";
import {
  CYCLES,
  PAID_TIERS,
  amountFor,
  frequencyMonthsFor,
} from "./tier-mapping";
import { MpClient, createMpClient } from "./client";
import { CheckoutAbierto, abrirCheckout } from "./abrir-checkout";
import { trainerWebCheckout } from "../../mail/templates";

export { MP_CHECKOUTS_COLLECTION } from "./abrir-checkout";

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");

/**
 * A donde vuelve el navegador al salir del checkout. CONSTANTE del servidor, a
 * proposito: si viniera del cliente seria un open redirect firmado por nosotros
 * — MP mandaria al PF a donde diga el atacante, saliendo de una URL nuestra.
 *
 * ── Por que NO es `https://app.gettreino.com/ajustes` ──
 *
 * Porque esa URL no lleva a Facturacion. **El Coach Hub web usa HASH routing**:
 * no hay una sola llamada a `usePathUrlStrategy` en el repo, asi que Flutter cae
 * al `HashUrlStrategy` por default y el PATH se ignora entero. Verificado contra
 * produccion el 2026-09-08: pedir `/ajustes` termina en
 * `https://app.gettreino.com/ajustes#/login`, con el path intacto en la barra y
 * la app resolviendo por el fragmento. Con el hash vacio, go_router arranca en
 * su `initialLocation: '/dashboard'` (`coach_hub_router.dart`).
 *
 * O sea: durante toda la vida de esta constante, el PF que pagaba volvia al
 * DASHBOARD. El `/ajustes` era decorativo.
 *
 * ── Por que la raiz con `?to=facturacion` SI funciona ──
 *
 * Es la misma URL que los mails de plata al PF (`trainerWebCheckout` en
 * `mail/templates.ts`), y anda por dos piezas que ya existen y estan probadas:
 *
 *   1. `buildCoachHubRouter` lee `Uri.base.queryParameters` —o sea
 *      `location.search`, que el hash no toca— una vez al construir el router.
 *   2. `DeepLinkDestination.fromQuery` ya entiende `to=facturacion`, y
 *      `coachHubRedirect` lo aplica al aterrizar en la landing.
 *
 * MP le agrega SUS parametros (`collection_status`, etc.) a este mismo query
 * string, sin pisar el nuestro.
 *
 * ── Por que NO es `/abrir/profe?to=facturacion` ──
 *
 * En la computadora daria lo mismo: `vercel.json` redirige `/abrir/profe` a
 * esta misma URL conservando el query. Pero `/abrir/*` es un App Link, y en un
 * telefono con la app instalada volver de MP por ahi puede abrir la app en vez
 * de devolver al PF a la pestaña del Coach Hub donde estaba pagando — que es
 * donde corre la acreditacion al volver (`acreditacion_al_volver.dart`).
 *
 * La leccion general, que vale para cualquier link que entre desde afuera —
 * mail, pasarela, QR—: al Coach Hub se entra por la RAIZ con `?to=...`, NUNCA
 * por un path directo. Y lo que es plata, tampoco por `/abrir/profe`.
 */
const BACK_URL = trainerWebCheckout();

export interface CreatePreapprovalRequest {
  tier: SubscriptionTier;
  cycle: SubscriptionCycle;
}

/**
 * Alias de [CheckoutAbierto], no una copia.
 *
 * El nombre se conserva porque es el que nombra el contrato de este callable
 * —lo que el cliente espera de `createPreapproval`— pero la forma la define el
 * modulo compartido. Dos interfaces con los mismos tres campos serian dos cosas
 * que hay que acordarse de mover juntas.
 */
export type CreatePreapprovalResult = CheckoutAbierto;

export interface CreatePreapprovalDeps {
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
 *
 * Recibe el `uid` YA extraido del token y no el `request` entero, para
 * que sea imposible leer del body algo que tiene que salir del token.
 */
export async function runCreatePreapproval(
  app: App,
  uid: string,
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
  const userSnap = await getFirestore(app).collection("users").doc(uid).get();
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

  // Todo lo que sigue —la ventana anti-doble-click, el mapeo de error de MP a
  // `HttpsError`, la validacion de lo que MP devuelve y el orden de las dos
  // escrituras— vive en `abrir-checkout.ts`, compartido con el checkout del
  // alumno. Lo que se queda aca es lo que hace distinto a este producto: el
  // gate de rol, el precio, y a donde vuelve el navegador.
  return abrirCheckout({
    app,
    uid,
    // ⚠️ La huella es EXACTAMENTE `{tier, cycle}` y no puede ganar campos: los
    // documentos de `mp_checkouts` que hay en produccion tienen esos dos y
    // ninguno mas. Ver el dartdoc de `AbrirCheckoutInput.huella`.
    huella: { tier, cycle },
    reason: `TREINO — ${tier} (${cycle === "annual" ? "anual" : "mensual"})`,
    backUrl: BACK_URL,
    amount,
    frequencyMonths: frequencyMonthsFor(cycle),
    mapping: { producto: "trainer", uid, tier, cycle },
    mpClient: deps.mpClient,
    nowMs: deps.nowMs,
  });
}


export const createPreapproval = functions.onCall(
  // SIN enforceAppCheck, por el mismo motivo que `acceptTrainerLink`: el Coach
  // Hub web no activa App Check, y este callable se llama EXACTAMENTE desde
  // ahi. Con el flag puesto, todo checkout desde la web seria rechazado.
  //
  // La cerradura es otra: `request.auth`, el rol leido del documento, y el
  // hecho de que ni el MONTO ni la URL de retorno vengan del cliente. El mail
  // del pagador SI puede venir —ver el encabezado—; lo que no puede elegir es
  // cuanto paga ni a quien se le acredita el plan.
  {
    region: "southamerica-east1",
    secrets: [MP_ACCESS_TOKEN],
  },
  async (request): Promise<CreatePreapprovalResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "hay que estar logueado");
    }
    // Ya NO se lee el mail del token: el plan no lo pide y MP le pregunta al
    // pagador quien es. Un PF sin mail en su token puede comprar igual.

    return runCreatePreapproval(
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
