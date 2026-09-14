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
 * El valor de `status` que da de BAJA una suscripcion.
 *
 * Es la unica constante de este archivo que hay que justificar con tres fuentes,
 * porque **la documentacion oficial de MP se contradice con su propio SDK** y
 * elegir mal significa un 400 silencioso — o sea el cobro doble que esto viene a
 * cerrar, intacto y sin que nadie se entere.
 *
 * Las tres fuentes, consultadas el 2026-09-08:
 *
 *   1. La guia en prosa dice `canceled`, con UNA ele:
 *      https://www.mercadopago.com.ar/developers/en/docs/subscriptions/subscription-management
 *      «To cancel a subscription, send a PUT with the `status` attribute and the
 *      `canceled` value to the /preapproval/{id} endpoint».
 *
 *   2. El SDK oficial de Node documenta el campo del REQUEST —no el de la
 *      respuesta— con DOS eles:
 *      https://github.com/mercadopago/sdk-nodejs/blob/master/src/clients/preApproval/commonTypes.ts
 *      `PreApprovalRequest.status?: string`, comentado
 *      «Desired subscription status (e.g. `authorized`, `paused`, `cancelled`)».
 *
 *   3. La API REAL, medida contra dos suscripciones de la misma cuenta el
 *      2026-09-07 (los payloads estan en `mp-reconcile.test.ts`): devuelve
 *      `cancelled`, con dos eles. Es el mismo valor que `map-status.ts` sabe
 *      traducir.
 *
 * **Gana `cancelled`**: dos de las tres fuentes son el sistema hablando de si
 * mismo, y la tercera es una guia traducida. Escribir el vocabulario de la
 * lectura tambien vale por si solo — un dominio partido en dos ortografias es
 * como se cuelan los bugs que `effective-limit.ts` documenta haber pagado con un
 * `"canceled"` de una sola ele que se caia por afuera de un switch.
 *
 * Y si igual estuviera mal, el diseño lo absorbe: la baja NO se da por hecha
 * porque el PUT haya salido bien. `reconcile.ts` no marca nada terminal hasta
 * que la llamada resuelve, y el barrido de la noche siguiente vuelve a
 * intentarlo. Un 400 acá se ve en Cloud Logging con el body de MP adentro.
 */
const STATUS_BAJA = "cancelled";

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
  /**
   * El plan contra el que se creo la suscripcion.
   *
   * Es lo que hace posible el webhook: un evento trae un id de SUSCRIPCION, y
   * este campo es el unico puente hasta el plan —que es lo que `mp_plans`
   * keyea y lo que `reconcileSubscription` recibe—. Verificado en la respuesta
   * de ejemplo de `GET /preapproval/{id}` de la referencia oficial.
   */
  preapproval_plan_id?: unknown;
  /** ISO 8601 del proximo cobro programado. */
  next_payment_date?: unknown;
  payer_id?: unknown;
  auto_recurring?: unknown;
  /** Historial de cobros. De acá sale si hay una cuota en reintento. */
  summarized?: unknown;
}

/**
 * Un PLAN de suscripcion. Es a donde se manda al PF, y la razon por la que
 * existe es de producto, no tecnica.
 *
 * ── Por que planes y no `/preapproval` directo ──
 *
 * Crear una suscripcion SIN plan obliga a mandar `payer_email`, y MP ATA el
 * cobro a ese mail: quien paga tiene que estar logueado con el. Eso dejaba sin
 * poder pagar a todo PF cuya cuenta de Mercado Pago use otro mail que su cuenta
 * de TREINO — la mitad de la gente — y el error le aparecia recien adentro del
 * checkout, donde ya no lo puede corregir. Verificado a mano contra la API.
 *
 * El plan NO pide `payer_email`: devuelve su propio `init_point` y **MP le
 * pregunta al pagador quien es**. Cualquier cuenta, cualquier mail.
 *
 * ── Un plan POR CHECKOUT, no seis planes fijos ──
 *
 * El `external_reference` vive en el PLAN, no en cada suscripcion. Con seis
 * planes fijos (3 tiers x 2 ciclos) todos los PF que compren el mismo plan
 * compartirian ese campo y perderiamos a quien acreditarle el cupo.
 *
 * Creando uno por checkout, cada plan lleva el uid de SU comprador.
 */
export interface MpPreapprovalPlan {
  id?: unknown;
  init_point?: unknown;
  external_reference?: unknown;
  status?: unknown;
  auto_recurring?: unknown;
}

