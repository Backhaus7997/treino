/**
 * free-limit-mail.ts — el mail al alumno que chocó un tope del plan free.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL SEGUNDO MAIL DEL PAYWALL DEL ALUMNO, Y EL DE MAYOR INTENCION
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `athlete-prospect-mail.ts` le escribe al que PERDIO cobertura —su profe
 * terminó el vínculo, o venció su suscripción—. Éste le escribe al que está
 * chocando contra una pared **mientras intenta hacer algo**: quiso una cuarta
 * rutina, o una plantilla paga, y la app le dijo que no.
 *
 * Es el momento de mayor intención que hay en el producto, y hasta acá no
 * producía nada: los topes son de cliente puro. La app ahora los ANOTA
 * (`freePlanLimitHitKind` / `freePlanLimitHitAt`, escritos por
 * `showFreePlanLimitSheet`), y este módulo es el que lee esa anotación.
 *
 * ── Por qué un mail ──
 *
 * Porque la app no puede decirle dónde se paga. La Guideline 3.1.3(f) exime
 * del IAP a las apps companion siempre que no haya compras adentro **ni
 * llamados a comprar afuera**, y ese amparo es lo que sostiene el cobro del
 * ENTRENADOR. Lo que Apple sí permite, textual: *«send communications outside
 * of the app to their user base about purchasing methods other than in-app
 * purchase»*.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  DOS CAMINOS: AL TOQUE, Y EL BARRIDO COMO RED
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * **El camino principal es `sendFreeLimitMailOnHit`**: un trigger sobre
 * `users/{uid}` que encola apenas la app anota el tope. El mail llega en
 * segundos, mientras el alumno todavía tiene en la mano lo que quiso hacer.
 *
 * Antes era sólo el barrido de las 05:00, con el argumento de que a la mañana
 * se lee entero y entre series se archiva. Se dio vuelta a propósito
 * (2026-09-25, pedido de Martín): la intención está AHORA, y a la mañana
 * siguiente es un recuerdo. El costo aceptado es que muchas veces llegue en
 * medio del entrenamiento.
 *
 * **`sweepFreeLimitMail` se queda, como red.** Si el trigger falla —un
 * encolado que no entró, una instancia caída—, el barrido lo reintenta al otro
 * día dentro de la ventana de 36 h. Los dos caminos no se pisan: el que llega
 * primero anota el enfriamiento, y la cola deduplica por día y por alumno.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUE UNA FUNCION PROPIA Y NO UNA RAMA DEL BARRIDO QUE YA EXISTE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `sweepAthletePaywall` ya pagina `users where role == "athlete"`, así que
 * colgarse de ahí parecía gratis. No lo es:
 *
 *   - Ese barrido recorre a TODOS los alumnos. Éste sólo necesita a los que
 *     chocaron un tope ayer, que es un subconjunto chico. Una query por
 *     `freePlanLimitHitAt` los trae directo, y **no hace falta índice
 *     compuesto**: Firestore indexa cada campo por su cuenta.
 *   - Y son dos preocupaciones distintas. Aquel escribe un campo de
 *     entitlement; éste manda correo comercial. Mezclarlos ata el día que uno
 *     de los dos tenga que cambiar de frecuencia.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  LAS CUATRO CLAUSULAS DEL SILENCIO
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   1. **Sin anotación → silencio.** Obvio, y es la que hace barata la query.
 *
 *   2. **Anotación vieja → silencio.** El mail vale porque llega CERCA del
 *      intento. Uno que llega tres semanas después no le recuerda nada a
 *      nadie: le cuenta a alguien que ya se olvidó que una vez no pudo.
 *
 *   3. **Ya paga → silencio.** El tope no le muerde. Escribirle «hay una
 *      salida» a quien ya la compró es el error más caro del repertorio.
 *
 *   4. **Ya se le escribió hace poco → silencio.** LA cláusula. Alguien que
 *      usa la app todos los días choca un tope todos los días, y la anotación
 *      se pisa cada vez. Sin enfriamiento, el mismo usuario recibe un mail
 *      diario sobre lo mismo — que es la definición de spam y la forma más
 *      rápida de que el dominio de TREINO termine en una lista negra.
 *
 * El vínculo con un PF se chequea en el handler y no acá, porque es una query:
 * el alumno vinculado NO paga nunca (su profe paga por él), así que un mail
 * ofreciéndole un plan sería cobrarle dos veces a la misma persona.
 *
 * ── El prefKey ──
 *
 * Lleva el mismo que `athlete-prospect-mail.ts`, y a propósito: los dos son
 * comunicación comercial sobre lo mismo, y para el usuario apagar uno y seguir
 * recibiendo el otro sería no haber apagado nada.
 */

