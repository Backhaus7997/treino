/**
 * diferir-primer-cobro.ts: que volver a suscribirse no cobre dos veces el mismo
 * periodo.
 *
 * ── El problema ──
 *
 * Un PF que se da de baja conserva el plan pago hasta `currentPeriodEnd`: es lo
 * que promete la baja y lo que implementa la rama `cancelled` de
 * `effectiveWeightLimit`. Si antes de esa fecha vuelve a suscribirse al MISMO
 * plan, el checkout nuevo cobra en el acto y paga dos veces los mismos dias. MP
 * no lo evita: cada preapproval es independiente y no sabe nada del anterior.
 *
 * ── El arreglo ──
 *
 * El plan nuevo se crea con una prueba de N dias (`auto_recurring.free_trial`),
 * donde N es lo que le queda al periodo pago. La idea es que MP cobre por primera
 * vez cuando la prueba termina, o sea cuando lo que ya estaba pago vence. Que MP
 * se comporte asi NO esta medido: ver la seccion siguiente.
 *
 * ── Lo que se ASUME de MP y NO esta medido ──
 *
 * Nadie probo este flujo contra la API real. Todo lo que sigue es un supuesto,
 * sacado de los tipos del SDK oficial y del sentido comun, y el codigo esta
 * escrito para no depender de que se cumpla al pie de la letra:
 *
 *   a. Que la API acepte `free_trial` en dias dentro del `auto_recurring` de un
 *      plan (los tipos del SDK lo declaran). Si lo rechazara, el checkout de un PF
 *      con dias pagos fallaria: para eso esta el interruptor
 *      [DIFERIR_PRIMER_COBRO_ENABLED].
 *   b. Que la prueba corra desde que el pagador AUTORIZA y que sean N dias
 *      corridos. Si MP los cuenta en su propio calendario (-04:00), el primer
 *      cobro podria caer hasta un dia ANTES de la fecha que calculamos. El `ceil`
 *      de [diasDePrueba] apunta a que no caiga antes, pero solo vale bajo este
 *      supuesto: ninguna otra regla depende de ello (el reconciliador deja
 *      holgura, y un plan con prueba se descarta como evidencia solo si le faltan
 *      mas de [ADELANTO_MAXIMO_DEL_COBRO_MS] para cobrar). Si MP ignorara o
 *      acortara la prueba, el reconciliador lo avisa con un warn
 *      ([cobroAntesDeLaPrueba]): con el interruptor encendido, el primer PF real
 *      que vuelva a suscribirse con dias pagos es la medicion de este supuesto.
 *   c. Que `date_created` de la suscripcion sea el momento de la autorizacion, y
 *      que `pending_charge_quantity` pueda contar el primer cobro programado.
 *
 * Este archivo es PURO a proposito: no toca Firestore ni MP. Las lecturas que
 * necesita entran por parametro (`leerPlanes`, `leerSuscripciones`,
 * `diferidoDelCheckoutAbierto`), asi que se testea con fakes de una linea y ningun
 * test puede pasar porque un mock de Firestore acepto de mas.
 *
 * Tiene dos mitades que comparten constantes y vocabulario:
 *
 *   1. AL ABRIR EL CHECKOUT (`decidirDiferimiento`): si el PF califica, y hasta
 *      cuando tiene pago el periodo.
 *   2. AL RECONCILIAR (`aplicarPruebaDiferidaAlEstado` y
 *      `aplicarPruebaDiferidaAlPeriodo`): como se lee despues un plan que nacio
 *      con prueba. Hace falta porque el link de un checkout no vence y MP no
 *      deja dar de baja un plan. Ver el encabezado de esa seccion.
 *
 * ── Por que el pago se comprueba CONTRA MP y no contra nuestra fecha ──
 *
 * `currentPeriodEnd` dice hasta cuando le DURA el plan al PF, no que lo haya
 * PAGADO. Una fecha futura tambien la pueden tener un PF sembrado a mano con el
 * Admin SDK (no hay pago que descontar) o una suscripcion que se cancelo antes de
 * cobrar nada, como una prueba cancelada antes de su primer cobro. Diferir contra
 * una fecha asi es regalar dias: por eso se exige ver en MP un cobro real, y el
 * diferimiento nunca pasa de lo que ese cobro cubre.
 *
 * ── La pregunta de fondo: fallar para que lado ──
 *
 * Todo lo dudoso en este archivo termina en NO diferir, o sea en el
 * comportamiento de antes (cobrar en el acto). Con una sola excepcion, que es
 * deliberada: si no podemos LEER lo que necesitamos para decidir, se tira. Seguir
 * adelante sin saber si el PF tiene dias pagos es exactamente el doble cobro que
 * esto viene a cerrar, y el PF puede reintentar.
 */

import { logger } from "firebase-functions";

import { SubscriptionStatus } from "../effective-limit";
import { toSubscriptionState } from "../subscription-state";
import { SubscriptionTier } from "../tier-config";
import { MpPreapproval } from "./client";
import { MOTIVO_ABANDONO } from "./motivos-terminal";

/**
 * El interruptor del diferimiento. ENCENDIDO.
 *
 * Apagado, el checkout NUNCA difiere: `decidirDiferimiento` corta antes de leer
 * nada y el PF paga en el acto, como antes de que existiera esto. Existe por lo
 * unico que no se pudo probar de todo el diseño: que la API de MP acepte una
 * prueba en dias y la cuente como suponemos (ver "Lo que se ASUME de MP"). Si un
 * checkout diferido empieza a fallar, el rollback es `false` y un deploy; no hay
 * nada que migrar.
 *
 * Lo que NO apaga: las reglas del reconciliador (`aplicarPruebaDiferidaAlEstado`
 * y `aplicarPruebaDiferidaAlPeriodo`). Los planes que ya se abrieron con prueba
 * siguen existiendo en MP y siguen necesitando que se los lea asi; apagar el
 * checkout no los cierra. Por eso esas funciones no leen este valor.
 *
 * `decidirDiferimiento` lo recibe por parametro (`habilitado`), con esta
 * constante de default, igual que `resolvePlanLimits` con sus interruptores
 * (`trainer-plan-limits.ts`): si no, uno de los dos caminos se shipearia sin un
 * test encima.
 */
