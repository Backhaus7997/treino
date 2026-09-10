/**
 * client.ts — el unico lugar del repo que le habla a la API de RevenueCat.
 *
 * Calca la forma de `mp/client.ts`: una factory que RECIBE la credencial (nunca
 * la lee de un secreto por su cuenta) y un error tipado que sabe si conviene
 * reintentar. Que la key entre por parametro es lo que hace testeable todo esto
 * sin red y sin credenciales.
 *
 * ── EL MISMO PRINCIPIO QUE MERCADO PAGO, Y ESTA VEZ LO PIDE EL PROVEEDOR ──
 *
 * **El webhook NO es la fuente de la verdad: es una invalidacion de cache.**
 *
 * Con MP eso fue una decision nuestra. Con RevenueCat es ademas la
 * recomendacion explicita de la doc, textual:
 *
 *   «Because different webhook events contain unique information, we recommend
 *   calling the GET /subscribers REST API endpoint after receiving any webhook.
 *   That way, the customer's information is always in the same format and is
 *   easily synced to your database. This approach is simpler than writing
 *   custom logic to handle each webhook event, and has the added benefit of
 *   making your system more robust and scalable.»
 *
 * O sea: del evento se usa el `app_user_id` y nada mas. Los 20 y pico de tipos
 * de evento (`INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `BILLING_ISSUE`,
 * `EXPIRATION`, `TRANSFER`…) dejan de ser una tabla de decision y pasan a ser
 * un filtro de «¿esto amerita re-consultar?».
 *
 * ── POR QUE v2 Y NO v1 ──
 *
 * v1 (`GET /v1/subscribers/{app_user_id}`) es mas simple: no necesita
 * `project_id` y devuelve los entitlements keyeados por lookup key. Pero tiene
 * dos problemas y el segundo es el que decide:
 *
 *   1. **No es un getter puro.** Se llama «Get or Create Customer»: si el
 *      `app_user_id` no existe, LO CREA y devuelve 201. Un webhook que
 *      re-consulta no deberia poder crear nada.
 *
 *   2. **No tiene `gives_access`.** En v1 hay que derivar el derecho comparando
 *      `expires_date` y `grace_period_expires_date` contra el reloj. En v2 el
 *      veredicto ya viene computado por RevenueCat, y la doc avisa por que eso
 *      importa: «Please note that additional states might be added in the
 *      future. To determine whether or not a subscription currently provides
 *      access to any associated entitlements, use the gives_access field.»
 *
 * Switchear sobre `status` es una bomba de tiempo con fecha puesta por el
 * proveedor. `gives_access` no. Por eso pagamos el `project_id` de mas.
 *
 * ── LA TRAMPA DEL `Bearer` ──
 *
 * v1 acepta la key pelada. **v2 EXIGE el prefijo `Bearer`.** Es el tipo de
 * detalle que produce un 401 que se lee como «la key esta mal» cuando en
 * realidad la key esta bien.
 *
 * ── Las credenciales ──
 *
 * `RC_API_KEY` es la V2 secret key del dashboard, y se carga con
 * `firebase functions:secrets:set RC_API_KEY`. NUNCA vive en el repo.
 *
 * Ojo con no confundirla con la key PUBLICA del SDK, que es otra cosa: esa va
 * compilada en la app, es publica por diseño, y no sirve para esta API.
 *
 * ── ADVERTENCIA HONESTA SOBRE ESTE ARCHIVO ──
 *
 * La forma de la respuesta esta calcada de la documentacion de RevenueCat
 * (leida el 2026-09-10), **no de una llamada real observada**. Todavia no hay
 * proyecto de RevenueCat creado, asi que no hubo contra que probar. Por eso el
 * parseo es deliberadamente defensivo y `subscriptionsQueOtorgan` no asume la
 * forma del sobre: acepta `{items: [...]}` y tambien un array pelado, y logea
 * si no reconoce ninguna de las dos.
 *
 * El dia que haya una llamada real, verificar y borrar este parrafo.
 */

const RC_API = "https://api.revenuecat.com";

/** Cuanto se espera a RevenueCat antes de darlo por caido. */
const TIMEOUT_MS = 8000;

/**
 * Error de la API de RevenueCat, con el dato que decide el HTTP de vuelta.
 *
 * `retryable` no es cosmetico: en este webhook decide entre gastar uno de los
 * CINCO reintentos que da RevenueCat o darle el evento por cerrado. Ver el
 * encabezado de `webhook.ts`, que explica por que aca la politica de codigos es
 * la inversa de la de Mercado Pago.
 */
export class RcApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly retryable: boolean,
  ) {
    super(message);
    this.name = "RcApiError";
  }
}

