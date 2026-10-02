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
 * donde N son los dias de CALENDARIO ARGENTINO que le quedan al periodo pago,
 * contados como los cuenta una persona: del 2/10 al 1/11 son 30. La idea es que MP
 * cobre por primera vez el dia en que vence lo que ya estaba pago. Que MP se
 * comporte asi NO esta medido: ver la seccion siguiente.
 *
 * ── Lo que se ASUME de MP y NO esta medido ──
 *
 * Cuando se escribio, nadie habia probado este flujo contra la API real. Lo que
 * sigue salio de los tipos del SDK oficial y del sentido comun, y el codigo esta
 * escrito para no depender de que se cumpla al pie de la letra:
 *
 *   a. Que la API acepte `free_trial` en dias dentro del `auto_recurring` de un
 *      plan (los tipos del SDK lo declaran). Si lo rechazara, el checkout de un PF
 *      con dias pagos fallaria: para eso esta el interruptor
 *      [DIFERIR_PRIMER_COBRO_ENABLED]. MEDIDO en produccion entre el 2026-10-01 y
 *      el 2026-10-02 (PRs #1290, #1291 y #1293): la API lo acepta, y el checkout
 *      de MP lo muestra como «¡Tenés N días gratis!». Es el unico de los tres que
 *      ya se midio: ese checkout se miro pero no se pago, asi que como reconcilia
 *      una suscripcion en prueba y cuando cae el primer cobro siguen sin medir.
 *   b. Que la prueba corra desde que el pagador AUTORIZA y que sean N corridas
 *      de 24 h. Con N igual a los dias de calendario argentino que faltan
 *      ([diasDePrueba]), el primer cobro caeria el MISMO dia argentino en que vence
 *      lo que el PF ya pago, siempre que el pagador autorice el mismo dia en que se
 *      abrio el checkout (pasada la medianoche argentina cae un dia de calendario
 *      despues), y a la hora del dia en que autorice: algunas horas antes o despues
 *      de la hora exacta de ese vencimiento, hasta casi un dia hacia cualquiera de
 *      los dos lados. Si MP los cuenta de otra forma (en su propio calendario,
 *      -04:00), podria caer mas lejos. Ninguna otra regla depende de que se cumpla
 *      al pie de la letra: el reconciliador deja holgura ([HOLGURA_PRUEBA_MS]), un
 *      plan con prueba se descarta como evidencia solo si le faltan mas de
 *      [ADELANTO_MAXIMO_DEL_COBRO_MS] para cobrar, y una prueba cancelada antes de
 *      su primer cobro conserva el acceso hasta E aunque ese cobro hubiera caido
 *      unas horas antes. Si MP ignorara o acortara la prueba, el reconciliador lo
 *      avisa con un warn ([cobroAntesDeLaPrueba], con su propio margen mas ancho,
 *      [MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS]): con el interruptor encendido, el
 *      primer PF real que vuelva a suscribirse con dias pagos es la medicion de
 *      este supuesto.
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
 *      cuando tiene pago el periodo. El alumno tiene su propia entrada
 *      (`decidirDiferimientoDeAlumno`), con la misma prueba y otra fuente de
 *      elegibilidad: ver el encabezado de esa seccion.
 *   2. AL RECONCILIAR (`aplicarPruebaDiferidaAlEstado` y
 *      `aplicarPruebaDiferidaAlPeriodo`): como se lee despues un plan que nacio
 *      con prueba, sea de PF o de alumno. Hace falta porque el link de un checkout
 *      no vence y MP no deja dar de baja un plan. Ver el encabezado de esa
 *      seccion.
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
import { ATHLETE_STATUSES } from "./map-status";
import {
  MOTIVO_ABANDONO,
  arrepentidoAtDe,
  puedeSeguirCobrando,
} from "./motivos-terminal";
import { numeroDeDia } from "./plazo-arrepentimiento";

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
 *
 * Es tambien lo que garantiza que [diasDePrueba] de al menos 1: con 24 h o mas por
 * delante, el vencimiento cae por lo menos un dia de calendario despues de hoy.
 * Con menos puede dar 0 (vence hoy mismo, en Argentina), y nuestro cliente de MP no
 * manda una prueba de 0 dias (`freeTrialDays` va de 1 a `MAX_FREE_TRIAL_DAYS`).
 */
export const MIN_DIFERIMIENTO_MS = DIA_MS;

/**
 * Cuantos planes del PF se le consultan a MP para comprobar un pago.
 *
 * Cada uno es una llamada en el camino del boton "ELEGIR PLAN", asi que el peor
 * caso tiene que estar acotado. El tope se aplica DESPUES de descartar los planes
 * que no pueden ser evidencia (ver [planesARevisar]): cortar antes deja afuera
 * justo al que pago.
 *
 * El alumno tiene su propio tope ([MAX_PLANES_DEL_ALUMNO_A_REVISAR]), y no corta
 * en silencio: con mas planes que eso, no difiere.
 */
export const MAX_PLANES_A_REVISAR = 3;

/**
 * Cuanto antes de E suponemos, como maximo, que puede caer el primer cobro de un
 * plan con prueba.
 *
 * Los dias de prueba son los de CALENDARIO ARGENTINO (ver [diasDePrueba]), asi que
 * el primer cobro caeria el mismo dia argentino que E pero a la hora en que se
 * autorizo: puede ser hasta un dia, menos un instante, ANTES de la hora exacta de E
 * (hoy a las 00:01 y E a las 23:59 de ese dia). Este margen es exactamente ese peor
 * caso, y no deja holgura para nada mas: si MP cuenta los dias en su propio
 * calendario (-04:00, no esta medido), el cobro podria caer algo mas lejos.
 *
 * Se usa para dos cosas, las dos del lado del modelo:
 *
 *   - decidir que un plan con prueba TODAVIA NO PUDO COBRAR (ver [planesARevisar]);
 *   - reconocer que el fin de una prueba cancelada que cae a menos de esto antes de
 *     E es su primer cobro programado y no una fecha anterior a E (ver
 *     [aplicarPruebaDiferidaAlPeriodo]).
 *
 * El aviso de un cobro antes de tiempo NO lo usa: tiene su propio margen, mas ancho
 * ([MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS]). Es un margen, no una garantia.
 */
export const ADELANTO_MAXIMO_DEL_COBRO_MS = DIA_MS;

/**
 * Cuanto antes de E tiene que haber cobrado un plan con prueba para que el
 * reconciliador avise de un cobro antes de tiempo ([cobroAntesDeLaPrueba]).
 *
 * Es mas ancho que [ADELANTO_MAXIMO_DEL_COBRO_MS] a proposito. Ese es el peor caso
 * del modelo, y un cobro legitimo puede quedar a un milisegundo de el; si ademas MP
 * cuenta los dias en su propio calendario (-04:00, no esta medido), el cobro puede
 * caer todavia un dia de calendario mas temprano. Un aviso falso no cuesta plata,
 * pero ensucia el log y le quita credibilidad a la unica medicion del supuesto
 * central: lo que tiene que avisar es un cobro que ningun calendario explica, el de
 * una prueba que MP ignoro o acorto y cobro al autorizar, dias o semanas antes de E.
 *
 * El costo de ser ancho es que no avisa de un cobro anticipado cuando faltan menos
 * de dos dias para E. Es el lado barato de equivocarse: la medicion es el primer PF
 * real con un periodo largo por delante.
 */
export const MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS = 2 * DIA_MS;

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
 *      diferido (`diferidoHastaMs` = E) no cobra antes de E menos el adelanto que
 *      suponemos como maximo ([ADELANTO_MAXIMO_DEL_COBRO_MS]: con dias de calendario
 *      el cobro puede caer hasta un dia antes de la hora exacta de E, no esta
 *      medido).
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
 * Cuantos dias de prueba hay que mandarle a MP: los dias de CALENDARIO ARGENTINO
 * entre hoy y el dia en que vence lo que el PF ya pago. Es el dia argentino de
 * [diferidoHastaMs] menos el de [nowMs].
 *
 * El dia argentino sale de `numeroDeDia` (`plazo-arrepentimiento.ts`), la misma
 * cuenta sin `Intl` que ya usa el plazo de arrepentimiento: un UTC-3 fijo, que no
 * depende de los datos de zona horaria ni del locale del runtime. Es UNA sola
 * definicion de "dia argentino" para las dos reglas.
 *
 * ── Por que calendario y no el tiempo exacto que falta ──
 *
 * La primera version hacia `ceil(tiempo restante / 24 h)`, y le sumaba un dia a
 * cualquiera con horas sobrantes. Un caso real: un plan pago hasta el 1/11 a las
 * 11:47, y el checkout abierto el 2/10 a las 09:30. Faltaban 30 dias y 2 horas, el
 * `ceil` daba 31, MP mostraba "31 dias gratis" y el primer cobro caia el 2/11.
 * Nadie cuenta asi: del 2/10 al 1/11 son 30 dias, y desde el 8/10 serian 24. Lo
 * que el PF espera ver, y lo que se le explica, son dias de calendario.
 *
 * ── Que se espera de MP (NO esta medido) ──
 *
 * Si MP cuenta N corridas de 24 h desde que el pagador AUTORIZA, el primer cobro
 * cae en `autorizacion + N * 24 h`. Con N de calendario, eso es el MISMO dia
 * argentino en que vence el periodo (siempre que el pagador autorice el mismo dia
 * en que se abrio el checkout), a la hora del dia en que autorizo: puede ser
 * algunas horas antes o despues de la hora exacta de E, hasta casi un dia hacia
 * cualquiera de los dos lados. Para que 24 h sean siempre un dia de calendario hace
 * falta que Argentina no tenga horario de verano, y no lo tiene desde 2009 (es el
 * mismo supuesto de `numeroDeDia`).
 *
 * Si MP los cuenta de otra forma (en su propio calendario, -04:00), no lo sabemos:
 * ver "Lo que se ASUME de MP".
 *
 * ── Lo que garantiza ──
 *
 * Con [MIN_DIFERIMIENTO_MS] o mas por delante da AL MENOS 1: sumarle 24 h a un
 * instante corre su fecha argentina exactamente un dia. Con menos puede dar 0 (vence
 * hoy mismo), que el cliente de MP rechaza; por eso `decidirDiferimiento` no
 * difiere por debajo de ese minimo.
 *
 * Una entrada que no es una fecha da NaN o infinito, y una absurda da un numero
 * fuera de rango: el cliente de MP lo rechaza (`freeTrialDays` es un entero de 1 a
 * `MAX_FREE_TRIAL_DAYS`) antes de salir a la red, como cualquier otra entrada
 * invalida.
 *
 * Vive aca y la llama `abrir-checkout.ts`: los dias salen de UN solo lugar, a
 * partir de `diferidoHastaMs` y del reloj del request.
 */
export function diasDePrueba(diferidoHastaMs: number, nowMs: number): number {
  return numeroDeDia(diferidoHastaMs) - numeroDeDia(nowMs);
}

/**
 * Por que NO se difiere. Va al log para poder explicar un cobro en el acto.
 *
 * Los tres ultimos son solo del alumno ([decidirDiferimientoDeAlumno]).
 */
export type MotivoSinDiferir =
  | "deshabilitado"
  | "sin-suscripcion"
  | "estado-degradado"
  | "no-esta-cancelada"
  | "otro-tier"
  | "sin-fecha-de-fin"
  | "queda-menos-de-un-dia"
  | "sin-pago-comprobado"
  | "pago-vence-pronto"
  | "sin-acceso-vigente"
  | "demasiados-planes"
  | "sin-respuesta-de-mp";

export type Diferimiento =
  | { diferir: false; motivo: MotivoSinDiferir }
  | {
      diferir: true;
      /**
       * Hasta cuando esta pago el periodo, en ms. Es el dia (argentino) en el que se
       * busca que caiga el primer cobro (ver [diasDePrueba] por lo que no esta
       * medido).
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
// El alumno: la misma decision, con la elegibilidad leida de MP.
// ---------------------------------------------------------------------------
//
// El alumno que se da de baja tambien conserva el acceso hasta el fin de lo que
// pago (`athleteStatusDesde`, rama `cancelled`), y si vuelve a suscribirse antes
// de esa fecha paga dos veces los mismos dias. Se cierra con la MISMA prueba
// (`free_trial`) y, al reconciliar, con las MISMAS reglas de la otra mitad de este
// archivo. Lo que no se puede copiar del PF es de donde sale la elegibilidad:
//
//   - `users/{uid}.athleteSubscription` es `{status}` y nada mas, a proposito (ver
//     `escribirSuscripcionDeAlumno` en `reconcile.ts`), con tres valores: `active`,
//     `grace` y `expired`. No existe `cancelled`: un alumno dado de baja con dias
//     pagos se lee `active`, igual que uno que paga. Tampoco hay tier ni fecha. El
//     documento sirve para descartar barato, pero no alcanza para decidir.
//   - La fecha vive en cada plan: `mp_plans/{planId}.currentPeriodEnd`. Que un plan
//     NO la tenga no prueba que nunca tuvo una suscripcion: el reconciliador no la
//     escribe si MP no manda `next_payment_date` en una suscripcion viva, ni en un
//     link diferido pagado tarde (la guarda de `pending` corta antes).
//   - Un plan de alumno dado de baja NO es `terminal` mientras le queden dias (el
//     barrido lo tiene que seguir mirando para apagarle el derecho al vencer). El
//     filtro de evidencia del PF (`terminal === true`) dejaria afuera justo a ese.
//
// Por eso "esta dado de baja" se le pregunta a MP, plan por plan y en el mismo
// pedido: se consultan los planes del alumno que todavia pueden cobrar, tengan o no
// fecha, y se difiere solo si ninguno tiene una suscripcion viva. Una viva es
// alguien que ya paga: diferirle un plan nuevo le sumaria un segundo cobro en E. El
// PF tiene una red para eso, el alumno no: cuando un plan nuevo confirma,
// `darDeBajaLosReemplazados` da de baja los viejos, pero corre solo en la rama del
// PF del reconciliador. Por eso aca no hay atajo del doble click (no le preguntaria
// nada a MP), y por eso la decision tambien levanta la guarda del mismo ciclo en
// `create-athlete-preapproval.ts`.
//
// ── UNA sola pasada por MP, para dos preguntas ──
//
// El callable le hace al alumno dos preguntas sobre las mismas suscripciones de MP:
// «¿alguna sigue cobrando?» (si es asi, NO se abre otro checkout: es la mitad
// temporal del cobro doble, [consultarPlanesDelAlumno]) y, si ninguna cobra, «¿hay
// un cobro real que respalde dias pagos?» ([decidirDiferimientoDeAlumno]). Las dos
// leen el mismo `searchPreapprovalsByPlan` de los mismos planes, en el mismo
// pedido, asi que se contesta UNA vez por plan: la pasada recorre en serie todos los
// planes que pueden cobrar, corta en el primero vivo y deja lo que MP contesto en un
// mapa; la decision del diferimiento lee de ese mapa y no sale a la red.
//
// «Viva» no significa lo mismo en las dos, a proposito ([mpSigueCobrando] frente al
// `!== "cancelled"` de abajo). Para bloquear, una suscripcion `pending` NO cobra
// todavia y bloquearla le cerraria el reintento del checkout que dejo a medias. Para
// diferir, se pide mas: ante la duda de si ya paga, se cobra en el acto como antes.
//
// El checkout abandonado (terminal por [MOTIVO_ABANDONO]) sin fecha no puede ser
// evidencia de un pago: cuando el barrido lo cerro no tenia ninguna suscripcion, y
// si alguien lo pagara despues sin que el reconciliador lo viera, tampoco lo veria
// el PF. Pero SI se consulta, en la pasada ([consultarPlanesDelAlumno]) y de nuevo
// al decidir, para saber si esta vivo: lo que MP devuelva ahi frena el diferimiento
// igual que en cualquier otro plan (una `pending` que se autorice despues cobraria
// desde E junto con el plan nuevo).

/**
 * Cuantos planes del ALUMNO se consideran, como maximo, para decidir el
 * diferimiento. Con mas, no se difiere (se cobra en el acto, como antes) y se avisa.
 *
 * Mas ancho que [MAX_PLANES_A_REVISAR] porque el alumno no puede filtrar antes por
 * `terminal` como el PF: entran tambien sus checkouts sin pagar de los ultimos 30
 * dias. Nacio como tope de llamadas en el camino del boton (en serie, porque en
 * paralelo MP contesta 429). Hoy esas llamadas ya las hizo
 * [consultarPlanesDelAlumno], que mira todos los planes que pueden cobrar para el
 * bloqueo, asi que el tope solo acota la decision: con tantos planes, lo seguro es
 * no sumar una prueba.
 */
export const MAX_PLANES_DEL_ALUMNO_A_REVISAR = 5;

/** `unknown` → ms si tiene forma de Timestamp y da un numero finito, si no `null`. */
function msDeTimestamp(v: unknown): number | null {
  const t = v as { toMillis?: unknown } | null | undefined;
  if (t == null || typeof t.toMillis !== "function") return null;
  const ms = (t.toMillis as () => number)();
  return Number.isFinite(ms) ? ms : null;
}

/** Un plan del alumno que puede tener una suscripcion viva, o probar un pago. */
export interface PlanDelAlumnoARevisar {
  id: string;
  /**
   * `currentPeriodEnd` del plan, en ms: hasta cuando le da acceso ese plan. `null`
   * si no tiene: un checkout que nadie pago todavia, o uno cuya suscripcion el
   * reconciliador vio sin fecha (ver el encabezado de esta seccion).
   */
  finMs: number | null;
  /**
   * Si el REGISTRO del plan le permite ser la evidencia de un pago (lo que diga
   * MP se mira despues). Ver [planesDelAlumnoARevisar].
   */
  puedeSerEvidencia: boolean;
}

/**
 * Los planes del alumno que hay que consultarle a MP, del mas nuevo al mas viejo.
 *
 * Son los de alumno (`producto === "athlete"`; un plan sin el campo es de PF, ver
 * el default de `lookupPlan`) que todavia pueden cobrar (`puedeSeguirCobrando`),
 * TENGAN O NO fecha: que no la tengan no prueba que no haya una suscripcion viva
 * (ver el encabezado). La unica excepcion es el checkout abandonado sin fecha, que
 * cuando se cerro no tenia ninguna: no entra aca porque no puede ser evidencia de
 * un pago, pero [decidirDiferimientoDeAlumno] igual lo consulta para saber si esta
 * vivo.
 *
 * Entran los checkouts sin pagar de los ultimos 30 dias (despues los cierra el
 * barrido): MP contesta que no tienen ninguna suscripcion, y eso ya es la
 * respuesta. Se devuelven TODOS; el tope lo aplica [decidirDiferimientoDeAlumno],
 * que con mas que eso no difiere: cortar en silencio podria dejar afuera justo a la
 * suscripcion que todavia cobra.
 *
 * `puedeSerEvidencia` descarta lo que no puede probar un pago por mas que MP
 * muestre un cobro:
 *
 *   - **Un plan sin fecha**: no hay contra que acotar lo que cubre ese cobro.
 *   - **Un plan arrepentido** (`arrepentidoAtDe`): se devolvio todo lo pagado. El
 *     reconciliador lo marca `terminal` apenas lo procesa, pero si esa corrida
 *     fallo, el plan sigue aca con su fecha.
 *   - **Un checkout abandonado que despues se pago** ([MOTIVO_ABANDONO]): mismo
 *     criterio que el PF (ver [planesARevisar]).
 *   - **Un plan con prueba que todavia no pudo cobrar**: el mismo filtro 3 del PF.
 *
 * Todos se siguen consultando para saber si estan vivos: lo que no prueba un pago
 * igual puede estar cobrando.
 */
export function planesDelAlumnoARevisar(
  planes: PlanDeLaCuenta[],
  nowMs: number,
): PlanDelAlumnoARevisar[] {
  return planes
    .filter(({ data }) => data.producto === "athlete" && puedeSeguirCobrando(data))
    .map(({ id, data }) => {
      const finMs = msDeTimestamp(data.currentPeriodEnd);
      const abandonado = data.terminalReason === MOTIVO_ABANDONO;
      // Cerrado sin ninguna suscripcion, y nadie le vio una despues.
      if (abandonado && finMs === null) return null;

      const e = data.diferidoHastaMs;
      const pruebaSinCobrar =
        typeof e === "number" &&
        Number.isFinite(e) &&
        e > nowMs + ADELANTO_MAXIMO_DEL_COBRO_MS;
      const puedeSerEvidencia =
        finMs !== null &&
        arrepentidoAtDe(data) === null &&
        !abandonado &&
        !pruebaSinCobrar;

      return { id, finMs, puedeSerEvidencia, creado: creadoEnMs(data.createdAt) };
    })
    .filter((p): p is PlanDelAlumnoARevisar & { creado: number } => p !== null)
    .sort((a, b) => b.creado - a.creado)
    .map(({ id, finMs, puedeSerEvidencia }) => ({ id, finMs, puedeSerEvidencia }));
}

/**
 * Si un estado de MP significa que la suscripcion todavia puede cobrar.
 *
 * Solo `cancelled` y `pending` quedan afuera:
 *
 *   - `authorized` cobra (incluye el `grace` nuestro: MP lo deja `authorized`
 *     mientras reintenta un cobro rebotado).
 *   - `paused` CUENTA, y es la decision menos obvia: la pausa no es una baja, el
 *     pagador la puede reactivar desde su cuenta de MP y el cobro vuelve solo.
 *     Dejarlo comprar otro plan ahi es armar el doble cobro con retraso. No lo
 *     deja encerrado: `cancelMySubscription` da de baja tambien las pausadas, o
 *     sea que siempre tiene salida.
 *   - un estado que no conocemos cuenta: entre un bloqueo de mas y un cobro
 *     doble en silencio, se elige lo primero.
 *   - `pending` no: todavia no autorizo, no hay cobro. Y bloquearlo le cerraria
 *     el reintento del checkout que dejo a medias.
 */
export function mpSigueCobrando(raw: unknown): boolean {
  return raw !== "cancelled" && raw !== "pending";
}

/** Lo que dejo [consultarPlanesDelAlumno]. */
export type ConsultaDeLosPlanesDelAlumno =
  | {
      /** Hay una suscripcion que MP TODAVIA cobra: no se abre otro checkout. */
      vivo: true;
      /** El primer plan donde se encontro. */
      planId: string;
    }
  | {
      /** Ninguna cobra. Lo que MP contesto por cada plan, para no volver a preguntar. */
      vivo: false;
      suscripciones: ReadonlyMap<string, MpPreapproval[]>;
    };

/**
 * La UNICA pasada por MP del checkout del alumno: le pregunta, plan por plan, por
 * las suscripciones de los planes que todavia pueden cobrar, y contesta dos cosas a
 * la vez. Ver "UNA sola pasada por MP" en el encabezado de esta seccion.
 *
 * ── Que planes ──
 *
 * Los de alumno (`producto === "athlete"`; un plan sin el campo es de PF) que
 * [puedeSeguirCobrando]. Los terminales de hecho (baja confirmada) se saltean para
 * no gastar una llamada; el checkout ABANDONADO NO, porque el `init_point` no vence
 * y se puede pagar tarde. Es un conjunto mas ancho que el de
 * [planesDelAlumnoARevisar] (que deja afuera al abandonado sin fecha): para BLOQUEAR
 * importa todo lo que pueda estar cobrando, para diferir solo lo que pueda probar un
 * pago. Quien decide el diferimiento filtra la evidencia de lo que esta pasada
 * deja, pero mira el estado de TODOS: ninguno de los planes consultados puede estar
 * vivo para que se difiera.
 *
 * ── Como ──
 *
 * SECUENCIAL y cortando en el primero que cobra, a proposito: MP contesta 429 y los
 * planes abandonados se quedan para siempre, asi que un `Promise.all` creceria con
 * el uso y un solo 429 trabaria al alumno (mismo criterio que
 * `cancel-my-subscription.ts`). Con el corte, solo importan los planes que
 * realmente se consultaron: si uno falla antes de encontrar uno vivo, no se puede
 * descartar el cobro.
 *
 * **Tira** si MP no contesta (o `leerSuscripciones` lo hace con un error): sin saber
 * si algo cobra no se puede descartar el doble cobro, y abrir el checkout igual
 * necesita a MP. Quien llama lo traduce a un error reintentable. `leerSuscripciones`
 * tiene que ser ESTRICTA (`searchPreapprovalsByPlan(id, {estricto: true})`): una
 * respuesta rota de MP no puede leerse como «no hay nada».
 */
export async function consultarPlanesDelAlumno(i: {
  planes: PlanDeLaCuenta[];
  leerSuscripciones: (planId: string) => Promise<MpPreapproval[]>;
}): Promise<ConsultaDeLosPlanesDelAlumno> {
  const suscripciones = new Map<string, MpPreapproval[]>();
  for (const { id, data } of i.planes) {
    if (data.producto !== "athlete" || !puedeSeguirCobrando(data)) continue;

    const subs = await i.leerSuscripciones(id);
    suscripciones.set(id, subs);
    if (subs.some((s) => mpSigueCobrando(s.status))) {
      return { vivo: true, planId: id };
    }
  }
  return { vivo: false, suscripciones };
}

export interface DecidirDiferimientoDeAlumnoInput {
  uid: string;
  /** `users/{uid}`, tal como salio de Firestore. Se lee `athleteSubscription`. */
  userData: Record<string, unknown> | undefined;
  nowMs: number;
  /**
   * TODOS los planes de MP de esta cuenta (`mp_plans where uid == uid`). Funcion y
   * no arreglo por lo mismo que en el PF: solo se llama si el alumno tiene acceso
   * pago hoy.
   */
  leerPlanes: () => Promise<PlanDeLaCuenta[]>;
  /**
   * Las suscripciones de MP detras de un plan (`searchPreapprovalsByPlan`). El
   * callable pasa una lectura de lo que [consultarPlanesDelAlumno] ya contesto en
   * este pedido, para no preguntarle dos veces a MP lo mismo; quien la llame
   * suelta, como los tests, hace la consulta de verdad.
   */
  leerSuscripciones: (planId: string) => Promise<MpPreapproval[]>;
  /** El interruptor [DIFERIR_PRIMER_COBRO_ENABLED]: es el mismo para los dos. */
  habilitado?: boolean;
}

/**
 * Decide si el checkout que el alumno esta por abrir tiene que diferir su primer
 * cobro, y hasta cuando. Ver el encabezado de esta seccion.
 *
 * Se difiere SOLO si todo esto es cierto:
 *
 *   0. El interruptor [DIFERIR_PRIMER_COBRO_ENABLED] esta encendido.
 *   1. `athleteSubscription.status` es `active`. `grace` es una suscripcion viva con
 *      un cobro rebotado (MP reintenta); `expired`, que no le queda nada pago.
 *   2. Algun plan suyo que pueda probar un pago le da todavia al menos
 *      [MIN_DIFERIMIENTO_MS] de acceso.
 *   3. En ESTE pedido, MP contesto por cada plan suyo que puede cobrar sin ninguna
 *      suscripcion viva, y por cada plan con fecha con la suscripcion que tuvo. Un
 *      plan con fecha que vuelve vacio no se da por dado de baja: la busqueda de MP
 *      llega tarde a una suscripcion recien autorizada, y el cliente trata una
 *      respuesta rara como vacia.
 *   4. MP muestra un cobro real que lo respalda ([evidenciaDePago]).
 *
 * Vale para cualquier ciclo: el alumno tiene un solo plan, asi que pasar de
 * mensual a anual paga dos veces los mismos dias igual que volver al mismo.
 *
 * Por plan, el fin es el MENOR entre el fin del plan que pago y lo que cubre el cobro
 * de MP, como en el PF, y dentro de ese plan se toma el pago mas lejano. El
 * resultado es el MAYOR de esos fines entre todos los planes que pueden probar un
 * pago y muestran un cobro: el alumno ya tiene pago hasta ahi por el plan que mas
 * lejos llega, sea el mas nuevo o no. Un empate lo desempata el id del plan, para
 * no depender del orden de lectura.
 *
 * Sin atajo del doble click (ver el encabezado): un segundo toque vuelve a
 * verificar contra MP y, si nada cambio, llega a la MISMA fecha, que es lo que
 * `abrirCheckout` necesita para reusar el checkout abierto.
 *
 * Tira si no puede LEER los planes o las suscripciones: ver el encabezado del
 * archivo. Quien llama lo traduce a un error que el alumno pueda reintentar.
 */
export async function decidirDiferimientoDeAlumno(
  i: DecidirDiferimientoDeAlumnoInput,
): Promise<Diferimiento> {
  const { uid, nowMs } = i;

  const sinDiferir = (
    motivo: MotivoSinDiferir,
    extra: Record<string, unknown> = {},
  ): Diferimiento => {
    logger.info("mp/diferir-primer-cobro: se cobra en el acto", {
      uid,
      producto: "athlete",
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
  //
  // Casi todo checkout de alumno corta aca: el que nunca pago no tiene
  // `athleteSubscription`, y no le cuesta ni una lectura de mas.
  const sub = i.userData?.athleteSubscription;
  if (sub == null) return sinDiferir("sin-suscripcion");
  const status =
    typeof sub === "object" ? (sub as { status?: unknown }).status : undefined;
  if (
    typeof status !== "string" ||
    !(ATHLETE_STATUSES as readonly string[]).includes(status)
  ) {
    return sinDiferir("estado-degradado");
  }
  if (status === "expired") return sinDiferir("sin-acceso-vigente");
  if (status !== "active") return sinDiferir("no-esta-cancelada", { status });

  // Desde aca se lee, y un fallo TIRA (ver el encabezado del archivo).
  const enLaCuenta = await i.leerPlanes();
  const aConsultar = planesDelAlumnoARevisar(enLaCuenta, nowMs);
  const conDias = aConsultar.filter(
    (p) => p.finMs !== null && p.finMs - nowMs >= MIN_DIFERIMIENTO_MS,
  );
  const candidatos = conDias.filter((p) => p.puedeSerEvidencia);
  // Cuantos planes quedan en cada etapa: es lo que permite explicar despues por
  // que se cobro en el acto.
  const alcance = {
    planesEnLaCuenta: enLaCuenta.length,
    planesQueCobran: aConsultar.length,
    candidatos: candidatos.length,
  };

  // Las tres primeras no le preguntan nada a MP: sin un plan que pueda probar
  // dias pagos, no hay nada que diferir, este quien este vivo.
  if (aConsultar.every((p) => p.finMs === null)) {
    return sinDiferir("sin-fecha-de-fin", alcance);
  }
  if (conDias.length === 0) return sinDiferir("queda-menos-de-un-dia", alcance);
  if (candidatos.length === 0) return sinDiferir("sin-pago-comprobado", alcance);

  // El tope solo acota ESTA decision: la pasada ([consultarPlanesDelAlumno]) ya
  // consulto todos los planes que pueden cobrar, asi que no hay llamadas que
  // ahorrar. Con mas planes que el tope no se difiere y se cobra en el acto, como
  // antes: es la direccion segura (no se suma una prueba sobre una cuenta con tantos
  // planes que pueden cobrar). Es raro, y por eso ademas de explicarse, avisa.
  if (aConsultar.length > MAX_PLANES_DEL_ALUMNO_A_REVISAR) {
    logger.warn(
      "mp/diferir-primer-cobro: el alumno tiene mas planes que pueden cobrar " +
        "que los que se revisan, no se difiere",
      { uid, ...alcance, tope: MAX_PLANES_DEL_ALUMNO_A_REVISAR },
    );
    return sinDiferir("demasiados-planes", alcance);
  }

  const esCandidato = new Set(candidatos.map((p) => p.id));
  // El plan que mas lejos llega, y con que pago. Se evalua CADA candidato y gana el
  // de fin independiente mas lejano (ver abajo): quedarse con el primero que tenga
  // evidencia, que es el mas nuevo, deja al alumno pagando de nuevo los dias que ya
  // cubria otro plan mas largo (un anual cancelado vigente hasta enero y un mensual
  // posterior vigente hasta septiembre: difiere hasta enero, no hasta septiembre).
  let pago: EvidenciaDePago | null = null;
  let conPago: PlanDelAlumnoARevisar | null = null;
  let finDelMejor = -Infinity;
  for (const plan of aConsultar) {
    const subs = await i.leerSuscripciones(plan.id);

    // Viva es todo lo que no sea `cancelled`, incluido un estado que no
    // conocemos: es el criterio de `sigueViva` (`reconcile.ts`). Ante la duda de
    // si el alumno ya paga, se cobra en el acto como antes, nunca se le suma un
    // segundo cobro en E.
    if (subs.some((s) => s.status !== "cancelled")) {
      return sinDiferir("no-esta-cancelada", { ...alcance, planVivo: plan.id });
    }

    // Un plan con fecha tuvo una suscripcion: si MP no devuelve ninguna, no
    // contesto por la que sabemos que existe. Puede ser la demora de su busqueda
    // con una recien autorizada, o una respuesta rara que el cliente convierte en
    // `[]` ("no hay nada"). Para el PF eso es "sin evidencia" y cobra en el acto;
    // aca seria dar por dada de baja a una que quiza cobra.
    if (plan.finMs !== null && subs.length === 0) {
      return sinDiferir("sin-respuesta-de-mp", { ...alcance, planSinRespuesta: plan.id });
    }

    if (esCandidato.has(plan.id) && plan.finMs !== null) {
      const evidencias = subs
        .map(evidenciaDePago)
        .filter((e): e is EvidenciaDePago => e !== null);
      if (evidencias.length > 0) {
        // El pago mas lejano de ese plan.
        const delPlan = evidencias.reduce(
          (mejor, e) => (e.hastaMs > mejor.hastaMs ? e : mejor),
        );
        // El fin de ESTE plan, calculado como el del resultado: el menor entre su
        // fecha de fin y lo que cubre su cobro. Gana el mas lejano; en un empate,
        // el id menor, para que el resultado no dependa del orden de lectura.
        const fin = Math.min(plan.finMs, delPlan.hastaMs);
        if (
          fin > finDelMejor ||
          (fin === finDelMejor && conPago !== null && plan.id < conPago.id)
        ) {
          finDelMejor = fin;
          pago = delPlan;
          conPago = plan;
        }
      }
    }
  }

  // Los planes que pueden cobrar y no entraron a `aConsultar` (el checkout
  // abandonado sin fecha) no prueban ningun pago, pero se miran igual para saber si
  // estan vivos: cualquier estado que no sea `cancelled` (una `pending` que se
  // autorice despues) frena el diferimiento, como en el resto de los planes.
  const consultados = new Set(aConsultar.map((p) => p.id));
  for (const { id, data } of enLaCuenta) {
    if (consultados.has(id)) continue;
    if (data.producto !== "athlete" || !puedeSeguirCobrando(data)) continue;
    const subs = await i.leerSuscripciones(id);
    if (subs.some((s) => s.status !== "cancelled")) {
      return sinDiferir("no-esta-cancelada", {
        ...alcance,
        planVivo: id,
        abandonadoSinFecha: true,
      });
    }
  }

  if (pago === null || conPago === null || conPago.finMs === null) {
    return sinDiferir("sin-pago-comprobado", alcance);
  }

  if (pago.fuente === "alta") {
    // El mismo parche que en el PF, y grita por lo mismo.
    logger.warn(
      "mp/diferir-primer-cobro: MP no mando last_charged_date, el pago se " +
        "reconstruye desde el alta",
      { uid, producto: "athlete", planConPago: conPago.id },
    );
  }

  const diferidoHastaMs = finDelMejor;
  if (diferidoHastaMs - nowMs < MIN_DIFERIMIENTO_MS) {
    return sinDiferir("pago-vence-pronto", {
      ...alcance,
      finDePeriodoIso: new Date(conPago.finMs).toISOString(),
      pagadoHastaIso: new Date(pago.hastaMs).toISOString(),
      fuenteDelPago: pago.fuente,
    });
  }

  logger.info("mp/diferir-primer-cobro: se difiere el primer cobro", {
    uid,
    producto: "athlete",
    ...alcance,
    planConPago: conPago.id,
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
//      el PF pago hasta E (a traves del plan anterior): el ultimo le regala un mes
//      que nunca se cobro, y los otros pueden pasarse de E o quedarse cortos. Si
//      MP manda `next_payment_date` en una prueba cancelada (no esta medido) seria
//      el primer cobro que no ocurrio: el mismo dia argentino que E, pero hasta
//      casi un dia ANTES o DESPUES de su hora exacta. Pasado de E se acota a E. Y
//      unas horas ANTES de E tambien vale E: cortarle el acceso en un cobro que
//      nunca ocurrio le saca horas de un periodo que ya pago (en el caso real, 2 h
//      12 min). Solo un fin MAS lejos de E que [ADELANTO_MAXIMO_DEL_COBRO_MS] se
//      respeta tal cual, porque ningun calendario lo explica.
//
// Lo que NO hacen: no dan de baja nada en MP. El pagador autorizo de buena fe, la
// baja es terminal, y una decision nuestra equivocada no se puede deshacer. Se
// limitan a decidir que escribimos: `subscription` para el PF, y para el alumno
// su `athleteSubscription` (que sale del estado y la fecha, `athleteStatusDesde`)
// y el `currentPeriodEnd` del plan. Las reglas son las mismas para los dos: lo que
// las motiva es como MP cobra una prueba, no quien la paga.

/**
 * Cuanto despues de abrir el checkout puede autorizar el pagador para que la
 * prueba que le calculamos siga valiendo.
 *
 * Los dias se contaron desde el momento en que se abrio el checkout. Asumimos que
 * MP los cuenta desde que el pagador AUTORIZA (no esta medido), asi que el primer
 * cobro caeria `autorizacion + dias`. Autorizando a las pocas horas la diferencia
 * es chica y entra en [HOLGURA_PRUEBA_MS] (si se autoriza pasada la medianoche
 * argentina, el cobro cae un dia de calendario despues del de E); autorizando
 * varios dias despues, el cobro se correria esos mismos dias y dejaria de ser el
 * que le corresponde.
 */
export const VENTANA_AUTORIZACION_MS = 24 * 60 * 60 * 1000;

/**
 * Cuanto despues de E se sigue tratando como "en prueba" a una suscripcion que
 * todavia no cobro.
 *
 * Bajo el supuesto de que MP cuenta N corridas de 24 h desde la autorizacion (no
 * esta medido), el primer cobro caeria el mismo dia argentino que E, hasta casi un
 * dia DESPUES de su hora exacta (por contar dias de calendario, ver
 * [diasDePrueba]), mas lo que tardo el pagador en autorizar (hasta
 * [VENTANA_AUTORIZACION_MS]), y MP puede demorarse en intentarlo. Tres dias
 * cubren eso con aire (el peor caso es E mas dos dias); pasados, un cobro
 * pendiente vuelve a leerse como `grace` y el aviso de "no pudimos cobrar" es
 * verdad.
 *
 * El cobro tambien puede caer ANTES de la hora exacta de E, hasta un dia
 * ([ADELANTO_MAXIMO_DEL_COBRO_MS]): no rompe nada, porque apenas hay un cobro
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
 * margen del aviso ([MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS]) para E.
 *
 * Quiere decir que MP IGNORO o ACORTO la prueba, y que el PF pago dos veces: el
 * periodo que ya tenia pago y el que acaba de cobrar el plan nuevo. Es la medicion
 * del supuesto (b) de "Lo que se ASUME de MP". El cobro ocurrio en algun momento
 * anterior o igual a `nowMs`, asi que si `nowMs` ya esta antes de E menos el
 * margen, el cobro cayo antes de lo que explica contar los dias de calendario
 * argentino (como mucho casi un dia antes de la hora exacta de E, ver
 * [ADELANTO_MAXIMO_DEL_COBRO_MS]) y con aire de sobra para el calendario propio de
 * MP: ver por que el margen es mas ancho que ese adelanto.
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
  return i.nowMs < e - MARGEN_DEL_AVISO_DE_COBRO_DOBLE_MS;
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
 * Solo toca una suscripcion que MP dice `cancelled` o `paused`. El PF pago hasta
 * E, a traves del plan anterior, y de ahi no pasa: lo que pase de E (el mes que la
 * cascada de `resolverFinDePeriodo` deriva del alta) es un periodo que nunca se
 * cobro. Pero tampoco puede quedarse corto, porque E es lo que SI pago:
 *
 *   - Un fin pasado de E, o ninguno por ningun camino: E.
 *   - Un fin a menos de [ADELANTO_MAXIMO_DEL_COBRO_MS] antes de E: tambien E. Ese
 *     fin es el primer cobro programado de la prueba, que cae el mismo dia
 *     argentino que E pero a la hora en que se autorizo, hasta casi un dia antes de
 *     su hora exacta (en el caso real, 2 h 12 min). No es una fecha anterior a E:
 *     es un cobro que no ocurrio, y cortar el acceso ahi le saca horas de un
 *     periodo que ya pago.
 *   - Un fin MAS lejos que eso antes de E: se respeta tal cual. Ningun calendario
 *     lo explica, y ante lo que no se entiende no se estira.
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
  // Nunca mas alla de E; sin fin, E.
  const tope = Math.min(i.periodEndMs ?? e, e);
  // Pero un fin que cae poco antes de E es el primer cobro de la prueba, no una
  // fecha menor: el PF pago hasta E.
  return tope >= e - ADELANTO_MAXIMO_DEL_COBRO_MS ? e : tope;
}