export const DIFERIR_PRIMER_COBRO_ENABLED = true;

/** Un dia en ms. La prueba que le mandamos a MP se cuenta en dias. */
export const DIA_MS = 24 * 60 * 60 * 1000;

/**
 * Con menos que esto de periodo restante NO se difiere.
 *
 * El solapamiento que se evita seria menor que un dia, y la prueba mas corta que
 * podemos mandar es de un dia: diferir por horas le regalaria al PF casi un dia
 * entero para ahorrarle unas pocas horas, y le suma un caso borde a un cobro.
 */
export const MIN_DIFERIMIENTO_MS = DIA_MS;

/**
 * Cuantos planes del PF se le consultan a MP para comprobar un pago.
 *
 * Cada uno es una llamada en el camino del boton "ELEGIR PLAN", asi que el peor
 * caso tiene que estar acotado. El tope se aplica DESPUES de descartar los planes
 * que no pueden ser evidencia (ver [planesARevisar]): cortar antes deja afuera
 * justo al que pago.
 */
export const MAX_PLANES_A_REVISAR = 3;

/**
 * Cuanto antes de E suponemos, como maximo, que MP puede cobrar el primer cobro
 * de un plan con prueba.
 *
 * Los dias de prueba se calculan para que el cobro caiga en E. Si MP los cuenta en
 * su propio calendario (-04:00) y no en tramos de 24 h (no esta medido), el cobro
 * puede caer hasta un dia antes. Se usa para decidir que un plan con prueba
 * TODAVIA NO PUDO COBRAR (ver [planesARevisar]); es un margen, no una garantia.
 */
export const ADELANTO_MAXIMO_DEL_COBRO_MS = DIA_MS;

/** Un plan de `mp_plans` tal como sale de Firestore, sin interpretar. */
export interface PlanDeLaCuenta {
  id: string;
  data: Record<string, unknown>;
}

/**
 * `unknown` → ms si tiene forma de Timestamp, si no 0.
 *
 * El 0 manda al plan al final del orden (el mas viejo) en vez de tirar: un plan
 * sin fecha legible puede seguir siendo el que pago, y descartarlo seria perder
 * la evidencia. Solo pierde frente a los que tienen fecha.
 */
function creadoEnMs(createdAt: unknown): number {
  const t = createdAt as { toMillis?: unknown } | null | undefined;
  return t != null && typeof t.toMillis === "function"
    ? (t.toMillis as () => number)()
    : 0;
}

/**
 * Si este plan PUEDE ser la evidencia de un pago. Ver [planesARevisar] para el
 * por que de cada filtro.
 */
function puedeHaberCobrado(
  data: Record<string, unknown>,
  tier: SubscriptionTier,
  nowMs: number,
): boolean {
  // Un plan de PF (no de alumno) del MISMO tier que pide.
  if (data.producto === "athlete" || data.tier !== tier) return false;

  // Un plan que tuvo una suscripcion: cerrado (`terminal`) y que NO sea un
  // checkout abandonado. Un plan reemplazado SIGUE contando.
  if (data.terminal !== true || data.terminalReason === MOTIVO_ABANDONO) {
    return false;
  }

  // Un plan con prueba que todavia no pudo cobrar.
  const e = data.diferidoHastaMs;
  if (
    typeof e === "number" &&
    Number.isFinite(e) &&
    e > nowMs + ADELANTO_MAXIMO_DEL_COBRO_MS
  ) {
    return false;
  }

  return true;
}

export interface PlanesARevisar {
  /** Cuantos planes pasaron los filtros: ANTES del tope. Va al log. */
  candidatos: number;
  /** A los que se les pregunta a MP: los mas nuevos, hasta [MAX_PLANES_A_REVISAR]. */
  ids: string[];
}

/**
 * Los planes de este PF a los que vale la pena preguntarle a MP si cobraron.
 *
 * ── El orden importa: primero se descarta, DESPUES se corta ──
 *
 * Cortar por recencia sobre TODOS los planes del tier deja afuera al que pago.
 * Cada toque del boton fuera de la ventana de reuso de 30 minutos, y cada cambio
 * de ciclo, abre un plan nuevo en MP: con tres toques sin pagar, el plan que si
 * pago es el cuarto mas nuevo, no se revisa, y al PF se le cobra en el acto lo que
 * ya tenia pago. Por eso el tope va al final y los filtros van antes. Los filtros:
 *
 *   1. **Un plan de PF del MISMO tier que pide.** El diferimiento solo aplica a
 *      volver al mismo plan, asi que un pago de otro tier (o de un alumno) no
 *      prueba nada sobre este. `producto !== "athlete"` y no `=== "trainer"`: los
 *      planes de PF anteriores al 2026-09-17 no tienen el campo (ver el default de
 *      `lookupPlan`), y son justamente los que mas pueden haber pagado.
 *
 *   2. **Un plan que tuvo una suscripcion: `terminal === true`, y que NO sea un
 *      checkout abandonado.** `reconcile.ts` marca `terminal` cuando MP da de baja
 *      la suscripcion (`cancelled`, sin motivo) y cuando REEMPLAZAMOS un plan (con
 *      [MOTIVO_REEMPLAZO], y solo si MP le encuentra alguna suscripcion): en los
 *      dos hubo una suscripcion, que pudo haber cobrado. Un
 *      checkout que el PF abrio y no pago NO es terminal, asi que sale de la lista
 *      sin preguntarle nada a MP. Un plan pagado y despues reemplazado SIGUE
 *      contando: es la evidencia de ese pago. Lo unico que se descarta de los
 *      terminal es el [MOTIVO_ABANDONO]: el barrido nocturno marca asi un checkout
 *      que a los 30 dias seguia sin suscripcion, y sin descartarlo un PF con un
 *      anual (periodo de hasta 12 meses) y varios toques de hace mas de un mes
 *      volveria a empujar fuera al plan que pago. El costo: un checkout abandonado
 *      que se pago tarde y despues se cancelo conserva su motivo y queda afuera. Es
 *      raro, y el resultado es cobrar en el acto, como antes. Los motivos se
 *      comparan contra las constantes de `motivos-terminal.ts`, que es lo que
 *      escribe el reconciliador: con un literal copiado aca, el dia que alguien
 *      cambie el motivo el filtro dejaria de reconocerlo sin que nada falle.
 *
 *   3. **Si el plan se abrio con prueba, que haya podido cobrar.** Un plan
 *      diferido (`diferidoHastaMs` = E) no cobra antes de E, salvo por el adelanto
 *      que suponemos como maximo ([ADELANTO_MAXIMO_DEL_COBRO_MS], no esta medido).
 *      Volver a suscribirse y cancelar dentro del mismo periodo deja un plan
 *      terminal por vuelta, ninguno llega a cobrar, y todos comparten E (el fin del
 *      periodo pago): tres vueltas empujarian fuera al plan que si pago.
 *
 * Del mas nuevo al mas viejo. El orden se resuelve ACA, en memoria, y no en la
 * query: un `orderBy` sobre un campo distinto del `where` exigiria un indice
 * compuesto, y con un puñado de planes por PF ordenar despues no cuesta nada.
 */
