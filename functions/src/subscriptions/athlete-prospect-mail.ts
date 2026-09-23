/**
 * athlete-prospect-mail.ts — el mail al ALUMNO que se quedó sin cobertura.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUE UN MAIL Y NO UNA PANTALLA
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Porque la app NO PUEDE decirle dónde se paga. La Guideline 3.1.3(f) de Apple
 * exime del IAP a las apps companion de una *paid web based tool* **siempre que
 * no haya compras adentro NI llamados a comprar afuera**, y ese amparo es lo
 * que hoy sostiene que el ENTRENADOR pague por Mercado Pago en el Coach Hub
 * web. Un botón «suscribite en gettreino.com» no le cuesta nada al alumno y se
 * lleva puesto el ingreso del profe. Lo fija
 * `test/features/paywall/superficie_de_cobro_alumno_test.dart`.
 *
 * El mail es la salida, y no es una idea nueva de este archivo: el encabezado
 * de `athlete_entitlement.dart` y los guards de `anti_steering_movil_test.dart`
 * ya la dejaron escrita para el caso del PF —«la salida es un MAIL, que es lo
 * único que Apple no gobierna»—. Esto la implementa para el alumno.
 *
 * **La app no cambia ni una línea.** El backend nota el cambio y escribe. Apple
 * revisa el binario, y el binario sigue sin nombrar el checkout.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  LAS DOS CLAUSULAS QUE SEPARAN UN MAIL DE UN INCIDENTE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Es el mismo problema que documenta `decideProspectMail` para el PF, y la
 * lección se copia entera porque el error también se copiaría entero:
 *
 *   **1. El DELTA, no el estado.** Se manda cuando `athletePaywallEnforced`
 *   PASA a `true`, no cuando ES `true`. «Está sin cobertura» describe a media
 *   base; «se quedó sin cobertura recién» describe a una persona.
 *
 *   **2. El BARRIDO no manda.** Esta es la que el caso del PF no tenía que
 *   pensar, y acá es la más peligrosa. `sweepAthletePaywall` llama al mismo
 *   `syncAthletePaywallEnforced`, así que la PRIMERA corrida después de
 *   encender `ATHLETE_PAYWALL_ENFORCEMENT_ENABLED` va a voltear de `false` a
 *   `true` a todos los alumnos sin cobertura que ya existen. Cada uno con su
 *   `changed: true` perfectamente legítimo.
 *
 *   Sin esta cláusula, encender el flag manda el mail a la base entera en una
 *   corrida. El delta no alcanza: hay que distinguir un cambio que le pasó al
 *   usuario de un cambio que le pasó al sistema.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  UNA DIVERGENCIA DELIBERADA CON EL MAIL DEL PF
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `decideProspectMail` descarta a quien tiene o tuvo suscripción («ése es
 * CLIENTE, no prospecto: le hablan los otros dos mails»). **Acá no se descarta,
 * y es a propósito.**
 *
 * El motivo es que para el alumno esos «otros dos mails» NO EXISTEN: no hay
 * `subscription-downgraded` ni `subscription-grace` del lado del atleta. Copiar
 * la cláusula dejaría al alumno cuya suscripción venció sin ningún aviso — y es
 * justamente el que más cerca está de volver a pagar.
 *
 * No hace falta una cláusula para evitarle el mail a quien SÍ tiene derecho
 * vigente: `resolveAthletePaywallEnforced` ya devuelve `false` cuando
 * `hasEntitlingSubscription`, así que un `value === true` significa, por
 * construcción, que no lo tiene.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL prefKey, Y POR QUE ESTE MAIL SI LO LLEVA
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Los tres mails de suscripción del PF van SIN `prefKey`: son transaccionales
 * —le avisan a alguien que ya paga que algo pasó con su plata— y no se apagan.
 *
 * Éste es distinto: le ofrece un producto a alguien que no lo compró. Eso es
 * una **comunicación comercial**, y `docs/legal/politica-de-privacidad.md` se
 * compromete, textual, a que «para las comunicaciones comerciales la oposición
 * es ABSOLUTA: si la ejercés, dejamos de enviarlas sin ponderar nada en
 * contra». Un mail comercial sin interruptor convierte esa línea en mentira.
 *
 * ⚠️ Lo que este archivo NO resuelve: `emailChannelAllowed` trata la ausencia
 * de preferencia como «sí» (`value !== false`), o sea **opt-out**. La política
 * declara la base legal como «tu consentimiento», que leído estricto es
 * opt-IN. Las dos cosas no son lo mismo y la diferencia es de abogado, no de
 * código — está anotada en la consulta legal pendiente. Lo que sí queda
 * garantizado desde hoy es el derecho de oposición, que es lo que la política
 * promete de forma absoluta.
 */

import { App } from "firebase-admin/app";

import { enqueueMail } from "../mail/enqueue-mail";
import { artDateKey } from "../mail/format";
import { LANDING_URL } from "../mail/templates";
// `import type` y no un import normal: `athlete-paywall-enforced.ts` importa de
// ESTE archivo para cablear el aviso, asi que un import de valor cerraria un
// ciclo en runtime. El tipo se borra al compilar y el ciclo no existe.
import type { SyncResult } from "./athlete-paywall-enforced";

/** La clave de `notificationPrefs` con la que el alumno lo apaga. */
export const ATHLETE_PROSPECT_PREF_KEY = "novedades_plan";

