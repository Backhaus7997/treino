/**
 * webhook.ts — la notificacion de Mercado Pago. **El primer endpoint HTTP
 * publico del repo.**
 *
 * Todo lo demas de `functions/` es `onCall` (con `request.auth`) o un trigger
 * de Firestore. Esto lo puede POSTear cualquiera en internet, y por eso el
 * archivo se lee entero antes de tocarlo.
 *
 * ── LO QUE HACE QUE ESTO SEA SEGURO NO ES LA FIRMA ──
 *
 * Es el principio que `client.ts` ya declara para toda la integracion:
 *
 *   **El webhook NO es la fuente de la verdad: es una invalidacion de cache.**
 *
 * De un evento entrante se usa UN solo dato —el id del recurso— y todo lo demas
 * se descarta. La verdad se pide con un `GET` usando NUESTRO token. Eso mata
 * tres ataques de un saque, sin depender de la firma:
 *
 *   - **Body forjado.** No leemos el body mas alla del id. Un atacante que
 *     mande `{status: "authorized", tier: "plan3"}` no logra nada: ese payload
 *     no se mira.
 *   - **Replay.** Re-GETear devuelve el estado ACTUAL. Reenviar un evento viejo
 *     de un alta no revive una suscripcion dada de baja.
 *   - **Eventos fuera de orden.** Siempre gana lo que MP diga ahora.
 *
 * Y hay una cuarta defensa que no es de este archivo: `reconcileSubscription`
 * solo escribe si el uid del mapeo coincide con el `external_reference` que
 * devolvio MP. Un id de un preapproval de OTRO vendedor no resuelve a ningun
 * plan nuestro y no escribe nada.
 *
 * Lo que un atacante SI puede hacer es gastarnos llamadas a la API de MP
 * mandando ids al azar. Contra eso estan el chequeo de forma del id, el
 * `maxInstances` y el dedupe — ver mas abajo. No es una amenaza de correctitud,
 * es una de cuota.
 *
 * ── LA FIRMA: HAY CLAVE, Y SE VALIDA ──
 *
 * **Verificado en el panel real el 2026-09-08**: la aplicacion TREINO
 * (`4762356032347434`) SI tiene la seccion Webhooks en «Tus integraciones», y
 * al guardar genera una firma secreta. O sea que en produccion este webhook
 * corre CON validacion de firma.
 *
 * Vale la pena que quede escrito por que el codigo igual tolera no tenerla: la
 * doc de MP **se contradice consigo misma en la misma pagina**. Dice textual,
 * en «Configuracion a traves de Tus integraciones», que *«este metodo de
 * configuracion no esta disponible para integraciones con Codigo QR ni
 * Suscripciones»* —y la clave se genera EXCLUSIVAMENTE ahi— mientras la tabla
 * de eventos de esa misma pagina lista `subscription_preapproval` como
 * configurable por ese panel. El panel le dio la razon a la tabla.
 *
 * El camino sin clave se conserva por dos motivos concretos, no por simetria:
 *
 *   1. **El arranque.** `MP_WEBHOOK_SECRET` tiene que EXISTIR en Secret Manager
 *      para que el deploy funcione (asi son los secretos de v2), y hay una
 *      ventana —entre el primer deploy y guardar la config en MP— donde todavia
 *      no hay clave que poner.
 *   2. **Que la doc siga sin resolverse.** Si manana MP aplica de verdad ese
 *      aviso a las apps de Suscripciones, exigir firma dejaria el webhook sin
 *      poder desplegarse.
 *
 * Sin clave se procesa igual y **se logea un warn en CADA request**: es un modo
 * degradado, y un modo degradado silencioso es el que se queda para siempre.
 * Lo que sostiene la seguridad en los dos casos es el diseño de arriba, no la
 * firma.
 *
 * Para cargarla:
 *
 *   firebase functions:secrets:set MP_WEBHOOK_SECRET --project prod
 *
 * ── EL MANIFEST DE LA FIRMA TIENE UNA TRAMPA ──
 *
 * El `data.id` del manifest sale de los **QUERY PARAMS de la URL**, no del body
 * JSON. Leerlo de `req.body.data.id` produce firmas que no matchean nunca, y el
 * sintoma es «MP manda mal la firma» cuando el error es nuestro. Textual de la
 * doc: *«[data.id_url] se sustituira por el valor del parametro data.id
 * recibido en los query params de la solicitud»*.
 *
 * Las otras tres reglas del manifest, tambien textuales: los ids alfanumericos
 * en mayusculas van en minusculas; los componentes ausentes se REMUEVEN del
 * template; y el HMAC es SHA256 en hexadecimal con el secreto como clave.
 *
 * ── POR QUE CASI TODO CONTESTA 200 ──
 *
 * MP reintenta **cada 15 minutos, indefinidamente**, hasta recibir 200 o 201
 * («despues del tercer intento el plazo sera prorrogado, pero los envios
 * continuaran sucediendo»). Un 500 por un error de NEGOCIO —un plan que no
 * conocemos, un topico que no manejamos— se convierte en un martilleo eterno
 * sobre un evento que nunca vamos a poder procesar.
 *
 * Por eso el 500 se reserva EXCLUSIVAMENTE para lo transitorio: MP no
 * contesto. Ahi el reintento a los 15 minutos es exactamente lo que queremos.
 * Todo lo demas —incluido lo que no entendimos— contesta 200 y se logea.
 *
 * Y si el webhook nunca llega, no pasa nada grave: el barrido de las 03:00
 * cubre lo mismo con mas latencia. Se pierde tiempo, no correccion.
 */