export function planesARevisar(
  planes: PlanDeLaCuenta[],
  tier: SubscriptionTier,
  nowMs: number,
): PlanesARevisar {
  const candidatos = planes
    .filter(({ data }) => puedeHaberCobrado(data, tier, nowMs))
    .map(({ id, data }) => ({ id, creado: creadoEnMs(data.createdAt) }))
    .sort((a, b) => b.creado - a.creado);

  return {
    candidatos: candidatos.length,
    ids: candidatos.slice(0, MAX_PLANES_A_REVISAR).map((p) => p.id),
  };
}

/**
 * [desdeMs] mas [meses] meses, o `null` si la cuenta no da una fecha valida.
 *
 * `setUTCMonth` normaliza el desborde de mes solo (31 de enero + 1 mes cae en
 * marzo), que es como cuenta el calendario. Es la aritmetica de
 * `finDePeriodoDesdeAltaMs` (reconcile.ts), copiada y no importada a proposito:
 * `reconcile.ts` importa este archivo, y un import en el otro sentido seria
 * circular.
 *
 * El `null` existe por el respaldo de [evidenciaDePago], donde los meses son
 * `cobros * periodo`: un `cobros` absurdo se sale del rango de `Date`, y sin esta
 * guarda saldria un `NaN` que `Math.min` propagaria hasta una fecha de
 * diferimiento invalida.
 */