export interface CreatePreapprovalPlanInput {
  /** Lo que el PF ve como concepto del cobro en su resumen. */
  reason: string;
  /** Nuestro enganche: el uid de Firebase. */
  externalReference: string;
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
   * Crea un plan y devuelve su `init_point`. Ver [MpPreapprovalPlan] para por
   * que el checkout va por acá y no por `createPreapproval`.
   */
  createPreapprovalPlan(
    input: CreatePreapprovalPlanInput,
  ): Promise<MpPreapprovalPlan>;
  /**
   * Las suscripciones creadas contra un plan. Normalmente 0 (nadie pago
   * todavia) o 1.
   *
   * El reconciliador busca POR PLAN y no por el `external_reference` de la
   * suscripcion, a proposito: no esta verificado que la suscripcion herede ese
   * campo del plan, y el plan lo creamos nosotros con un id que ya guardamos.
   * Buscar por lo que sabemos con certeza en vez de por lo que suponemos.
   */
  searchPreapprovalsByPlan(planId: string): Promise<MpPreapproval[]>;
  /**
   * Da de BAJA una suscripcion. Es lo unico que frena un cobro recurrente.
   *
   * ── Por que este metodo tuvo que existir ──
   *
   * Hasta que aparecio, `MpClient` solo hacia GET y POST: sabia ABRIR cobros y
   * LEERLOS, y no sabia cerrarlos. Como `create-preapproval.ts` no mira si el PF
   * ya tiene una suscripcion viva, un entrenador que pasaba de plan1 a plan2
   * quedaba con DOS suscripciones autorizadas en MP —la vieja nunca se daba de
   * baja— **y MP le cobraba las dos**. No es un caso raro: es exactamente lo que
   * pasa cuando a alguien le va bien y quiere pagarnos mas.
   *
   * ── Es TERMINAL, y por eso quien la llama tiene que estar seguro ──
   *
   * Un preapproval cancelado no se reactiva: para volver atras hay que crear uno
   * NUEVO, con otro id, y el PF tiene que pasar por el checkout de nuevo. Es la
   * misma propiedad que `reconcile.ts` ya usa para sacar del barrido lo que MP
   * dio de baja.
   *
   * Corolario de diseño, y esta escrito en el encabezado de `reconcile.ts`: esto
   * NO se llama al abrir un checkout. Se llama cuando la suscripcion NUEVA ya
   * quedo confirmada por MP. Cancelar antes deja sin plan a quien todavia no
   * compro nada.
   *
   * ── Se cancela la SUSCRIPCION, no el plan ──
   *
   * El `preapproval_plan` no cobra: es una plantilla con un `init_point`. Lo que
   * cobra es el `preapproval` que nace cuando alguien paga contra ese plan, y es
   * lo unico que hay que dar de baja. La doc de MP para gestionar planes
   * (`/docs/subscription-plans/manage-subscription-plan`, consultada el
   * 2026-09-08) solo describe el panel web: **no hay baja de plan por API**, y no
   * hace falta. Un plan viejo que queda vivo no le cuesta un peso a nadie, y del
   * barrido lo saca `terminal` en `mp_plans`.
   */
  cancelPreapproval(preapprovalId: string): Promise<MpPreapproval>;
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
   * El unico lugar que toca la red. Las cuatro operaciones comparten timeout,
   * clasificacion de errores y validacion de la respuesta — tenerlo repetido
   * garantizaba que un dia divergieran.
   */
  async function request(
    path: string,
    method: "GET" | "POST" | "PUT",
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

    async createPreapprovalPlan(
      input: CreatePreapprovalPlanInput,
    ): Promise<MpPreapprovalPlan> {
      // Falla ANTES de salir a la red: un monto en 0 o un externalReference
      // vacio no son errores de MP, son bugs nuestros, y descubrirlos por un
      // 400 los disfraza de problema de ellos.
      if (!input.externalReference) {
        throw new MpApiError("mp/client: externalReference vacio", 0);
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

      // SIN `payer_email`: ese es el punto entero de usar un plan. MP le
      // pregunta al pagador quien es en el checkout.
      return request("/preapproval_plan", "POST", {
        reason: input.reason,
        external_reference: input.externalReference,
        back_url: input.backUrl,
        auto_recurring: {
          frequency: input.frequencyMonths,
          frequency_type: "months",
          transaction_amount: input.transactionAmount,
          currency_id: "ARS",
        },
      });
    },

    async searchPreapprovalsByPlan(planId: string): Promise<MpPreapproval[]> {
      if (!planId) {
        throw new MpApiError("mp/client: planId vacio", 0);
      }
      const res = await request(
        `/preapproval/search?preapproval_plan_id=${encodeURIComponent(planId)}`,
        "GET",
      );
      const results = (res as { results?: unknown }).results;
      // Un `results` que no es array se trata como vacio y NO como error: MP
      // devolviendo algo raro no puede hacer que el barrido se caiga para
      // todos los demas PF.
      return Array.isArray(results) ? (results as MpPreapproval[]) : [];
    },

    async cancelPreapproval(preapprovalId: string): Promise<MpPreapproval> {
      // Falla ANTES de salir a la red, igual que las otras. Y acá pesa mas que
      // en un GET: con el id vacio la ruta queda en `/preapproval/`, que no
      // identifica ninguna suscripcion, y lo que MP hace con un PUT ahi no lo
      // sabemos. Un request cuyo efecto no conocemos no se manda — menos uno
      // cuyo cuerpo dice "dar de baja".
      if (!preapprovalId) {
        throw new MpApiError("mp/client: preapprovalId vacio", 0);
      }
      // `PUT /preapproval/{id}` con `{ status }` es el endpoint de actualizacion
      // de suscripciones; la baja es un caso particular de el. Verificado en la
      // referencia oficial el 2026-09-08:
      // https://www.mercadopago.com.ar/developers/en/reference/online-payments/subscriptions/update-preapproval/put
      //
      // Se manda SOLO `status`: el body de ese endpoint tambien acepta `reason`,
      // `auto_recurring`, `back_url` y los tokens de tarjeta, y mandar cualquiera
      // de esos de mas seria reescribir el cobro de alguien en el mismo request
      // en el que lo damos de baja.
      return request(
        `/preapproval/${encodeURIComponent(preapprovalId)}`,
        "PUT",
        { status: STATUS_BAJA },
      );
    },

  };
}