import { createHmac, timingSafeEqual } from "node:crypto";

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";

import { MpApiError, MpClient, createMpClient } from "./client";
import { reconcileSubscription } from "./reconcile";

const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");
const MP_WEBHOOK_SECRET = defineSecret("MP_WEBHOOK_SECRET");

/**
 * Coleccion del dedupe. Un doc por evento visto, id = el id del recurso.
 *
 * MP reintenta el MISMO evento cada 15 minutos hasta que contestemos 200, y
 * ademas manda varios topicos por una sola compra. Sin dedupe, cada reintento
 * es un GET a MP y una pasada de reconciliacion.
 *
 * No es una defensa de correctitud —reconciliar dos veces converge al mismo
 * estado, y el corto-circuito `sinCambios` evita la segunda escritura— sino de
 * cuota: es lo que hace que un POST repetido salga gratis.
 */
export const MP_WEBHOOK_EVENTS_COLLECTION = "mp_webhook_events";

/**
 * Cuanto vale un evento ya procesado.
 *
 * Diez minutos y no 15: tiene que ser MENOR que el intervalo de reintento de
 * MP para que un reintento legitimo —uno donde de verdad no contestamos 200—
 * vuelva a procesarse. Mas largo que su ventana convertiria el dedupe en un
 * agujero: el evento que se perdio no se reintentaria nunca.
 */
export const DEDUPE_MS = 10 * 60 * 1000;

/**
 * Los topicos que este handler ATIENDE.
 *
 * `subscription_preapproval` es la vinculacion suscripcion↔plan: es lo que
 * avisa el alta, la baja y la pausa, o sea todos los cambios de estado de la
 * suscripcion en si. Es el unico que este slice necesita.
 *
 * Los otros dos que MP manda para suscripciones se ACUSAN con 200 y no se
 * procesan, a proposito:
 *
 *   - `payment` / `subscription_authorized_payment` hablan de un COBRO puntual.
 *     Llegar al plan desde ahi cuesta dos hops (`authorized_payments/{id}` trae
 *     `preapproval_id`, no `preapproval_plan_id`) y no hace falta todavia: un
 *     cobro que rebota ya se ve desde el preapproval, porque
 *     `hayCobroPendiente` lee `summarized.pending_charge_quantity` — que es
 *     justo el campo del que `map-status` deriva `grace`.
 *   - `subscription_preapproval_plan` avisa cambios del PLAN, no de la compra.
 *     Un webhook que escuchara solo ese no se enteraria nunca de una venta.
 */
const TOPICO_SUSCRIPCION = "subscription_preapproval";

/**
 * Forma aceptable de un id de recurso de MP.
 *
 * Los ids de preapproval son hex de 32 caracteres (`2c938084726fca48…`), pero
 * no se exige eso: MP cambia formatos y un chequeo demasiado fino rompe el dia
 * que aparezca un id nuevo. Lo que SI se exige es que sea corto y alfanumerico,
 * que es lo unico que hace falta para que un POST hostil no nos mande a hacer
 * un GET con basura arbitraria en la URL.
 */
const ID_VALIDO = /^[A-Za-z0-9_-]{1,64}$/;