function sumarMesesUtc(desdeMs: number, meses: number): number | null {
  const d = new Date(desdeMs);
  d.setUTCMonth(d.getUTCMonth() + meses);
  const ms = d.getTime();
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Un monto de `summarized` como numero, o `null` si no vino o no se entiende.
 *
 * Acepta un number finito, o un string que sea un numero: el SDK oficial tipa
 * `last_charged_amount` como `string | null` y `charged_amount` como
 * `number | null` (`sdk-nodejs/src/clients/preApproval/commonTypes.ts`,
 * `SummarizedResponse`, consultado el 2026-10-01), y no sabemos cual de las dos
 * formas manda la API de verdad. Un string vacio NO es 0: `Number("")` da 0, y
 * leerlo asi convertiria un campo vacio en un monto de $0.
 */
function montoDe(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/**
 * Cuantos cobros EXITOSOS muestra `summarized`: `charged_quantity` si es un numero
 * finito >= 1 y ningun monto cobrado dice $0 o menos; si no, `0`.
 *
 * ── Por que no alcanza con `charged_quantity` ──
 *
 * Una autorizacion de prueba puede figurar como un "cobro" de $0: MP podria
 * reportarla con `charged_quantity >= 1` y `charged_amount: 0` (no esta medido).
 * Contarla como un pago convertiria el alta de una prueba en evidencia de que el
 * PF pago un periodo entero, o apagaria las reglas de la prueba diferida antes de
 * que MP haya cobrado un peso. Por eso, si `charged_amount` o `last_charged_amount`
 * vienen como numero y no son positivos, no hay cobro.
 *
 * Un monto que falta (o no se entiende) NO descuenta nada: se cae a la regla de la
 * cantidad, que es la de siempre. Pedir el monto como condicion obligatoria
 * dejaria sin evidencia a todo plan si MP no lo manda.
 *
 * La usan las DOS mitades: la evidencia de pago al abrir el checkout
 * ([evidenciaDePago]) y la regla del reconciliador que decide si una prueba
 * "todavia no cobro". Que las dos lean lo mismo es lo que evita que una crea que
 * hubo un pago y la otra no.
 */
export function cobrosExitosos(summarized: unknown): number {
  if (summarized === null || typeof summarized !== "object") return 0;
  const r = summarized as {
    charged_quantity?: unknown;
    charged_amount?: unknown;
    last_charged_amount?: unknown;
  };

  const n = r.charged_quantity;
  if (typeof n !== "number" || !Number.isFinite(n) || n < 1) return 0;

  for (const bruto of [r.charged_amount, r.last_charged_amount]) {
    const monto = montoDe(bruto);
    if (monto !== null && monto <= 0) return 0;
  }
  return n;
}

/** De donde salio la fecha con la que se da por pagado un periodo. */
export type FuenteDelPago = "ultimo-cobro" | "alta";

export interface EvidenciaDePago {
  /** Hasta cuando esta pago el periodo, en ms. */
  hastaMs: number;
  fuente: FuenteDelPago;
}

/**
 * Hasta cuando esta PAGO el periodo de una suscripcion, segun lo que MP dice que
 * cobro, y de donde sale esa fecha. `null` si no hay evidencia de un cobro real.
 *
 * Siempre hacen falta dos cosas: que MP confirme cobros EXITOSOS (ver
 * [cobrosExitosos]: `summarized.charged_quantity >= 1` y ningun monto cobrado en
 * $0 o menos, porque la autorizacion de una prueba no es un pago) y un periodo que
 * entendemos (`auto_recurring`: un entero de 1 a 24, en `months`). Sin alguna de
 * las dos la cuenta seria inventada, y una fecha inventada es un dia regalado o un
 * cobro adelantado. Con eso hay dos fuentes, en este orden:
 *
 *   1. **`last_charged_date`** (fuente `ultimo-cobro`): el ULTIMO cobro exitoso
 *      mas un periodo. Es la fecha que midio MP, y gana siempre que se entienda,
 *      incluso en un plan con prueba (ahi ya es un cobro real).
 *
 *   2. **El alta** (fuente `alta`): `date_created + cobros * periodo`. Es el
 *      respaldo, y solo corre si (1) falta o no es una fecha.
 *
 * Los campos salen de `summarized`, tal como los define el SDK oficial
 * (`sdk-nodejs/src/clients/preApproval/commonTypes.ts`, `SummarizedResponse`,
 * consultado el 2026-10-01).
 *
 * ── Por que existe el respaldo ──
 *
 * De todo lo que usa la fuente (1), `last_charged_date` es lo unico que NO esta
 * medido: ningun payload real del repo lo trae y ningun codigo lo lee todavia. Si
 * la busqueda de MP lo omitiera, sin respaldo esta funcion daria `null` siempre y
 * el diferimiento no se dispararia NUNCA: el PF volveria a pagar dos veces, que
 * es justo lo que todo esto viene a cerrar, y sin un solo sintoma en el log.
 *
 * `charged_quantity` y `date_created` si los leen otros modulos de los mismos
 * resultados de busqueda (`arrepentimiento-por-mail.ts`), asi que se reconstruye
 * con ellos. La cuenta supone que cada cobro exitoso compra UN periodo y que el
 * primero se cobra al autorizar, o sea en `date_created` (nuestros planes no
 * mandan `start_date`).
 *
 * Es una aproximacion. Lo esperable, aunque no esta medido, es que se quede corta
 * y no larga: un cobro que llego tarde o una pausa corren el pago real hacia
 * adelante de lo que da la cuenta. Por el lado largo no se suma ningun riesgo
 * nuevo: el respaldo pide el mismo `charged_quantity >= 1` que (1), y el
 * diferimiento nunca pasa de nuestro propio fin de periodo (ver
 * `decidirDiferimiento`).
 *
 * Es un parche y no un camino normal, igual que el fallback por monto de
 * `tier-mapping.ts`: `decidirDiferimiento` loguea un warn cada vez que el
 * respaldo es el que decide, para que si algun dia pasa a ser el unico se note.
 *
 * ── Y por que NO con una prueba gratis ──
 *
 * La cuenta del respaldo supone que el primer cobro cae en `date_created`. Con
 * `free_trial` (que es como abrimos NOSOTROS los planes diferidos) se espera que el
 * primero caiga cuando la prueba termina, y no sabemos cuantos dias despues: MP
 * puede contarlos distinto de como los mandamos, y eso no esta medido.
 * `alta + cobros * periodo` ignoraria la prueba entera. Se prefiere no reconstruir
 * nada: se devuelve `null`, el diferimiento no se dispara y el checkout cobra en el
 * acto, que es el comportamiento de antes. Para esos planes `last_charged_date` es
 * la UNICA fuente.
 *
 * "Con prueba" es cualquier `free_trial` que no sea `null` ni este ausente:
 * ante una forma que no conocemos (un objeto vacio, un string) no se asume que
 * no hay prueba.
 *
 * El respaldo tambien exige que `charged_quantity` sea un ENTERO: se multiplica,
 * y un 1.5 no es una cantidad de cobros. Y descarta el resultado si no es una
 * fecha valida (ver [sumarMesesUtc]).
 */
export function evidenciaDePago(sub: MpPreapproval): EvidenciaDePago | null {
  const resumen = sub.summarized;
  const cobros = cobrosExitosos(resumen);
  if (cobros < 1) return null;
  // `cobros >= 1` implica que `resumen` es un objeto.
  const { last_charged_date: ultimo } = resumen as { last_charged_date?: unknown };

  const ar = sub.auto_recurring;
  if (ar === null || typeof ar !== "object") return null;
  const {
    frequency: n,
    frequency_type: tipo,
    free_trial: prueba,
  } = ar as {
    frequency?: unknown;
    frequency_type?: unknown;
    free_trial?: unknown;
  };
  // Mismos limites que `finDePeriodoDesdeAltaMs`: un periodo que no entendemos
  // no se suma.
  if (typeof n !== "number" || !Number.isInteger(n) || n < 1 || n > 24) {
    return null;
  }
  if (tipo !== "months") return null;

  // (1) La fecha del ultimo cobro, si MP la mando y se entiende.
  const ultimoMs = typeof ultimo === "string" ? Date.parse(ultimo) : Number.NaN;
  if (Number.isFinite(ultimoMs)) {
    const hastaMs = sumarMesesUtc(ultimoMs, n);
    return hastaMs === null ? null : { hastaMs, fuente: "ultimo-cobro" };
  }

  // (2) El respaldo desde el alta. Ver "Y por que NO con una prueba gratis".
  if (prueba != null) return null;
  if (!Number.isInteger(cobros)) return null;
  const altaMs =
    typeof sub.date_created === "string" ? Date.parse(sub.date_created) : Number.NaN;
  if (!Number.isFinite(altaMs)) return null;

  const hastaMs = sumarMesesUtc(altaMs, cobros * n);
  return hastaMs === null ? null : { hastaMs, fuente: "alta" };
}

/**
 * La fecha de [evidenciaDePago] sin su fuente, para quien solo necesita saber
 * hasta cuando esta pago el periodo.
 */
export function pagadoHastaDe(sub: MpPreapproval): number | null {
  return evidenciaDePago(sub)?.hastaMs ?? null;
}

/**
 * Cuantos dias de prueba hay que mandarle a MP para que, SI cuenta N dias corridos
 * de 24 h desde la autorizacion, el primer cobro caiga en [diferidoHastaMs] o
 * apenas despues.
 *
 * El "si" es un supuesto que NO esta medido (ver "Lo que se ASUME de MP"): si MP
 * cuenta los dias en su propio calendario (-04:00), el cobro podria caer hasta un
 * dia ANTES de esa fecha, y este calculo no lo puede evitar. Lo que SI evita es
 * empeorarlo por redondeo: `ceil` y no `round`, porque redondear hacia abajo
 * adelantaria el cobro y el PF pagaria antes de que venza lo que ya pago, que es
 * el bug entero. El costo de redondear hacia arriba es que el cobro cae hasta un
 * dia despues, que es el lado barato de equivocarse.
 *
 * Vive aca y la llama `abrir-checkout.ts`: los dias salen de UN solo lugar, a
 * partir de `diferidoHastaMs` y del reloj del request.
 */
export function diasDePrueba(diferidoHastaMs: number, nowMs: number): number {
  return Math.ceil((diferidoHastaMs - nowMs) / DIA_MS);
}

/** Por que NO se difiere. Va al log para poder explicar un cobro en el acto. */
export type MotivoSinDiferir =
  | "deshabilitado"
  | "sin-suscripcion"
  | "estado-degradado"
  | "no-esta-cancelada"
  | "otro-tier"
  | "sin-fecha-de-fin"
  | "queda-menos-de-un-dia"
  | "sin-pago-comprobado"
  | "pago-vence-pronto";

export type Diferimiento =
  | { diferir: false; motivo: MotivoSinDiferir }
  | {
      diferir: true;
      /**
       * Hasta cuando esta pago el periodo, en ms. Es la fecha en la que se busca
       * que caiga el primer cobro (ver [diasDePrueba] por lo que no esta medido).
       */
      diferidoHastaMs: number;
    };

export interface DecidirDiferimientoInput {
  uid: string;
  /** El tier que el PF esta por comprar. */
  tier: SubscriptionTier;
  /** `users/{uid}`, tal como salio de Firestore. */
  userData: Record<string, unknown> | undefined;
  nowMs: number;
  /**
   * TODOS los planes de MP de esta cuenta (`mp_plans where uid == uid`).
   *
   * Es una funcion y no un arreglo para no pagar la query a quien no califica
   * por su estado, que es casi todo checkout: solo se llama cuando el PF esta
   * cancelado, en el mismo tier, con mas de un dia por delante.
   */
  leerPlanes: () => Promise<PlanDeLaCuenta[]>;
  /** Las suscripciones de MP detras de un plan (`searchPreapprovalsByPlan`). */
  leerSuscripciones: (planId: string) => Promise<MpPreapproval[]>;
  /**
   * El `diferidoHastaMs` del checkout que ESTE pedido reusaria (misma huella,
   * dentro de la ventana de reuso de `abrir-checkout.ts`), o `null` si no hay
   * ninguno o es un checkout normal.
   *
   * Es el atajo del doble click. Sin el, cada toque de un PF dado de baja pagaba
   * hasta [MAX_PLANES_A_REVISAR] busquedas en MP aunque el checkout ya estuviera
   * abierto y fuera a reusarse. Se llama DESPUES de la elegibilidad barata (que es
   * pura, sin ninguna lectura) y ANTES de salir a MP; si devuelve una fecha valida,
   * se la reusa tal cual y no se busca nada. Opcional: sin el, siempre se busca.
   */
  diferidoDelCheckoutAbierto?: () => Promise<number | null>;
  /**
   * El interruptor [DIFERIR_PRIMER_COBRO_ENABLED]. Parametro y no la constante
   * leida directo, para que los dos caminos tengan test (ver su dartdoc). Sin
   * pasarlo vale la constante.
   */
  habilitado?: boolean;
}

/**
 * Decide si el checkout que el PF esta por abrir tiene que diferir su primer
 * cobro, y hasta cuando.
 *
 * Se difiere SOLO si todo esto es cierto:
 *
 *   0. El interruptor [DIFERIR_PRIMER_COBRO_ENABLED] esta encendido.
 *   1. `subscription` se lee sin degradacion, y esta `cancelled`.
 *   2. Es del MISMO tier que el PF pide (cualquier ciclo: pasar de mensual a
 *      anual dentro del mismo plan tambien paga dos veces los dias que quedan).
 *   3. Le queda al menos [MIN_DIFERIMIENTO_MS] de periodo.
 *   4. MP muestra un cobro real que lo respalda (ver [evidenciaDePago], que
 *      explica las dos fuentes de la fecha y por que hay un respaldo).
 *
 * De la 0 a la 3 salen del documento del usuario y no leen NADA: son la
 * elegibilidad barata. Recien si pasan se mira el checkout abierto y despues se
 * sale a la red.
 *
 * ── El atajo del doble click ──
 *
 * Con la elegibilidad barata en la mano, antes de buscar en MP se pregunta si ya
 * hay un checkout diferido abierto que este pedido reusaria
 * (`diferidoDelCheckoutAbierto`). Si lo hay, la verificacion contra MP ya se hizo
 * cuando se abrio, y repetirla en cada toque costaria hasta
 * [MAX_PLANES_A_REVISAR] busquedas. Ver el campo por las condiciones.
 *
 * El resultado es el MENOR entre nuestra fecha de fin y lo que cubre el cobro de
 * MP. Nuestra fecha puede estar corrida hacia adelante (un tope que no se aplico,
 * una fecha sembrada a mano) y MP puede respaldar menos de lo que ella dice:
 * quedarse con la menor es no regalarle al PF mas de lo que las dos aceptan.
 *
 * De los planes que se revisan se toma el primero (el mas nuevo) que muestre un
 * cobro. Dentro de ese plan, el pago mas lejano.
 *
 * Tira si no puede LEER los planes o las suscripciones: ver el encabezado. Quien
 * llama lo traduce a un error que el PF pueda reintentar.
 */
export async function decidirDiferimiento(
  i: DecidirDiferimientoInput,
): Promise<Diferimiento> {
  const { uid, tier, nowMs } = i;

  const sinDiferir = (
    motivo: MotivoSinDiferir,
    extra: Record<string, unknown> = {},
  ): Diferimiento => {
    logger.info("mp/diferir-primer-cobro: se cobra en el acto", {
      uid,
      tier,
      motivo,
      ...extra,
    });
    return { diferir: false, motivo };
  };

  // El interruptor va primero y corta antes de leer NADA.
  if (!(i.habilitado ?? DIFERIR_PRIMER_COBRO_ENABLED)) {
    return sinDiferir("deshabilitado");
  }

  // ── Elegibilidad barata: solo el documento del usuario, ninguna lectura ──
  const { state, degraded } = toSubscriptionState(i.userData, uid);
  if (degraded) return sinDiferir("estado-degradado");
  if (state === null) return sinDiferir("sin-suscripcion");
  if (state.status !== "cancelled") {
    return sinDiferir("no-esta-cancelada", { status: state.status });
  }
  if (state.tier !== tier) return sinDiferir("otro-tier", { tierActual: state.tier });

  // `Number.isFinite` ademas de `== null`: un `NaN` pasaria el chequeo de nulos y
  // el resto del archivo haria cuentas con una fecha que no existe.
  const finMs = state.currentPeriodEndMs;
  if (finMs == null || !Number.isFinite(finMs)) return sinDiferir("sin-fecha-de-fin");
  if (finMs - nowMs < MIN_DIFERIMIENTO_MS) return sinDiferir("queda-menos-de-un-dia");

  // ── El atajo del doble click: si ya hay un checkout diferido que se va a ──
  // ── reusar, no se busca nada en MP ──
  //
  // La fecha tiene que seguir al menos [MIN_DIFERIMIENTO_MS] hacia adelante y no
  // pasar de nuestro propio fin de periodo (si el periodo se achico desde que se
  // abrio, esa fecha ya no es lo que el PF tiene pago). Y se devuelve EXACTAMENTE
  // la que esta guardada: `abrirCheckout` la compara para reusar, y devolver otra
  // crearia un plan nuevo SIN haber verificado el pago contra MP.
  const abierto = await i.diferidoDelCheckoutAbierto?.();
  if (
    typeof abierto === "number" &&
    Number.isFinite(abierto) &&
    abierto - nowMs >= MIN_DIFERIMIENTO_MS &&
    abierto <= finMs
  ) {
    logger.info(
      "mp/diferir-primer-cobro: se reusa el diferimiento del checkout abierto, " +
        "no se busca en MP",
      { uid, tier, diferidoHastaIso: new Date(abierto).toISOString() },
    );
    return { diferir: true, diferidoHastaMs: abierto };
  }

  // Desde aca se sale a la red, y un fallo TIRA (ver el encabezado).
  const enLaCuenta = await i.leerPlanes();
  const { candidatos, ids: planes } = planesARevisar(enLaCuenta, tier, nowMs);
  // Cuantos planes quedan en cada etapa. Es lo que permite explicar despues un
  // "sin-pago-comprobado": si `candidatos` es 0, no habia ningun plan cerrado.
  const alcance = {
    planesEnLaCuenta: enLaCuenta.length,
    candidatos,
    planesRevisados: planes.length,
  };

  let pago: EvidenciaDePago | null = null;
  let planConPago: string | null = null;
  for (const planId of planes) {
    const evidencias = (await i.leerSuscripciones(planId))
      .map(evidenciaDePago)
      .filter((e): e is EvidenciaDePago => e !== null);
    if (evidencias.length > 0) {
      // El pago mas lejano de ese plan.
      pago = evidencias.reduce((mejor, e) => (e.hastaMs > mejor.hastaMs ? e : mejor));
      planConPago = planId;
      break;
    }
  }
  if (pago === null) return sinDiferir("sin-pago-comprobado", alcance);

  if (pago.fuente === "alta") {
    // El respaldo decidio: MP no mando `last_charged_date` (o no se entiende). Es
    // un parche que grita, no un camino normal: si empieza a verse en cada
    // checkout, la fuente principal no esta llegando y hay que mirar el payload.
    logger.warn(
      "mp/diferir-primer-cobro: MP no mando last_charged_date, el pago se " +
        "reconstruye desde el alta",
      { uid, tier, planConPago },
    );
  }

  const diferidoHastaMs = Math.min(finMs, pago.hastaMs);
  if (diferidoHastaMs - nowMs < MIN_DIFERIMIENTO_MS) {
    return sinDiferir("pago-vence-pronto", {
      ...alcance,
      finDePeriodoIso: new Date(finMs).toISOString(),
      pagadoHastaIso: new Date(pago.hastaMs).toISOString(),
      fuenteDelPago: pago.fuente,
    });
  }

  logger.info("mp/diferir-primer-cobro: se difiere el primer cobro", {
    uid,
    tier,
    ...alcance,
    planConPago,
    fuenteDelPago: pago.fuente,
    diferidoHastaIso: new Date(diferidoHastaMs).toISOString(),
    diasDePrueba: diasDePrueba(diferidoHastaMs, nowMs),
  });
  return { diferir: true, diferidoHastaMs };
}

// ---------------------------------------------------------------------------
// La otra mitad: como se LEE, al reconciliar, un plan que nacio con prueba.
// ---------------------------------------------------------------------------
//
// El plan diferido guarda `diferidoHastaMs` (E) en `mp_plans`. Mientras su
// suscripcion no tenga ningun cobro exitoso (ver [cobrosExitosos]), el
// reconciliador la lee con las reglas de abajo; apenas MP cobra una vez, todo
// vuelve a ser como en cualquier otro plan. Hay tres razones, y NO tienen el
// mismo respaldo: la 1 esta documentada en el repo; la 2 y la 3 dependen de los
// supuestos de "Lo que se ASUME de MP" (arriba) y no estan medidas.
//
//   1. **El link de un checkout no vence y MP no deja dar de baja un plan**
//      (`client.ts`, `cancelPreapproval`). Los dias de prueba se calcularon para
//      el momento en que se abrio el checkout; si el PF paga ese mismo link
//      semanas despues, el primer cobro caeria (suponiendo que la prueba corre
//      desde la autorizacion) semanas despues de E. Sin una regla, le daria plan
//      pago todo ese tiempo sin que MP haya cobrado nada. Y se puede usar a
//      proposito: abrir el checkout, no pagarlo, y autorizarlo cuando convenga
//      para correr el primer cobro tanto como se quiera.
//
//   2. **`pending_charge_quantity` durante la prueba.** Si MP cuenta el primer
//      cobro programado como pendiente (no esta medido), `hayCobroPendiente` lo
//      leeria como un cobro rebotado y el PF pasaria a `grace`, con su mail de
//      "no pudimos cobrar", sin que se le haya intentado cobrar nada.
//
//   3. **Una prueba cancelada antes de su primer cobro.** `resolverFinDePeriodo`
//      arma el fin con `next_payment_date`, con lo que ya estaba guardado o, si
//      no hay nada, con alta mas un periodo entero. Ninguno de los tres sabe que
//      el PF solo pago hasta E (a traves del plan anterior): el ultimo le regala
//      un mes que nunca se cobro, y los otros pueden pasarse de E (si MP manda
//      `next_payment_date` en una prueba cancelada, que no esta medido, seria el
//      primer cobro que no ocurrio, redondeado a dias).
//
// Lo que NO hacen: no dan de baja nada en MP. El pagador autorizo de buena fe, la
// baja es terminal, y una decision nuestra equivocada no se puede deshacer. Se
// limitan a decidir que escribimos en `subscription`.

/**
 * Cuanto despues de abrir el checkout puede autorizar el pagador para que la
 * prueba que le calculamos siga valiendo.
 *
 * Los dias se contaron desde el momento en que se abrio el checkout. Asumimos que
 * MP los cuenta desde que el pagador AUTORIZA (no esta medido), asi que el primer
 * cobro caeria `autorizacion + dias`. Autorizando a las pocas horas la diferencia
 * es chica y entra en [HOLGURA_PRUEBA_MS]; autorizando varios dias despues, el
 * cobro se correria esos mismos dias y dejaria de ser el que le corresponde.
 */
export const VENTANA_AUTORIZACION_MS = 24 * 60 * 60 * 1000;

/**
 * Cuanto despues de E se sigue tratando como "en prueba" a una suscripcion que
 * todavia no cobro.
 *
 * Bajo el supuesto de que MP cuenta N dias corridos desde la autorizacion (no esta
 * medido), el primer cobro caeria en E o hasta un dia despues (por el `ceil` de
 * [diasDePrueba]) mas lo que tardo el pagador en autorizar (hasta
 * [VENTANA_AUTORIZACION_MS]), y MP puede demorarse en intentarlo. Tres dias
 * cubren eso con aire; pasados, un cobro pendiente vuelve a leerse como `grace`
 * y el aviso de "no pudimos cobrar" es verdad.
 *
 * Si MP cuenta en su propio calendario y el cobro cae ANTES de E
 * ([ADELANTO_MAXIMO_DEL_COBRO_MS]), nada de esto se rompe: apenas hay un cobro
 * exitoso el plan deja de leerse como prueba y vale el mapeo de siempre.
 */
export const HOLGURA_PRUEBA_MS = 3 * DIA_MS;

/** Lo que el reconciliador sabe de un plan y de su suscripcion de MP. */
export interface PruebaDiferidaInput {
  /**
   * `mp_plans/{planId}.diferidoHastaMs` (E), TAL CUAL salio del documento. Si no
   * es un numero finito, el plan no es diferido y nada de lo de abajo aplica.
   */
  diferidoHastaMs: unknown;
  /** `mp_plans/{planId}.createdAt` en ms, o `null` si no se pudo leer. */
  planCreadoMs: number | null;
  /** El `status` CRUDO de la suscripcion de MP. */
  mpStatus: unknown;
  /** El estado al que llego el mapeo de siempre (`mapMpStatus`). */
  statusHoy: SubscriptionStatus;
  /** `summarized` de la suscripcion de MP. */
  summarized: unknown;
  /** `date_created` de la suscripcion de MP: cuando el pagador autorizo. */
  mpDateCreated: unknown;
  nowMs: number;
}

/**
 * E si este plan es diferido Y su suscripcion todavia no tuvo ningun cobro
 * EXITOSO; si no, `null`, que quiere decir "este plan se lee como cualquier otro".
 *
 * "Sin cobro exitoso" es lo que dice [cobrosExitosos]: `charged_quantity` ausente
 * o 0, O un monto cobrado que figura en $0 o menos. Lo segundo es la autorizacion
 * de una prueba reportada como un "cobro" de $0: si contara como pago, las reglas
 * se apagarian antes de que MP haya cobrado un peso y el PF quedaria leido como un
 * plan comun sin serlo.
 *
 * Que `charged_quantity` falte o no sea un numero se lee como "no cobro": es el
 * estado normal de una suscripcion recien autorizada. Desde el primer cobro real
 * las reglas se apagan solas, y con ellas cualquier posibilidad de que una
 * prueba retenga a alguien que ya esta pagando.
 */
function enPruebaSinCobrar(
  diferidoHastaMs: unknown,
  summarized: unknown,
): number | null {
  if (typeof diferidoHastaMs !== "number" || !Number.isFinite(diferidoHastaMs)) {
    return null;
  }
  if (cobrosExitosos(summarized) >= 1) return null;
  return diferidoHastaMs;
}

/**
 * Si la suscripcion se autorizo dentro de la ventana que la prueba calculada
 * tolera. Cualquier fecha que falte o no se entienda cuenta como FUERA: ante la
 * duda no se le da plan pago a una suscripcion que todavia no cobro.
 */
function autorizadaATiempo(
  planCreadoMs: number | null,
  mpDateCreated: unknown,
): boolean {
  if (planCreadoMs === null || !Number.isFinite(planCreadoMs)) return false;
  if (typeof mpDateCreated !== "string") return false;
  const autorizadaMs = Date.parse(mpDateCreated);
  if (!Number.isFinite(autorizadaMs)) return false;
  return autorizadaMs - planCreadoMs <= VENTANA_AUTORIZACION_MS;
}

/**
 * En que situacion esta la prueba de un plan, que es lo que el reconciliador
 * necesita para decidir el estado Y para decidir que loguear.
 *
 *   - `no-aplica`: el plan no es diferido, ya tuvo un cobro exitoso, o MP no dice
 *     `authorized`. Se lee como cualquier otro.
 *   - `fuera-de-ventana`: autorizada mucho despues de abrir el checkout (o sin
 *     fechas que se entiendan). Es el link viejo pagado tarde.
 *   - `en-prueba`: autorizada a tiempo y antes de E + [HOLGURA_PRUEBA_MS].
 *   - `vencida`: autorizada a tiempo, pasado ese horizonte y sin ningun cobro
 *     exitoso. El primer cobro ya tendria que haber salido.
 */
export type SituacionDeLaPrueba =
  | "no-aplica"
  | "fuera-de-ventana"
  | "en-prueba"
  | "vencida";

export function situacionDeLaPrueba(i: PruebaDiferidaInput): SituacionDeLaPrueba {
  const e = enPruebaSinCobrar(i.diferidoHastaMs, i.summarized);
  if (e === null) return "no-aplica";
  if (i.mpStatus !== "authorized") return "no-aplica";

  if (!autorizadaATiempo(i.planCreadoMs, i.mpDateCreated)) return "fuera-de-ventana";
  return i.nowMs < e + HOLGURA_PRUEBA_MS ? "en-prueba" : "vencida";
}

/**
 * Si un plan con prueba YA tuvo un cobro exitoso cuando todavia faltaba mas del
 * adelanto maximo ([ADELANTO_MAXIMO_DEL_COBRO_MS]) para que le tocara cobrar.
 *
 * Quiere decir que MP IGNORO o ACORTO la prueba, y que el PF pago dos veces: el
 * periodo que ya tenia pago y el que acaba de cobrar el plan nuevo. Es la medicion
 * del supuesto (b) de "Lo que se ASUME de MP". El cobro ocurrio en algun momento
 * anterior o igual a `nowMs`, asi que si `nowMs` ya esta antes de E menos el
 * adelanto, el cobro cayo antes de lo que cualquier forma de contar los dias
 * podria explicar.
 *
 * No cambia ningun estado ni ninguna fecha: el plan que ya cobro se lee como
 * cualquier otro. Es solo para que el reconciliador avise.
 */
export function cobroAntesDeLaPrueba(
  i: Pick<PruebaDiferidaInput, "diferidoHastaMs" | "summarized" | "nowMs">,
): boolean {
  const e = i.diferidoHastaMs;
  if (typeof e !== "number" || !Number.isFinite(e)) return false;
  if (cobrosExitosos(i.summarized) < 1) return false;
  return i.nowMs < e - ADELANTO_MAXIMO_DEL_COBRO_MS;
}

/**
 * El estado que el reconciliador tiene que escribir para un plan que puede ser
 * diferido. Para uno que no lo es (o que ya cobro), devuelve [statusHoy] tal cual.
 *
 * Solo toca una suscripcion que MP dice `authorized` (ver [situacionDeLaPrueba]):
 *
 *   - **Autorizada fuera de la ventana** (el link se pago mucho despues de abrir
 *     el checkout): `pending`. De este plan el PF no recibe nada hasta el primer
 *     cobro real de MP, y la guarda de `pending` del reconciliador conserva lo
 *     que ya tuviera pago. Ver el punto 1 del encabezado de esta seccion.
 *
 *   - **A tiempo y antes de E + [HOLGURA_PRUEBA_MS]**: `active`, aunque MP diga
 *     que hay un cobro pendiente. Durante la prueba no se debe nada.
 *
 *   - **A tiempo y pasado ese horizonte**: el mapeo de siempre, o sea `grace` si
 *     hay un cobro pendiente. Ahi el primer cobro ya tendria que haber salido.
 *     Si NO hay cobro pendiente, el mapeo de siempre es `active`: una suscripcion
 *     que lleva dias sin cobrar nada ni intentarlo y sigue dando plan pago. Eso no
 *     se corrige aca (no hay evidencia de que sea un error) pero el reconciliador
 *     lo avisa con un warn.
 */
export function aplicarPruebaDiferidaAlEstado(
  i: PruebaDiferidaInput,
): SubscriptionStatus {
  switch (situacionDeLaPrueba(i)) {
  case "fuera-de-ventana":
    return "pending";
  case "en-prueba":
    return "active";
  case "no-aplica":
  case "vencida":
    return i.statusHoy;
  }
}

/**
 * El fin de periodo que el reconciliador tiene que escribir para un plan que
 * puede ser diferido. Para uno que no lo es (o que ya cobro), devuelve
 * [periodEndMs] tal cual.
 *
 * Solo toca una suscripcion que MP dice `cancelled` o `paused`: `min(fin, E)`, y
 * si no habia fin por ningun camino, E. El PF solo pago hasta E, a traves del
 * plan anterior; lo que pase de ahi (el mes que la cascada de
 * `resolverFinDePeriodo` deriva del alta) es un periodo que nunca se cobro.
 *
 * Tener E como respaldo cuando falta la fecha importa: un `null` le sacaria el
 * plan en el acto a alguien que si pago hasta E.
 *
 * El arrepentimiento NO pasa por aca. Quien llama conserva su precedencia: el
 * instante del arrepentimiento gana sobre cualquier fin de periodo.
 */
export function aplicarPruebaDiferidaAlPeriodo(
  i: PruebaDiferidaInput & { periodEndMs: number | null },
): number | null {
  const e = enPruebaSinCobrar(i.diferidoHastaMs, i.summarized);
  if (e === null) return i.periodEndMs;
  if (i.mpStatus !== "cancelled" && i.mpStatus !== "paused") {
    return i.periodEndMs;
  }
  return Math.min(i.periodEndMs ?? e, e);
}