import { App } from "firebase-admin/app";
import { DocumentData, Timestamp, getFirestore } from "firebase-admin/firestore";

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

import { dedupeKey, enqueueMail } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION } from "../mail/types";
import { artDateKey } from "../mail/format";
import { LANDING_URL } from "../mail/templates";
import { ATHLETE_PROSPECT_PREF_KEY } from "./athlete-prospect-mail";
import {
  hasActiveTrainerLink,
  hasEntitlingSubscription as hayPlanVigente,
} from "./athlete-paywall-enforced";

/** El campo que escribe `showFreePlanLimitSheet` al abrirse. */
export const CAMPO_TOPE_AT = "freePlanLimitHitAt";
/** Cuál de los topes se tocó. Viaja al template para elegir el cuerpo. */
export const CAMPO_TOPE_KIND = "freePlanLimitHitKind";
/** Cuándo se le escribió por última vez. Lo escribe este módulo. */
export const CAMPO_MAIL_AT = "freePlanLimitMailAt";

/**
 * Cuán reciente tiene que ser el intento. Ver la cláusula 2.
 *
 * 36 horas y no 24: el barrido corre una vez por día, así que una ventana de
 * exactamente 24 dejaría afuera al que chocó el tope diez minutos DESPUES de
 * la corrida de ayer. El solapamiento lo cubre, y la cláusula 4 se encarga de
 * que no se le escriba dos veces por eso.
 */
export const VENTANA_MS = 36 * 60 * 60 * 1000;

/**
 * Cuánto hay que esperar para volver a escribirle. Ver la cláusula 4.
 *
 * Catorce días. El número sale de qué se está diciendo: no es un aviso
 * operativo sino una oferta, y a alguien que no la tomó se le vuelve a ofrecer
 * cada tanto, no cada semana.
 */
export const ENFRIAMIENTO_MS = 14 * 24 * 60 * 60 * 1000;

export interface FreeLimitMailPlan {
  kind: "free-limit-reached";
  scope: string;
  tope: string;
}

