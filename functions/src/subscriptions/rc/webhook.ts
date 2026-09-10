/**
 * webhook.ts — la notificacion de RevenueCat. El SEGUNDO endpoint HTTP publico
 * del repo, y el que le acredita la suscripcion al ALUMNO.
 *
 * Se parece mucho a `mp/webhook.ts` y por eso conviene leer primero en que NO
 * se parece. Copiar aquel archivo tal cual seria el error caro de este slice.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  LA DIFERENCIA QUE MANDA: LA POLITICA DE CODIGOS ESTA AL REVES
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Mercado Pago reintenta el mismo evento **cada 15 minutos, indefinidamente**.
 * Todo el razonamiento de `mp/webhook.ts` sale de ahi: «casi todo contesta 200
 * porque un 5xx por error de negocio es un martilleo eterno».
 *
 * RevenueCat hace lo contrario. Textual:
 *
 *   «Your server should return a 200 status code. Any other status code will be
 *   considered a failure by our backend. RevenueCat will retry later (up to 5
 *   times) with an increasing delay (5, 10, 20, 40, and 80 minutes). After 5
 *   retries, we will stop sending notifications.»
 *
 * 5 + 10 + 20 + 40 + 80 = **155 minutos**. Dos horas y media, y despues el
 * evento se pierde para siempre.
 *
 * O sea que el riesgo se invierte. Alla el peligro era el martilleo; aca es la
 * **perdida silenciosa**. Y el corolario es incomodo pero directo:
 *
 *   **un fallo transitorio SI conviene devolverlo como 5xx**, porque los cinco
 *   reintentos no son una plaga, son un recurso escaso y valioso.
 *
 * Lo que sigue valiendo igual, y es la regla que hace que el reintento sirva de
 * algo: **el fallo transitorio NO marca el evento como procesado**. Si se marca,
 * el reintento entra por el dedupe y se descarta sin hacer nada.
 *
 * ── LA OTRA CARA: NO GASTAR REINTENTOS AL PEDO ──
 *
 * Un evento que no nos incumbe —un alumno que no existe, un entitlement que no
 * es el nuestro, un tipo de evento que no miramos— se contesta **200**.
 * Reintentarlo cinco veces no lo va a volver relevante, y cada reintento gastado
 * es uno que no va a estar el dia que falle Firestore de verdad.
 *
 * ── Y LA FIRMA INVALIDA CONTESTA 401, A SABIENDAS ──
 *
 * Un 401 quema uno de los cinco. Se acepta igual, porque las dos unicas causas
 * posibles son un atacante (reintentar no importa) o nuestro secreto mal
 * cargado (reintentar con el mismo secreto malo falla identico). En ninguno de
 * los dos casos el reintento salva nada, asi que es mas honesto decir la
 * verdad que fingir un 200.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  LA FIRMA: ACA SI ESTA DOCUMENTADA
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Con MP hubo que escribir `varianteDeFirma()` —160 combinaciones probadas a
 * mano— porque la doc no alcanzaba para reproducir el manifest. Aca no hace
 * falta nada de eso: RevenueCat lo dice sin ambiguedad.
 *
 *   X-RevenueCat-Webhook-Signature: t=<unix_timestamp>,v1=<hmac_sha256_hex>
 *
 * y el HMAC va sobre la cadena `"<t>.<body crudo>"`.
 *
 * **EL BODY CRUDO ES CRUDO EN SERIO.** La doc advierte explicitamente la trampa
 * que a nosotros nos costo dos dias del otro lado:
 *
 *   «Compute the HMAC over the raw request body bytes, exactly as received —
 *   before any JSON parsing. Re-serializing a parsed object (JSON.parse →
 *   JSON.stringify, or a framework that reparses the body) changes the bytes
 *   and will cause verification to fail on valid requests.»
 *
 * Por eso `runRcWebhook` recibe `rawBody: Buffer` y NUNCA `JSON.stringify` de
 * nada. `firebase-functions` lo expone en su `Request`
 * (`common/providers/https.d.ts`: `rawBody: Buffer`).
 *
 * ── La tolerancia del `t`, y por que NO se dimensiona para los reintentos ──
 *
 * `t` es el momento en que RevenueCat FIRMO ese POST, no el `event_timestamp_ms`
 * del payload, y se **recalcula en cada reintento**. La doc lo dice y ademas
 * avisa del error de calculo que uno hace solo:
 *
 *   «A 5-minute tolerance only needs to cover clock skew and the latency of
 *   that POST. Don't size it to cover the retry delays of 5, 10, 20, 40, and
 *   80 minutes.»
 *
 * De ahi los 5 minutos de abajo. Estirarlo a 80 no protegeria un reintento
 * —que llega con `t` fresco— y si abriria una ventana de replay de hora y media.
 *
 * ── Rotar el secreto es un CORTE ──
 *
 * «The old secret is immediately invalidated»: no hay ventana de dos secretos
 * validos. Y se muestra una sola vez, al crearlo o al rotarlo. Rotar en caliente
 * pierde los eventos que esten en vuelo.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  QUE SE ESCRIBE, Y POR QUE TAN POCO
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Solo `users/{uid}.athleteSubscription = { status }`. Un campo. Nada mas.
 *
 * No es minimalismo estetico: es que `athletePaywallInputChanged`
 * (`athlete-paywall-enforced.ts:116-125`) compara **el mapa entero
 * serializado**, no `.status`:
 *
 *     JSON.stringify(before.athleteSubscription ?? null)
 *       !== JSON.stringify(after.athleteSubscription ?? null)
 *
 * Cualquier campo volatil adentro del mapa —un `updatedAt`, un `lastEventId`,
 * un `expiresAt`— hace correr el trigger `syncAthletePaywallOnUser` en CADA
 * evento de RevenueCat aunque el derecho no se haya movido. Y con el paywall
 * prendido eso no es gratis: para todo alumno cuyo status no otorgue,
 * `resolveAthletePaywallEnforced` paga una query a `trainer_links`.
 *
 * Lo volatil, si algun dia hace falta, va como campo HERMANO de `users/{uid}`,
 * fuera del mapa. El id del evento ya vive en la coleccion del dedupe, que es
 * donde corresponde.
 *
 * ── La forma del contrato ──
 *
 * `athleteSubscription` NO espeja a `TrainerSubscription` (que declara 9
 * campos). Son dos productos distintos y la separacion es una decision escrita
 * —ver `athlete_entitlement_provider.dart:21-33`—. Los dos unicos consumidores
 * del mapa en todo el repo leen unicamente `.status`, y otorgan con
 * `{"active", "grace"}`.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  LOS SECRETOS
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   firebase functions:secrets:set RC_API_KEY         # V2 secret key
 *   firebase functions:secrets:set RC_WEBHOOK_SECRET  # el de HMAC signing
 *
 * `RC_PROJECT_ID` no es secreto y va por variable de entorno.
 *
 * Ojo con un detalle de los secretos de v2 que ya nos mordio con MP: quedan
 * PINEADOS a la version que existia al momento del deploy. Rotar el secreto en
 * Secret Manager no lo cambia en la function: **hay que redesplegar**.
 */

