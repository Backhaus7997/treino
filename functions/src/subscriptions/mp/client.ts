/**
 * client.ts — el unico lugar del repo que le habla a la API de Mercado Pago.
 *
 * Calca la forma de `mail/resend-client.ts`: una factory que RECIBE el token
 * (nunca lo lee de un secreto por su cuenta) y un error tipado que sabe si
 * conviene reintentar. Que el token entre por parametro es lo que hace
 * testeable todo esto sin red y sin credenciales.
 *
 * ── Por que existe una capa propia y no se usa el SDK a secas ──
 *
 * El SDK oficial de Node es bueno y probablemente lo usemos para crear
 * suscripciones. Pero la LECTURA —que es de lo que depende el estado de
 * `subscription` en Firestore— necesita tres cosas que acá quedan explicitas:
 * timeout, clasificacion de errores, y una superficie chica y mockeable.
 *
 * ── EL PRINCIPIO QUE GOBIERNA TODA LA INTEGRACION ──
 *
 * **El webhook NO es la fuente de la verdad: es una invalidacion de cache.**
 *
 * De un evento entrante se usa UN solo dato —el id del recurso— y todo lo
 * demas se descarta. La verdad se pide siempre con `GET` usando NUESTRO token.
 * Eso mata de un saque tres ataques que de otra forma habria que defender uno
 * por uno: un body forjado (no leemos el body), un replay para estirar el
 * periodo (re-GETear da el estado ACTUAL), y eventos fuera de orden (siempre
 * gana lo que MP diga ahora).
 *
 * Corolario operativo: el reconciliador por polling y el webhook llaman a la
 * MISMA funcion. Si el webhook nunca llega, el producto sigue andando — se
 * pierde latencia, no correccion. Por eso el reconciliador se construye
 * ANTES.
 *
 * ── El token ──
 *
 * Se carga con `firebase functions:secrets:set MP_ACCESS_TOKEN` y NUNCA vive
 * en el repo. Arrancar siempre con credenciales de PRUEBA: MP da tarjetas de
 * test para ejercitar el flujo sin cobrarle a nadie.
 */

const MP_API = "https://api.mercadopago.com";

/**
 * Corto a proposito. Esto corre adentro de una Cloud Function, y una llamada
 * colgada consume el timeout de la funcion entera. Si MP no contesta en 10s,
 * el reconciliador lo va a reintentar en su proxima corrida — que es
 * exactamente para lo que existe.
 */
const TIMEOUT_MS = 10_000;

export class MpApiError extends Error {
  constructor(
    message: string,
    /** HTTP status, o 0 cuando el request nunca llego a completarse. */
    readonly status: number,
    readonly body?: string,
  ) {
    super(message);
    this.name = "MpApiError";
  }

  /**
   * Si conviene reintentar.
   *
   * Un 401 o un 404 NO son reintentables y la distincion importa: reintentar
   * un token vencido es ruido, y reintentar un preapproval que no existe es
   * ruido para siempre. Un 429 o un 5xx si — ahi el problema es de MP y se
   * arregla solo.
   */
  get retryable(): boolean {
    return this.status === 0 || this.status === 429 || this.status >= 500;
  }
}

/**
 * La forma del preapproval que NOS IMPORTA. Deliberadamente parcial: MP
 * devuelve muchos mas campos y no queremos depender de ellos.
 *
 * Todo es opcional y de tipo laxo a proposito. Esto es lo que dijo un tercero
 * por la red, no un tipo: quien lo consuma tiene que validar. Declararlo
 * `status: MpPreapprovalStatus` seria mentir sobre una garantia que no
 * tenemos, y es justo el error que `subscription-state.ts` documenta haber
 * pagado con un cast a ciegas.
 */
export interface MpPreapproval {
  id?: unknown;
  status?: unknown;
  /**
   * La URL del checkout. Solo viene al CREAR — un GET de un preapproval ya
   * autorizado no la trae, y por eso hay que guardarla cuando aparece.
   */
  init_point?: unknown;
  /** Nuestro enganche al uid de Firebase. Lo mandamos nosotros al crear. */
  external_reference?: unknown;
  /** ISO 8601 del proximo cobro programado. */
  next_payment_date?: unknown;
  payer_id?: unknown;
  auto_recurring?: unknown;
  /** Historial de cobros. De acá sale si hay una cuota en reintento. */
  summarized?: unknown;
}

/**
 * Lo que hay que decirle a MP para abrir una suscripcion.
 *
 * NO lleva `preapproval_plan_id`. Se crea la suscripcion con el monto EXPLICITO
 * y no contra un plan preconfigurado en el panel de MP, por una razon que
 * condiciona todo lo que viene: **MP no devuelve `preapproval_plan_id` en la
 * respuesta**, solo lo acepta en el request. Atarse a planes del panel nos
 * dejaria sin poder preguntar de que plan es una suscripcion — y encima con la
 * tabla de precios viviendo en dos lugares, el panel y `tier-config.ts`.
 *
 * Con monto explicito la tabla queda en UN lugar, el servidor, y el tier se
 * recupera del monto (ver `tier-mapping.ts`).
 */