/** Lee un `Timestamp` de Firestore sin confiar en su forma. */
function msDe(valor: unknown): number | null {
  const c = valor as { toMillis?: unknown } | null | undefined;
  if (c == null || typeof c.toMillis !== "function") return null;
  const ms = (c.toMillis as () => number)();
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Si corresponde escribirle a este alumno, y con qué alcance de dedupe.
 *
 * PURA: no toca Firestore. El chequeo de vínculo, que sí es una query, vive en
 * el handler.
 *
 * @param userData - El documento de `users/{uid}`.
 * @param nowMs    - Reloj, inyectado.
 * @param tienePlan - Si ya tiene una suscripción que otorga derecho.
 */
export function decideFreeLimitMail(
  userData: DocumentData | undefined,
  nowMs: number,
  tienePlan: boolean,
): FreeLimitMailPlan | null {
  const tocadoMs = msDe(userData?.[CAMPO_TOPE_AT]);
  if (tocadoMs === null) return null;

  // El mail vale porque llega CERCA del intento. Ver la clausula 2.
  if (nowMs - tocadoMs > VENTANA_MS) return null;

  // Ya paga: el tope no le muerde. Ver la clausula 3.
  if (tienePlan) return null;

  // EL ENFRIAMIENTO. Ver la clausula 4: sin esto, quien usa la app todos los
  // dias recibe un mail por dia sobre lo mismo.
  const ultimoMs = msDe(userData?.[CAMPO_MAIL_AT]);
  if (ultimoMs !== null && nowMs - ultimoMs < ENFRIAMIENTO_MS) return null;

  const tope = userData?.[CAMPO_TOPE_KIND];
  return {
    kind: "free-limit-reached",
    scope: `tope_${artDateKey(nowMs)}`,
    tope: typeof tope === "string" && tope ? tope : "desconocido",
  };
}

/**
 * Encola el mail y anota que se escribió.
 *
 * Las dos cosas juntas, y en ese orden: si el `set` fallara despues de encolar,
 * el enfriamiento no quedaria anotado y el alumno podria recibir otro mail
 * manana. Encolar dos veces es peor que no anotar, asi que el `set` va DESPUES
 * del encolado y ambos estan dentro del mismo `try` del handler.
 *
 * `enqueueMail` nunca tira: devuelve `null` tanto si el mail YA estaba en la
 * cola (reintento del barrido, sano) como si la escritura FALLÓ. Si se anotara
 * el enfriamiento en los dos casos, una falla transitoria silenciaría al
 * alumno catorce días sin que exista mail alguno. Por eso, ante un `null`, se
 * mira la cola: si el documento está, se anota; si no, se tira, y el barrido
 * lo cuenta como fallido.
 *
 * Tirar NO garantiza un reintento. El barrido es diario y la ventana es de
 * 36 h, así que la corrida de mañana sólo vuelve a ver los topes que hoy
 * tienen menos de 12 h. Uno más viejo sale de la query y no se reintenta: el
 * mail llega recién si el alumno vuelve a chocar un tope. Se aceptó así
 * porque la falla es rara y el mail es comercial; lo que este chequeo sí
 * garantiza es que ese próximo choque no encuentre un enfriamiento anotado
 * sobre un mail que nunca salió.
 */
export async function enqueueFreeLimitMail(
  app: App,
  athleteId: string,
  plan: FreeLimitMailPlan,
  nowMs: number,
): Promise<void> {
  const queuedId = await enqueueMail(app, {
    toUid: athleteId,
    kind: plan.kind,
    scope: plan.scope,
    prefKey: ATHLETE_PROSPECT_PREF_KEY,
    params: {
      tope: plan.tope,
      ctaUrl: `${LANDING_URL}/es/suscripcion/checkout`,
    },
  });

  if (queuedId === null) {
    const enCola = await getFirestore(app)
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(dedupeKey(plan.kind, plan.scope, athleteId))
      .get();
    if (!enCola.exists) {
      throw new Error("free-limit-mail: no se pudo encolar el mail");
    }
  }

  await getFirestore(app)
    .collection("users")
    .doc(athleteId)
    .set(
      { [CAMPO_MAIL_AT]: Timestamp.fromMillis(nowMs) },
      { merge: true },
    );
}

export interface ResultadoDelBarrido {
  candidatos: number;
  enviados: number;
}

/**
 * Le escribe a los alumnos que chocaron un tope y no tienen por donde salir.
 *
 * ── La query, y por que trae tan poco ──
 *
 * `freePlanLimitHitAt >= hace 36hs` en lugar de recorrer todos los alumnos. El
 * campo solo existe en los documentos de quienes tocaron un tope, y la ventana
 * lo acota a ayer: el conjunto es chico aunque la base no lo sea. Firestore
 * indexa cada campo por su cuenta, asi que esto NO necesita indice compuesto.
 *
 * ── Por que el vinculo se chequea de a uno ──
 *
 * `hasActiveTrainerLink` es una query por alumno, y en una base grande hacerla
 * para todos seria caro. Acá se hace solo para los que ya pasaron las cuatro
 * clausulas puras, que son pocos — el orden de los chequeos ES la optimizacion.
 *
 * ── Un fallo no frena a los demas ──
 *
 * Mismo criterio que `sweepAthletePaywall`: un documento raro no puede dejar
 * sin mail a toda la cola.
 */
export async function barrerTopesTocados(
  app: App,
  nowMs: number = Date.now(),
  logger: { info: (m: string, d?: unknown) => void; error: (m: string, d?: unknown) => void } = console,
): Promise<ResultadoDelBarrido> {
  const desde = Timestamp.fromMillis(nowMs - VENTANA_MS);
  const snap = await getFirestore(app)
    .collection("users")
    .where(CAMPO_TOPE_AT, ">=", desde)
    .get();

  let enviados = 0;
  for (const doc of snap.docs) {
    try {
      const data = doc.data();
      const plan = decideFreeLimitMail(data, nowMs, hayPlanVigente(data));
      if (!plan) continue;

      // El vinculado no paga NUNCA: su profe paga por el. Va ultimo porque es
      // la unica comprobacion que cuesta una query.
      if (await hasActiveTrainerLink(app, doc.id)) continue;

      await enqueueFreeLimitMail(app, doc.id, plan, nowMs);
      enviados++;
    } catch (err) {
      logger.error("free-limit-mail: fallo un alumno", { uid: doc.id, err });
    }
  }

  return { candidatos: snap.size, enviados };
}

/** Qué hizo el trigger con una escritura de `users/{uid}`. Para el log. */
export type ResultadoAlToque =
  | "sin-tope-nuevo"
  | "silencio"
  | "vinculado"
  | "encolado";

/**
 * Si esta escritura es un tope NUEVO: `freePlanLimitHitAt` aparece o cambia.
 *
 * ⚠️ **Es lo que evita el loop.** `enqueueFreeLimitMail` escribe
 * `freePlanLimitMailAt` en el MISMO documento que dispara el trigger. Esa
 * escritura vuelve a despertarlo, pero deja `freePlanLimitHitAt` igual, así
 * que sale acá. Lo mismo con cualquier otra escritura del perfil —nombre,
 * foto, preferencias—, que son la enorme mayoría de las que llegan.
 */
export function esToqueNuevo(
  antes: DocumentData | undefined,
  despues: DocumentData | undefined,
): boolean {
  const despuesMs = msDe(despues?.[CAMPO_TOPE_AT]);
  if (despuesMs === null) return false;
  return despuesMs !== msDe(antes?.[CAMPO_TOPE_AT]);
}

/**
 * El camino al toque: las mismas cuatro cláusulas y el mismo chequeo de
 * vínculo que el barrido, para UN alumno, en el momento en que choca el tope.
 */
export async function alTocarElTope(
  app: App,
  uid: string,
  antes: DocumentData | undefined,
  despues: DocumentData | undefined,
  nowMs: number,
): Promise<ResultadoAlToque> {
  if (!esToqueNuevo(antes, despues)) return "sin-tope-nuevo";

  const plan = decideFreeLimitMail(despues, nowMs, hayPlanVigente(despues));
  if (!plan) return "silencio";

  // Último por la misma razón que en el barrido: es el único chequeo que
  // cuesta una query.
  if (await hasActiveTrainerLink(app, uid)) return "vinculado";

  await enqueueFreeLimitMail(app, uid, plan, nowMs);
  return "encolado";
}

/**
 * El mail al toque. Ver «DOS CAMINOS» en el encabezado.
 *
 * `onDocumentUpdated` y no `Written`: la anotación sale de
 * `userRepository.registrarTopeTocado` sobre un `users/{uid}` que ya existe
 * —la hoja sólo se abre con sesión—, así que un alta nunca trae un tope.
 *
 * Un fallo se loguea y no se relanza. Relanzar no reintentaría (el trigger
 * no tiene `retry`), y la red para ese caso ya existe: el barrido de las 05:00.
 */
export const sendFreeLimitMailOnHit = onDocumentUpdated(
  { document: "users/{uid}", region: "southamerica-east1" },
  async (event) => {
    const antes = event.data?.before?.data();
    const despues = event.data?.after?.data();
    // Filtro barato ANTES de tocar el app: casi todas las escrituras de
    // `users/{uid}` no son un tope.
    if (!esToqueNuevo(antes, despues)) return;

    const { getApp, initializeApp } = await import("firebase-admin/app");
    let app: App;
    try {
      app = getApp();
    } catch {
      app = initializeApp();
    }
    const uid = event.params.uid;
    try {
      const r = await alTocarElTope(app, uid, antes, despues, Date.now());
      logger.info("sendFreeLimitMailOnHit", { uid, resultado: r });
    } catch (err) {
      logger.error("sendFreeLimitMailOnHit: falló; lo reintenta el barrido", {
        uid,
        err,
      });
    }
  },
);

/**
 * 05:00 ART, media hora después de `sweepAthletePaywall`. **Es la red**, no el
 * camino principal: ver «DOS CAMINOS» en el encabezado.
 *
 * Después y no antes de aquel: resuelve `athletePaywallEnforced`, y correr
 * primero dejaría a este barrido decidiendo sobre el estado de anteayer para
 * quien cambió de situación durante la noche.
 */
export const sweepFreeLimitMail = onSchedule(
  {
    schedule: "0 5 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const { getApp, initializeApp } = await import("firebase-admin/app");
    let app: App;
    try {
      app = getApp();
    } catch {
      app = initializeApp();
    }
    const r = await barrerTopesTocados(app, Date.now(), logger);
    logger.info("sweepFreeLimitMail: corrida diaria", r);
  },
);