import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { getApps, initializeApp, type App } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { createHmac, timingSafeEqual } from "node:crypto";

import { createRcClient, RcApiError, statusQueOtorga } from "./client";
import type { RcClient } from "./client";

const RC_API_KEY = defineSecret("RC_API_KEY");
const RC_WEBHOOK_SECRET = defineSecret("RC_WEBHOOK_SECRET");

/**
 * Coleccion del dedupe. Un doc por evento procesado CON EXITO, id = `event.id`.
 *
 * Aca el dedupe no puede ser una ventana de tiempo como la de MP. Alla los
 * reintentos venian cada 15 minutos fijos, asi que una ventana de 10 los
 * distinguia de un evento nuevo. RevenueCat reintenta a los 5, 10, 20, 40 y 80
 * minutos: no hay ningun numero que sea «menor que el intervalo» para los cinco.
 *
 * Por eso la marca es booleana y permanente: **procesado con exito**. Un fallo
 * transitorio simplemente no escribe la marca, y el reintento —que trae el
 * MISMO `id`, la doc lo garantiza— vuelve a entrar y se procesa.
 */
export const RC_WEBHOOK_EVENTS_COLLECTION = "rc_webhook_events";

/**
 * El entitlement que otorga el paywall del alumno.
 *
 * Es un LOOKUP KEY de RevenueCat, y tiene que coincidir carácter por carácter
 * con el del dashboard. Ojo: este string queda ademas COMPILADO en el binario
 * instalado de la app, asi que renombrarlo rompe a todo el que tenga una
 * version vieja. Describe el ACCESO, no el plan que lo vende, justamente para
 * no tener que renombrarlo cuando cambien los planes.
 */
