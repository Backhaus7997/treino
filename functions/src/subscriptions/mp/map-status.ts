/**
 * map-status.ts — traduce el estado de una suscripcion de Mercado Pago a los
 * cinco estados que TREINO ya sabe interpretar.
 *
 * PURA: sin red, sin Firestore, sin reloj. Todo lo que decide entra por
 * parametro. Es la unica pieza de la integracion que se puede testear
 * exhaustivamente sin tocar nada, y por eso vive sola.
 *
 * ── El contrato al que hay que ENTRAR, no uno nuevo ──
 *
 * `effective-limit.ts` ya define los cinco estados y su semantica, ya esta
 * testeado, y ya lo consumen el gate de promocion y el barrido de
 * entitlements. Este archivo NO inventa vocabulario: traduce al que existe.
 *
 * ── El mapeo, y donde MP y nosotros NO coincidimos ──
 *
 * MP expone `status` con estos valores (verificado en los tipos del SDK
 * oficial, `sdk-nodejs/src/clients/preApproval/commonTypes.ts`, consultado el
 * 2026-09-02):
 *
 *   pending    -> `pending`    el PF arranco el alta y todavia no autorizo.
 *   authorized -> `active`     hay medio de pago y MP va a cobrar.
 *   paused     -> `paused`     suspendida, sin baja.
 *   cancelled  -> `cancelled`  dada de baja.
 *
 * **`grace` NO TIENE EQUIVALENTE EN MP, y esa es la unica asimetria real.**
 * Cuando un cobro rebota, MP NO mueve la suscripcion: la deja en `authorized`
 * y reintenta hasta 4 veces en una ventana de 10 dias. O sea que mirando SOLO
 * el `status` de la suscripcion, un PF que no pago se ve identico a uno al
 * dia.
 *
 * Por eso `grace` se deriva aparte, del historial de cobros
 * (`summarized`/authorized payments), y se pasa a esta funcion por el
 * parametro [cobroPendiente]. Meterlo adentro de la traduccion habria
 * escondido que son dos fuentes distintas.
 *
 * La direccion de la asimetria importa y es deliberada: `grace` da el limite
 * PAGO (ver `effective-limit.ts`), asi que ante la duda el PF conserva sus
 * alumnos mientras MP reintenta. No se castiga a nadie por un rechazo
 * transitorio de tarjeta — y menos al alumno, que no tiene nada que ver.
 */

import { logger } from "firebase-functions";

import { SubscriptionStatus } from "../effective-limit";

/**
 * Los estados que MP puede devolver, como LISTA en runtime. La union se deriva
 * de acá y no al reves, mismo idioma que `SUBSCRIPTION_STATUSES`: agregar un
 * estado sin darselo al traductor deja de ser posible.
 */
export const MP_PREAPPROVAL_STATUSES = [
  "pending",
  "authorized",
  "paused",
  "cancelled",
] as const;

export type MpPreapprovalStatus = (typeof MP_PREAPPROVAL_STATUSES)[number];

const KNOWN_MP_STATUSES: ReadonlySet<string> = new Set(MP_PREAPPROVAL_STATUSES);

/**
 * A donde cae un estado de MP que no conocemos.
 *
 * `pending` y no `active`: un estado que no entendemos no puede habilitar
 * cupo. Y no `cancelled`, que le sacaria alumnos a alguien por un valor que
 * quizas es perfectamente valido y nuevo. `pending` da el limite Free sin
 * revocar el periodo pago que ya este registrado — es el unico que falla del
 * lado del entrenador sin lastimar al alumno.
 */
const FALLBACK_STATUS: SubscriptionStatus = "pending";

export interface MapStatusInput {
  /** El `status` crudo del preapproval, tal como vino de la API. */
  raw: unknown;
  /**
   * `true` cuando el historial de cobros muestra una cuota impaga EN CURSO,
   * o sea que MP esta reintentando. Solo se mira si el estado es
   * `authorized`: en cualquier otro, MP ya dijo algo mas fuerte.
   */
  cobroPendiente?: boolean;
  /** Para que el warn de un estado desconocido sea accionable. */
  trainerId?: string;
}

export interface MappedStatus {
  status: SubscriptionStatus;
  /**
   * `true` cuando el valor de MP no se pudo interpretar. Los llamadores usan
   * esto igual que la degradacion de `subscription-state.ts`: frena trabajo
   * nuevo, nunca revoca relaciones existentes.
   */
  degraded: boolean;
}

/**
 * Traduce el estado de MP. Total: cualquier entrada devuelve un estado valido.
 */
export function mapMpStatus(input: MapStatusInput): MappedStatus {
  const { raw, cobroPendiente = false, trainerId } = input;

  if (typeof raw !== "string" || !KNOWN_MP_STATUSES.has(raw)) {
    logger.warn(
      `mp/map-status: estado desconocido — degradado a ${FALLBACK_STATUS}`,
      { trainerId, received: raw, receivedType: typeof raw },
    );
    return { status: FALLBACK_STATUS, degraded: true };
  }

  const mp = raw as MpPreapprovalStatus;

  switch (mp) {
  case "authorized":
    // La unica rama donde el historial de cobros manda sobre el estado de la
    // suscripcion. Ver el encabezado: MP no mueve `status` cuando reintenta.
    return { status: cobroPendiente ? "grace" : "active", degraded: false };
  case "pending":
    return { status: "pending", degraded: false };
  case "paused":
    return { status: "paused", degraded: false };
  case "cancelled":
    return { status: "cancelled", degraded: false };
  }
}

/**
 * La OTRA mitad de `grace`: si MP tiene una cuota sin cobrar en este momento.
 *
 * Vive al lado de [mapMpStatus] a proposito, porque juntas son una sola
 * decision tomada con dos fuentes distintas. Separarlas en archivos distintos
 * habria escondido justamente eso.
 *
 * Sale de `summarized.pending_charge_quantity` — cuantos cobros quedaron
 * pendientes — verificado en los tipos del SDK oficial
 * (`sdk-nodejs/src/clients/preApproval/commonTypes.ts`, 2026-09-02):
 *
 *   pending_charge_amount?: number | null
 *   pending_charge_quantity?: number | null
 *   semaphore?: string | null
 *
 * **Se elige `quantity` y no `amount`**: un monto pendiente de 0 es ambiguo
 * (¿no hay nada, o hay una cuota de importe cero?), mientras que la cantidad
 * responde exactamente lo que se pregunta. Y NO se usa `semaphore`, que es el
 * indicador de salud propio de MP: no encontramos documentados sus valores, y
 * un campo cuyo dominio no conocemos no puede decidir si alguien conserva sus
 * alumnos.
 *
 * TOTAL y conservadora: ante cualquier duda devuelve `false`, o sea `active`
 * en vez de `grace`. Puede parecer al reves —¿no seria mas prudente asumir que
 * debe?— pero no: `grace` da el limite PAGADO. Concederlo por un dato que no
 * entendimos seria regalar cupo. El que no pago de verdad lo agarra igual el
 * barrido cuando MP mueva el status a `cancelled`.
 */
export function hayCobroPendiente(summarized: unknown): boolean {
  if (summarized === null || typeof summarized !== "object") return false;

  const q = (summarized as { pending_charge_quantity?: unknown })
    .pending_charge_quantity;

  return typeof q === "number" && Number.isFinite(q) && q > 0;
}