export interface AthleteProspectMailPlan {
  kind: "athlete-coverage-lost";
  scope: string;
}

/**
 * De dónde viene la corrida que produjo el `SyncResult`.
 *
 * No es un detalle de implementación: es la diferencia entre un cambio que le
 * pasó AL USUARIO y uno que no.
 *
 *   `"evento"`  — le pasó a esta persona. Es el ÚNICO que manda.
 *   `"barrido"` — le pasó al sistema: se encendió el enforcement y la
 *                 reconciliación volteó a todos de una.
 *   `"alta"`    — la persona acaba de nacer. Ver la cláusula abajo.
 */
export type OrigenDelCambio = "evento" | "barrido" | "alta";

/**
 * Si corresponde escribirle, y con qué alcance de deduplicación.
 *
 * @param sync     - Lo que devolvió `syncAthletePaywallEnforced`.
 * @param degraded - Si el documento del usuario se leyó degradado.
 * @param origen   - Ver [OrigenDelCambio]. Sólo `"evento"` manda.
 * @param nowMs    - Reloj, inyectado.
 */
export function decideAthleteProspectMail(
  sync: SyncResult,
  degraded: boolean,
  origen: OrigenDelCambio,
  nowMs: number,
): AthleteProspectMailPlan | null {
  // El barrido reconcilia a TODOS. Ver el encabezado: sin esto, encender el
  // flag le manda el mail a la base entera en una sola corrida.
  if (origen === "barrido") return null;

  // ── ⚠️ EL ALTA NO ES UNA PERDIDA DE COBERTURA ──
  //
  // `athletePaywallInputChanged` trata el CREATE como cambio, a proposito y por
  // un motivo bueno: «un alumno recien registrado no tiene el campo, y
  // "ausente" para la regla significa NO enforced», asi que sin esa rama el
  // alumno nuevo se saltearia el paywall hasta tocar un vinculo.
  //
  // Pero para ESTE mail esa misma rama es una trampa. Un alumno que se registra
  // sin entrenador y sin suscripcion resuelve a `enforced: true` en su primer
  // milisegundo de vida, con un `changed: true` impecable — y recibiria
  // «tu lugar ya no esta cubierto» en el segundo en que se dio de alta. A
  // alguien que NUNCA estuvo cubierto, mezclado con el mail de bienvenida.
  //
  // El mail habla de una PERDIDA. Nacer sin algo no es perderlo.
  //
  // Es el mismo error de familia que las otras tres clausulas —confundir un
  // cambio del sistema con algo que le paso a la persona— y se encontro
  // preguntando «¿que le llega al alumno free que nunca tuvo profe?».
  if (origen === "alta") return null;

  // Mismo criterio que el resto del paywall: sobre un documento que sabemos
  // que leimos mal no le escribimos a nadie sobre plata.
  if (degraded) return null;

  // EL DELTA. `changed` solo no alcanza: tambien es `true` cuando el campo pasa
  // de `true` a `false`, que es la noticia CONTRARIA — el alumno recupero
  // cobertura porque un profe lo tomo. Ese no lleva mail ninguno.
  if (!sync.changed || !sync.value) return null;

  return {
    kind: "athlete-coverage-lost",
    // Un alumno al que su profe da de baja y vuelve a tomar el mismo dia puede
    // producir dos flips. La fecha ART en el scope hace que el segundo caiga en
    // el mismo documento de cola y no salga dos veces.
    scope: `sin_cobertura_${artDateKey(nowMs)}`,
  };
}

/**
 * Encola el mail.
 *
 * El CTA va a la landing y no a la app: es el UNICO mail del repo cuyo destino
 * es el checkout web, porque es el unico lugar donde el alumno puede pagar. Los
 * demas mandan a `app.gettreino.com/abrir/...` con un App Link.
 */
export async function enqueueAthleteProspectMail(
  app: App,
  athleteId: string,
  plan: AthleteProspectMailPlan,
): Promise<string | null> {
  return enqueueMail(app, {
    toUid: athleteId,
    kind: plan.kind,
    scope: plan.scope,
    prefKey: ATHLETE_PROSPECT_PREF_KEY,
    params: { ctaUrl: `${LANDING_URL}/es/suscripcion/checkout` },
  });
}

/**
 * El cable: decide y encola. Total — nunca tira.
 *
 * Que no tire es la razon de que exista esta funcion en vez de dos llamadas en
 * cada trigger: un fallo mandando un mail COMERCIAL no puede tumbar la
 * reconciliacion del entitlement, que es lo que decide si el alumno puede
 * entrenar. El mail es lo prescindible de los dos.
 */
export async function avisarAlAlumnoSinCobertura(
  app: App,
  sync: SyncResult,
  origen: OrigenDelCambio,
  nowMs: number,
  logger: { info: (m: string, d?: unknown) => void; error: (m: string, d?: unknown) => void },
  degraded: boolean = false,
): Promise<void> {
  try {
    const plan = decideAthleteProspectMail(sync, degraded, origen, nowMs);
    if (!plan) return;
    await enqueueAthleteProspectMail(app, sync.uid, plan);
    logger.info("athlete-prospect-mail: encolado", { uid: sync.uid });
  } catch (err) {
    logger.error("athlete-prospect-mail: no se pudo encolar", { uid: sync.uid, err });
  }
}