export const ENTITLEMENT_ALUMNO = "alumno_pro";

/**
 * Cuanta deriva de reloj se tolera entre el `t` de la firma y nuestro ahora.
 *
 * Cinco minutos, y NO mas. Ver el encabezado: `t` se recalcula en cada
 * reintento, asi que estirarlo no protege ningun reintento y si abre una
 * ventana de replay.
 */
export const TOLERANCIA_FIRMA_MS = 5 * 60 * 1000;

/** Lo que se le escribe al alumno cuando ninguna suscripcion otorga. */
export const STATUS_SIN_DERECHO = "expired";

export type RcWebhookOutcome =
  | "acreditado"
  | "revocado"
  | "sin-cambios"
  | "duplicado"
  | "sin-uid"
  | "sin-alumno"
  | "firma-invalida"
  /** RevenueCat no contesto. El UNICO que pide reintento. */
  | "error-rc";

export interface RcWebhookDeps {
  rcClient: RcClient;
  nowMs: number;
  /** Vacio = modo degradado, se procesa sin validar el origen. */
  signingSecret: string;
  entitlement: string;
}

function ensureApp(): App {
  return getApps().length ? getApps()[0] : initializeApp();
}

// ───────────────────────────────────────────────────────────────────────────
// Firma
// ───────────────────────────────────────────────────────────────────────────

export interface FirmaRcInput {
  signingSecret: string;
  /** El header `X-RevenueCat-Webhook-Signature`, tal cual llego. */
  header: string | undefined;
  /** Los BYTES del body, sin parsear ni re-serializar. */
  rawBody: Buffer;
  nowMs: number;
}

/**
 * ¿La firma de este POST es de RevenueCat?
 *
 * Sin `varianteDeFirma` ni combinatoria: aca la doc alcanza. Un solo manifest,
 * un solo digest.
 */