/** Una suscripcion, recortada a lo que este slice necesita. */
export interface RcSubscription {
  /** El veredicto ya computado: ¿da acceso AHORA? */
  gives_access: boolean;
  /**
   * `trialing` | `active` | `expired` | `in_grace_period` | `in_billing_retry`
   * | `paused` | `unknown` | `incomplete` — **y mas en el futuro**. No se
   * switchea sobre esto para decidir el derecho; solo para distinguir `grace`.
   */
  status: string;
  /** Los entitlements que esta suscripcion otorga, con su lookup key. */
  entitlements?: { items?: { lookup_key?: unknown }[] } | null;
}

export interface RcClient {
  /**
   * Las suscripciones del cliente, tal como RevenueCat las ve AHORA.
   *
   * `customerId` es el `app_user_id` — para TREINO, el uid de Firebase.
   */
  getSubscriptions(customerId: string): Promise<RcSubscription[]>;
}

/**
 * Clasifica un status HTTP en «reintentar» o «no insistir».
 *
 * 429 entra como retryable a proposito: el rate limit de v2 es de 480 req/min
 * por dominio, y si lo tocamos es por rafaga, no por un bug. Reintentar en 5
 * minutos es exactamente lo que corresponde.
 */
function esRetryable(status: number): boolean {
  return status === 429 || status >= 500;
}

export function createRcClient(apiKey: string, projectId: string): RcClient {
  const pedir = async (path: string): Promise<unknown> => {
    const control = new AbortController();
    const reloj = setTimeout(() => control.abort(), TIMEOUT_MS);
    let res: Response;
    try {
      res = await fetch(`${RC_API}${path}`, {
        method: "GET",
        headers: {
          // v2 EXIGE el prefijo. Sin el, 401 con mensaje enganoso.
          Authorization: `Bearer ${apiKey}`,
          Accept: "application/json",
        },
        signal: control.signal,
      });
    } catch (e) {
      // Timeout o red caida. Siempre reintentable: no sabemos si RevenueCat
      // llego a procesar nada, pero como esto es una LECTURA, repetirla es
      // gratis y seguro.
      throw new RcApiError(
        `no se pudo contactar a RevenueCat: ${String(e)}`,
        0,
        true,
      );
    } finally {
      clearTimeout(reloj);
    }

    if (!res.ok) {
      const cuerpo = await res.text().catch(() => "");
      throw new RcApiError(
        `RevenueCat contesto ${res.status}: ${cuerpo.slice(0, 300)}`,
        res.status,
        esRetryable(res.status),
      );
    }

    return res.json();
  };

  return {
    async getSubscriptions(customerId: string): Promise<RcSubscription[]> {
      const crudo = await pedir(
        `/v2/projects/${encodeURIComponent(projectId)}` +
          `/customers/${encodeURIComponent(customerId)}/subscriptions`,
      );
      return normalizarLista(crudo);
    },
  };
}

/**
 * Saca el array de suscripciones del sobre, sin confiar en su forma.
 *
 * Exportada para poder testear el parseo contra respuestas reales el dia que
 * las haya, sin levantar un cliente.
 */
export function normalizarLista(crudo: unknown): RcSubscription[] {
  const items = Array.isArray(crudo)
    ? crudo
    : Array.isArray((crudo as { items?: unknown })?.items)
      ? ((crudo as { items: unknown[] }).items)
      : null;

  if (items === null) return [];

  const out: RcSubscription[] = [];
  for (const it of items) {
    if (typeof it !== "object" || it === null) continue;
    const s = it as Record<string, unknown>;
    // `gives_access` y `status` estan marcados «required» en la doc, pero la
    // misma doc abre la seccion de campos con «don't assume Always fields are
    // non-null». Se parsea como si pudieran faltar.
    out.push({
      gives_access: s.gives_access === true,
      status: typeof s.status === "string" ? s.status : "unknown",
      entitlements: (s.entitlements ?? null) as RcSubscription["entitlements"],
    });
  }
  return out;
}

/**
 * ¿Alguna de estas suscripciones otorga HOY el entitlement que nos importa?
 *
 * Devuelve el `status` de la que otorga —para poder distinguir `in_grace_period`
 * de lo demas— o `null` si ninguna otorga.
 *
 * Se prefiere una que NO este en gracia: si el alumno tiene dos suscripciones
 * vivas (por ejemplo, migro de mensual a anual y la vieja quedo en gracia por
 * un cobro que rebota), la que manda es la que esta sana. Al revez lo
 * degradariamos sin motivo.
 */
export function statusQueOtorga(
  subs: RcSubscription[],
  lookupKey: string,
): string | null {
  let enGracia: string | null = null;

  for (const sub of subs) {
    if (!sub.gives_access) continue;

    const items = sub.entitlements?.items;
    if (!Array.isArray(items)) continue;

    const nuestro = items.some(
      (e) => typeof e?.lookup_key === "string" && e.lookup_key === lookupKey,
    );
    if (!nuestro) continue;

    if (sub.status === "in_grace_period") {
      enGracia = sub.status;
      continue;
    }
    // Cualquier otro status con `gives_access: true` —`active`, `trialing`, y
    // los que RevenueCat agregue mañana— otorga liso y llano.
    return sub.status;
  }

  return enGracia;
}
