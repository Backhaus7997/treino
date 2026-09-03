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
  /** Nuestro enganche al uid de Firebase. Lo mandamos nosotros al crear. */
  external_reference?: unknown;
  /** ISO 8601 del proximo cobro programado. */
  next_payment_date?: unknown;
  payer_id?: unknown;
  auto_recurring?: unknown;
  /** Historial de cobros. De acá sale si hay una cuota en reintento. */
  summarized?: unknown;
}

export interface MpClient {
  /** Lee una suscripcion. Es la FUENTE DE LA VERDAD de todo el sistema. */
  getPreapproval(preapprovalId: string): Promise<MpPreapproval>;
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

  return {
    async getPreapproval(preapprovalId: string): Promise<MpPreapproval> {
      if (!preapprovalId) {
        throw new MpApiError("mp/client: preapprovalId vacio", 0);
      }

      let response: Response;
      try {
        response = await fetchImpl(
          `${MP_API}/preapproval/${encodeURIComponent(preapprovalId)}`,
          {
            method: "GET",
            headers: {
              Authorization: `Bearer ${accessToken}`,
              "Content-Type": "application/json",
            },
            signal: AbortSignal.timeout(TIMEOUT_MS),
          },
        );
      } catch (e) {
        // Nunca llegamos a MP: red, DNS o timeout. Siempre vale reintentar, y
        // por eso va con status 0.
        throw new MpApiError(
          `mp/client: la llamada no completo — ${(e as Error).message}`,
          0,
        );
      }

      if (!response.ok) {
        const body = await response.text().catch(() => "");
        throw new MpApiError(
          `mp/client: HTTP ${response.status} al leer preapproval`,
          response.status,
          // El body puede traer detalle util de MP, pero tambien puede ser
          // enorme. Se recorta: esto va a Cloud Logging.
          body.slice(0, 500),
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
    },
  };
}