export function firmaRcValida(input: FirmaRcInput): boolean {
  // Modo degradado explicito: sin secreto no hay nada que validar. Lo logea
  // quien llama, en CADA request — el modo degradado que no se ve es el que se
  // queda para siempre.
  if (!input.signingSecret) return true;
  if (!input.header) return false;

  let t = "";
  let v1 = "";
  for (const parte of input.header.split(",")) {
    const i = parte.indexOf("=");
    if (i < 0) continue;
    const clave = parte.slice(0, i).trim();
    const valor = parte.slice(i + 1).trim();
    if (clave === "t") t = valor;
    else if (clave === "v1") v1 = valor;
  }
  if (!t || !v1) return false;

  const ts = Number(t);
  if (!Number.isFinite(ts)) return false;
  // `t` viene en SEGUNDOS unix.
  if (Math.abs(input.nowMs - ts * 1000) > TOLERANCIA_FIRMA_MS) return false;

  // El manifest: `<t>.<body crudo>`. Los bytes del body van tal cual llegaron.
  const esperado = createHmac("sha256", input.signingSecret)
    .update(`${t}.`)
    .update(input.rawBody)
    .digest("hex");

  // Comparacion de tiempo constante. `timingSafeEqual` explota si los largos
  // difieren, asi que se chequea antes — y ese chequeo no filtra nada util:
  // el largo de un SHA-256 en hex es publico.
  const a = Buffer.from(esperado, "utf8");
  const b = Buffer.from(v1, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

// ───────────────────────────────────────────────────────────────────────────
// El handler
// ───────────────────────────────────────────────────────────────────────────

export interface RcWebhookRequestLike {
  body: unknown;
  rawBody: Buffer;
  header(nombre: string): string | undefined;
}

/**
 * Saca el `app_user_id` del evento. Es **lo unico** que se usa del body.
 *
 * RevenueCat manda ademas `original_app_user_id` y `aliases`. Se prefiere
 * `app_user_id` porque es el que corresponde al momento del evento; el
 * `original` puede ser un id anonimo de antes del login.
 */
export function uidDelEvento(body: unknown): string | null {
  const ev = (body as { event?: Record<string, unknown> })?.event;
  if (typeof ev !== "object" || ev === null) return null;
  const uid = ev.app_user_id;
  return typeof uid === "string" && uid !== "" ? uid : null;
}

/** El id del evento, estable a lo largo de los cinco reintentos. */
export function idDelEvento(body: unknown): string | null {
  const ev = (body as { event?: Record<string, unknown> })?.event;
  if (typeof ev !== "object" || ev === null) return null;
  const id = ev.id;
  return typeof id === "string" && /^[A-Za-z0-9_:-]{1,128}$/.test(id)
    ? id
    : null;
}

/**
 * El handler puro. Devuelve el outcome; quien lo envuelve decide el HTTP.
 *
 * Separado del `onRequest` por el mismo motivo que los `run*` de los callables
 * (ADR-CXP-004): asi se testea sin levantar un servidor y sin red.
 */
export async function runRcWebhook(
  app: App,
  req: RcWebhookRequestLike,
  deps: RcWebhookDeps,
): Promise<RcWebhookOutcome> {
  if (!deps.signingSecret) {
    logger.warn(
      "rc/webhook: SIN clave de firma — se procesa sin validar el origen. " +
        "Cargala con `firebase functions:secrets:set RC_WEBHOOK_SECRET`.",
    );
  }

  if (
    !firmaRcValida({
      signingSecret: deps.signingSecret,
      header: req.header("x-revenuecat-webhook-signature"),
      rawBody: req.rawBody,
      nowMs: deps.nowMs,
    })
  ) {
    logger.warn("rc/webhook: firma invalida");
    return "firma-invalida";
  }

  const uid = uidDelEvento(req.body);
  if (!uid) {
    // Sin uid no hay a quien acreditarle nada, y ningun reintento le va a
    // agregar uno. 200.
    logger.warn("rc/webhook: evento sin app_user_id utilizable");
    return "sin-uid";
  }

  const db = getFirestore(app);

  // ── Dedupe, ANTES de salir a RevenueCat ──
  const eventoId = idDelEvento(req.body);
  const visto = eventoId
    ? db.collection(RC_WEBHOOK_EVENTS_COLLECTION).doc(eventoId)
    : null;
  if (visto && (await visto.get()).exists) {
    return "duplicado";
  }

  // ── El alumno tiene que existir. No se crea nada desde un webhook ──
  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    // Puede ser un `app_user_id` anonimo de RevenueCat (alguien que compro
    // antes de loguearse) o un uid de otro proyecto. En ninguno de los dos
    // casos reintentar ayuda: 200 y se marca como visto.
    logger.info("rc/webhook: no existe el usuario del evento", { uid });
    if (visto) await visto.set({ procesadoMs: deps.nowMs, outcome: "sin-alumno" });
    return "sin-alumno";
  }

  // ── La UNICA fuente de la verdad: preguntarle a RevenueCat con nuestra key ──
  let subs;
  try {
    subs = await deps.rcClient.getSubscriptions(uid);
  } catch (e) {
    const err = e as RcApiError;
    logger.error("rc/webhook: no se pudo leer las suscripciones", {
      uid,
      status: err.status,
      retryable: err.retryable,
    });
    // NO se marca como procesado, a proposito: el reintento de RevenueCat es
    // exactamente lo que hace falta, y los reintentos son cinco.
    return "error-rc";
  }

  const otorga = statusQueOtorga(subs, deps.entitlement);
  const status =
    otorga === null
      ? STATUS_SIN_DERECHO
      : otorga === "in_grace_period"
        ? "grace"
        : "active";

  // ── Corto-circuito: no escribir si no cambio nada ──
  //
  // No es una optimizacion cosmetica. Una escritura identica igual dispara
  // `syncAthletePaywallOnUser`, porque el trigger corre sobre el evento de
  // escritura y recien despues compara. Cortar aca es lo que hace que un
  // RENEWAL mensual de un alumno que ya estaba activo cueste cero.
  const previo = (userSnap.data() ?? {}).athleteSubscription as
    | { status?: unknown }
    | undefined;
  if (previo?.status === status) {
    if (visto) await visto.set({ procesadoMs: deps.nowMs, outcome: "sin-cambios" });
    return "sin-cambios";
  }

  // El mapa entero, de una. `set` con merge sobre el campo lo REEMPLAZA
  // completo, que es lo que queremos: un solo campo adentro, siempre.
  await userRef.set({ athleteSubscription: { status } }, { merge: true });

  const outcome: RcWebhookOutcome =
    status === STATUS_SIN_DERECHO ? "revocado" : "acreditado";

  if (visto) await visto.set({ procesadoMs: deps.nowMs, outcome, uid });

  logger.info("rc/webhook: evento procesado", { uid, status, outcome });
  return outcome;
}

export const rcWebhook = onRequest(
  {
    region: "southamerica-east1",
    secrets: [RC_API_KEY, RC_WEBHOOK_SECRET],
    // Mas alto que el 10 de `mpWebhook`, y por una razon concreta, no por
    // generosidad: cuando el tope se toca, Cloud Run contesta 429 ANTES de
    // ejecutar nada, y RevenueCat lo cuenta como entrega fallida. Con MP eso
    // costaba 15 minutos de demora; aca **quema uno de los cinco reintentos**.
    // El tope sigue existiendo para acotar el abuso de un endpoint publico,
    // pero se le da mas aire porque el costo de tocarlo es mayor.
    maxInstances: 20,
    // RevenueCat corta a los 60 segundos. 30 alcanza de sobra para un GET a su
    // API (8 s de timeout propio) mas dos lecturas y una escritura de
    // Firestore, y deja margen para un arranque en frio.
    timeoutSeconds: 30,
    // No hay dato de usuario en el body y el CORS no protege a un servidor.
    cors: false,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("solo POST");
      return;
    }

    let outcome: RcWebhookOutcome;
    try {
      outcome = await runRcWebhook(
        ensureApp(),
        {
          body: req.body,
          // Los BYTES, sin re-serializar. Ver el encabezado.
          rawBody: req.rawBody,
          header: (n: string) => req.get(n) ?? undefined,
        },
        {
          rcClient: createRcClient(
            RC_API_KEY.value(),
            process.env.RC_PROJECT_ID ?? "",
          ),
          nowMs: Date.now(),
          signingSecret: RC_WEBHOOK_SECRET.value(),
          entitlement: ENTITLEMENT_ALUMNO,
        },
      );
    } catch (err) {
      // Un bug nuestro SI pide reintento, al reves que en `mpWebhook`.
      //
      // Alla un 5xx por un bug era un martilleo eterno, asi que convenia
      // acusar 200 y dejar que el barrido de las 03:00 levantara lo perdido.
      // Aca no hay barrido para el alumno todavia, y los reintentos son cinco
      // y se terminan. Un 500 le da al deploy del fix hasta dos horas y media
      // para llegar antes de que el evento se pierda.
      logger.error("rc/webhook: error inesperado", { err });
      res.status(500).send("error interno");
      return;
    }

    if (outcome === "firma-invalida") {
      res.status(401).send("firma invalida");
      return;
    }
    if (outcome === "error-rc") {
      res.status(503).send("no se pudo consultar a RevenueCat");
      return;
    }
    res.status(200).send("ok");
  },
);