export type WebhookOutcome =
  | "reconciliado"
  | "duplicado"
  | "topico-ignorado"
  | "sin-id"
  | "firma-invalida"
  | "sin-plan"
  /** MP no contesto. Es el UNICO que pide reintento. */
  | "error-mp";

export interface WebhookDeps {
  mpClient: MpClient;
  nowMs: number;
  /** El secreto de firma, o `""` si MP no nos dio uno. */
  signingSecret: string;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * Arma el manifest y compara el HMAC.
 *
 * Devuelve `true` cuando NO hay secreto: sin clave no hay nada que validar, y
 * la seguridad la sostiene el hecho de no confiar en el body. Ver el encabezado.
 */
export function firmaValida(input: {
  signingSecret: string;
  xSignature: string | undefined;
  xRequestId: string | undefined;
  /** El `data.id` de los QUERY PARAMS, no el del body. */
  dataIdDeLaUrl: string | undefined;
}): boolean {
  if (!input.signingSecret) return true;
  if (!input.xSignature) return false;

  // `ts=...,v1=...`, en cualquier orden y con espacios posibles.
  let ts = "";
  let v1 = "";
  for (const parte of input.xSignature.split(",")) {
    const i = parte.indexOf("=");
    if (i < 0) continue;
    const clave = parte.slice(0, i).trim();
    const valor = parte.slice(i + 1).trim();
    if (clave === "ts") ts = valor;
    else if (clave === "v1") v1 = valor;
  }
  if (!ts || !v1) return false;

  // ── El template, y la unica ambiguedad que MP no resolvio ──
  //
  // Textual de la doc: `id:[data.id_url];request-id:[x-request-id];ts:[ts];`
  // Los componentes ausentes se REMUEVEN, no se dejan vacios.
  //
  // Sobre el CASE del `data.id`, la doc y la implementacion de referencia de MP
  // **se contradicen**:
  //
  //   - La doc dice: *«Si data.id se devuelve con caracteres alfanumericos en
  //     mayusculas, conviertelo a minusculas antes de usarlo en el manifest»*.
  //   - El SDK oficial de Node (`mercadopago/sdk-nodejs`,
  //     `src/utils/webhook/index.ts`) NO lo baja a minusculas: usa el id tal
  //     cual llega, y tiene un test que lo PINEA — *«case 2 — uppercase dataId
  //     is preserved in HMAC»*.
  //
  // Las dos fuentes son de MP y dicen lo opuesto, asi que se aceptan LAS DOS
  // derivaciones del mismo id recibido. No es laxitud: un atacante que quisiera
  // aprovecharlo necesitaria acertar un HMAC-SHA256 igual, y pasar de una
  // preimagen valida a dos no mueve esa aguja. Lo que si evita es el modo de
  // falla caro — que MP firme con la variante que nosotros no elegimos y
  // rechacemos el 100% de las notificaciones legitimas.
  //
  // Para TREINO es hoy un no-op: los ids de preapproval son hex en minusculas
  // (`2c938084…`), asi que las dos variantes coinciden. Importa el dia que MP
  // mande un id con mayusculas — los ULID de la Orders API son asi.
  const conId = (id: string | undefined): string => {
    const partes: string[] = [];
    if (id) partes.push(`id:${id};`);
    if (input.xRequestId) partes.push(`request-id:${input.xRequestId};`);
    partes.push(`ts:${ts};`);
    return partes.join("");
  };

  const crudo = input.dataIdDeLaUrl;
  const enMinusculas = crudo?.toLowerCase();
  const candidatos = [conId(crudo)];
  if (enMinusculas !== undefined && enMinusculas !== crudo) {
    candidatos.push(conId(enMinusculas));
  }

  return candidatos.some((manifest) => {
    const esperado = createHmac("sha256", input.signingSecret)
      .update(manifest)
      .digest("hex");

    // Comparacion de tiempo constante. Un `===` sobre un HMAC filtra, por el
    // tiempo de la comparacion, cuantos caracteres del prefijo acerto quien
    // prueba — que es como se falsifica una firma a fuerza de intentos.
    const a = Buffer.from(esperado, "utf8");
    const b = Buffer.from(v1, "utf8");
    // `timingSafeEqual` TIRA si los largos difieren, asi que el largo se
    // compara antes. No filtra nada util: el largo de un SHA256 en hex es
    // publico.
    return a.length === b.length && timingSafeEqual(a, b);
  });
}

/**
 * El id del recurso. Sale del body, y si no esta, de la query.
 *
 * MP manda el envelope `{type, action, data: {id}}` en el body y ademas repite
 * `data.id` en la query string. Se aceptan los dos porque la doc no publica
 * ejemplo de body para los topicos `subscription_*` — solo el generico de
 * `payment`— y quedarse con una sola fuente seria apostar a una forma que MP
 * no documento.
 *
 * OJO: esto es para PROCESAR. El manifest de la firma usa especificamente el de
 * la QUERY, y esa distincion no se puede colapsar.
 */
export function idDelEvento(body: unknown, query: unknown): string | null {
  const b = (body ?? {}) as { data?: { id?: unknown }; id?: unknown };
  const q = (query ?? {}) as Record<string, unknown>;

  const candidatos = [b.data?.id, q["data.id"], q.id, b.id];
  for (const c of candidatos) {
    if (typeof c === "string" && ID_VALIDO.test(c)) return c;
    // MP manda el id del ENVELOPE como number en su ejemplo. El del recurso
    // viaja como string, pero aceptar el number cuesta una linea y evita
    // descartar un evento por el tipo.
    if (typeof c === "number" && Number.isSafeInteger(c) && c > 0) {
      return String(c);
    }
  }
  return null;
}

/** El topico, que MP manda como `type` en el body o `topic` en la query. */
export function topicoDelEvento(body: unknown, query: unknown): string {
  const b = (body ?? {}) as { type?: unknown };
  const q = (query ?? {}) as { topic?: unknown; type?: unknown };
  for (const c of [b.type, q.topic, q.type]) {
    if (typeof c === "string" && c !== "") return c;
  }
  return "";
}

export interface WebhookRequestLike {
  body: unknown;
  query: unknown;
  header(nombre: string): string | undefined;
}

/**
 * El handler puro. Devuelve el outcome; quien lo envuelve decide el HTTP.
 *
 * Separado del `onRequest` por el mismo motivo que los `run*` de los callables
 * (ADR-CXP-004): asi se testea sin levantar un servidor y sin red.
 */
export async function runMpWebhook(
  app: App,
  req: WebhookRequestLike,
  deps: WebhookDeps,
): Promise<WebhookOutcome> {
  const query = (req.query ?? {}) as Record<string, unknown>;
  const dataIdDeLaUrl = typeof query["data.id"] === "string"
    ? (query["data.id"] as string)
    : typeof query.id === "string"
      ? (query.id as string)
      : undefined;

  if (!deps.signingSecret) {
    // En CADA request, a proposito. Correr sin validar firma es un modo
    // degradado, y el que no se ve es el que se queda para siempre.
    logger.warn(
      "mp/webhook: SIN clave de firma — se procesa sin validar el origen. " +
        "Cargala con `firebase functions:secrets:set MP_WEBHOOK_SECRET`.",
    );
  }

  if (
    !firmaValida({
      signingSecret: deps.signingSecret,
      xSignature: req.header("x-signature"),
      xRequestId: req.header("x-request-id"),
      dataIdDeLaUrl,
    })
  ) {
    // Se logea QUE componentes habia, nunca sus VALORES: el body y los headers
    // los manda cualquiera de internet y no van a Cloud Logging.
    //
    // Estos tres booleanos son lo unico que hace falta para diagnosticar el
    // modo de falla mas probable del primer dia — que el manifest se arme con
    // un componente de mas o de menos— sin exponer nada. Si TODOS vienen en
    // true y aun asi rechaza, el problema es el secreto o el algoritmo; si
    // alguno viene en false, es el manifest.
    logger.warn("mp/webhook: firma invalida — se descarta", {
      teniaSignature: req.header("x-signature") !== undefined,
      teniaRequestId: req.header("x-request-id") !== undefined,
      teniaDataIdEnLaUrl: dataIdDeLaUrl !== undefined,
    });
    return "firma-invalida";
  }

  const topico = topicoDelEvento(req.body, req.query);
  if (topico !== TOPICO_SUSCRIPCION) {
    // 200 igual: ver el encabezado. Un topico que no atendemos no mejora
    // porque MP lo reintente cada 15 minutos para siempre.
    logger.info("mp/webhook: topico que no atendemos", { topico });
    return "topico-ignorado";
  }

  const preapprovalId = idDelEvento(req.body, req.query);
  if (!preapprovalId) {
    logger.warn("mp/webhook: evento sin id de recurso utilizable", { topico });
    return "sin-id";
  }

  // ── Dedupe, ANTES de salir a MP ──
  const db = getFirestore(app);
  const visto = db.collection(MP_WEBHOOK_EVENTS_COLLECTION).doc(preapprovalId);
  const previo = (await visto.get()).data();
  const cuando = previo?.procesadoMs;
  if (typeof cuando === "number" && deps.nowMs - cuando < DEDUPE_MS) {
    return "duplicado";
  }

  // ── La UNICA fuente de la verdad: preguntarle a MP con nuestro token ──
  let preapproval;
  try {
    preapproval = await deps.mpClient.getPreapproval(preapprovalId);
  } catch (e) {
    const err = e as MpApiError;
    logger.error("mp/webhook: no se pudo leer el preapproval", {
      preapprovalId,
      status: err.status,
      retryable: err.retryable,
    });
    // El unico camino que pide reintento. NO se marca como procesado: el
    // reintento de MP a los 15 minutos es exactamente lo que hace falta.
    return "error-mp";
  }

  const planId = (preapproval as { preapproval_plan_id?: unknown })
    .preapproval_plan_id;
  if (typeof planId !== "string" || planId === "") {
    // Una suscripcion sin plan asociado no es nuestra: TREINO crea SIEMPRE un
    // plan por checkout. Se acusa 200 — reintentar no le va a poner un plan.
    logger.info("mp/webhook: preapproval sin plan asociado — no es nuestro", {
      preapprovalId,
    });
    await visto.set({ procesadoMs: deps.nowMs, outcome: "sin-plan" });
    return "sin-plan";
  }

  // De acá para abajo es el MISMO camino que el barrido de las 03:00. Toda la
  // politica de cuando escribir y cuando no vive ahi, en un solo lugar.
  const r = await reconcileSubscription(app, planId, deps);

  await visto.set({ procesadoMs: deps.nowMs, outcome: r.outcome, planId });

  logger.info("mp/webhook: evento procesado", {
    preapprovalId,
    planId,
    outcome: r.outcome,
  });
  return "reconciliado";
}

export const mpWebhook = onRequest(
  {
    region: "southamerica-east1",
    secrets: [MP_ACCESS_TOKEN, MP_WEBHOOK_SECRET],
    // El PRIMER endpoint publico del repo, y la unica function con un tope de
    // instancias. No es simetria lo que falta en las demas: ninguna otra puede
    // ser invocada por alguien sin cuenta. Sin tope, un POST en loop escala
    // Cloud Run y nos quema la cuota de la API de MP, que es la que necesita el
    // barrido nocturno para acreditarle el plan a todo el mundo.
    maxInstances: 3,
    // MP corta a los 22 segundos. Pasado eso da la notificacion por perdida y
    // reintenta, asi que seguir trabajando 60 segundos no sirve para nada.
    timeoutSeconds: 20,
    // No hay dato de usuario en el body y el CORS no protege a un servidor.
    cors: false,
  },
  async (req, res) => {
    // Solo POST. MP notifica por POST; un GET a esta URL es alguien mirando.
    if (req.method !== "POST") {
      res.status(405).send("solo POST");
      return;
    }

    let outcome: WebhookOutcome;
    try {
      outcome = await runMpWebhook(
        ensureApp(),
        {
          body: req.body,
          query: req.query,
          header: (n: string) => req.get(n) ?? undefined,
        },
        {
          mpClient: createMpClient(MP_ACCESS_TOKEN.value()),
          nowMs: Date.now(),
          signingSecret: MP_WEBHOOK_SECRET.value(),
        },
      );
    } catch (err) {
      // Un bug nuestro no puede convertirse en un martilleo eterno: se logea y
      // se acusa. El barrido de las 03:00 cubre lo que se haya perdido.
      logger.error("mp/webhook: error inesperado", { err });
      res.status(200).send("ok");
      return;
    }

    if (outcome === "firma-invalida") {
      res.status(401).send("firma invalida");
      return;
    }
    if (outcome === "error-mp") {
      // El UNICO 5xx. Le pide a MP que reintente en 15 minutos, que es
      // exactamente lo que hace falta cuando el que fallo fue MP.
      res.status(503).send("no se pudo consultar a Mercado Pago");
      return;
    }
    res.status(200).send("ok");
  },
);