export interface CreatePreapprovalInput {
  /** Lo que el PF ve como concepto del cobro en su resumen. */
  reason: string;
  /** Nuestro enganche: el uid de Firebase. Vuelve en cada GET. */
  externalReference: string;
  /** MP lo exige. Es el mail con el que el PF paga, no necesariamente el suyo. */
  payerEmail: string;
  /** A donde vuelve el navegador despues del checkout. */
  backUrl: string;
  transactionAmount: number;
  /** Cada cuantos MESES se cobra. 1 = mensual, 12 = anual. */
  frequencyMonths: number;
}

export interface MpClient {
  /** Lee una suscripcion. Es la FUENTE DE LA VERDAD de todo el sistema. */
  getPreapproval(preapprovalId: string): Promise<MpPreapproval>;
  /**
   * Abre una suscripcion. Devuelve el preapproval con `id` e `init_point` —
   * la URL a la que hay que mandar al PF para que autorice el pago.
   *
   * NO deja la suscripcion activa: la deja en `pending` hasta que el PF pone
   * su medio de pago. Por eso quien llame a esto NO puede escribir
   * `subscription` — eso lo hace el reconciliador cuando MP diga `authorized`.
   */
  createPreapproval(input: CreatePreapprovalInput): Promise<MpPreapproval>;
}

/**
 * Arma el cliente. `fetchImpl` existe para los tests: sin eso, probar el
 * manejo de un 500 o de un timeout exigiria red de verdad.
 */
export function createMpClient(
  accessToken: string,
  fetchImpl: typeof fetch = fetch,
): MpClient {
  if (!accessToken) {
    // Falla acá y no en la primera llamada: un token vacio en produccion es un
    // secreto mal cargado, y el sintoma util es "no arranca", no "todo devuelve
    // 401 y nadie sabe por que".
    throw new Error("mp/client: MP_ACCESS_TOKEN vacio o ausente");
  }

  /**
   * El unico lugar que toca la red. Las dos operaciones comparten timeout,
   * clasificacion de errores y validacion de la respuesta — tenerlo dos veces
   * garantizaba que un dia divergieran.
   */
  async function request(
    path: string,
    method: "GET" | "POST",
    body?: unknown,
  ): Promise<MpPreapproval> {
    let response: Response;
    try {
      response = await fetchImpl(`${MP_API}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (e) {
      // Nunca llegamos a MP: red, DNS o timeout. Siempre vale reintentar, y
      // por eso va con status 0.
      throw new MpApiError(
        `mp/client: la llamada no completo — ${(e as Error).message}`,
        0,
      );
    }

    if (!response.ok) {
      const bodyText = await response.text().catch(() => "");
      throw new MpApiError(
        `mp/client: HTTP ${response.status} en ${method} ${path}`,
        response.status,
        // El body puede traer detalle util de MP, pero tambien puede ser
        // enorme. Se recorta: esto va a Cloud Logging.
        bodyText.slice(0, 500),
      );
    }

    const json: unknown = await response.json().catch(() => null);
    if (json === null || typeof json !== "object") {
      throw new MpApiError(
        "mp/client: la respuesta no es un objeto JSON",
        response.status,
      );
    }

    return json as MpPreapproval;
  }

  return {
    async getPreapproval(preapprovalId: string): Promise<MpPreapproval> {
      if (!preapprovalId) {
        throw new MpApiError("mp/client: preapprovalId vacio", 0);
      }
      return request(
        `/preapproval/${encodeURIComponent(preapprovalId)}`,
        "GET",
      );
    },

    async createPreapproval(
      input: CreatePreapprovalInput,
    ): Promise<MpPreapproval> {
      // Chequeos que fallan ANTES de salir a la red. Un monto en 0 o un
      // externalReference vacio no son errores de MP: son bugs nuestros, y
      // descubrirlos por un 400 los disfraza de problema de ellos.
      if (!input.externalReference) {
        throw new MpApiError("mp/client: externalReference vacio", 0);
      }
      if (!input.payerEmail) {
        throw new MpApiError("mp/client: payerEmail vacio", 0);
      }
      if (!Number.isFinite(input.transactionAmount) ||
          input.transactionAmount <= 0) {
        throw new MpApiError(
          `mp/client: transactionAmount invalido (${input.transactionAmount})`,
          0,
        );
      }
      if (!Number.isInteger(input.frequencyMonths) ||
          input.frequencyMonths <= 0) {
        throw new MpApiError(
          `mp/client: frequencyMonths invalido (${input.frequencyMonths})`,
          0,
        );
      }

      return request("/preapproval", "POST", {
        reason: input.reason,
        external_reference: input.externalReference,
        payer_email: input.payerEmail,
        back_url: input.backUrl,
        // `pending` y no `authorized`: la suscripcion nace SIN medio de pago.
        // El PF lo carga en el `init_point` y recien ahi MP la mueve.
        status: "pending",
        auto_recurring: {
          frequency: input.frequencyMonths,
          // "months" y no "years" para el anual: `months` esta documentado en
          // los tipos del SDK y `years` no aparece. 12 meses es lo mismo y no
          // depende de un valor que no pudimos verificar.
          frequency_type: "months",
          transaction_amount: input.transactionAmount,
          currency_id: "ARS",
        },
      });
    },
  };
}
