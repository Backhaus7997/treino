/**
 * motivos-terminal.ts: los motivos con los que un plan de `mp_plans` queda
 * `terminal`, en un archivo sin ninguna dependencia.
 *
 * Viven aparte de `reconcile.ts`, que es quien los escribe, porque los lee mas de
 * un modulo y `reconcile.ts` importa a casi todos: `diferir-primer-cobro.ts` los
 * necesita para decidir que planes pueden ser la evidencia de un pago, y un
 * import hacia `reconcile.ts` seria circular (`reconcile.ts` ya importa ese
 * archivo). Un modulo sin imports se puede importar desde cualquier lado.
 *
 * Por el mismo motivo viven aca dos lecturas de un plan que cruzan modulos:
 * `puedeSeguirCobrando` y el campo del arrepentimiento (`arrepentidoAtDe`). Las
 * dos vivian en `reconcile.ts`, que las re-exporta, y las lee tambien el
 * diferimiento del alumno.
 *
 * Son constantes y no literales sueltos porque hay codigo que COMPARA contra ellos
 * (`puedeSeguirCobrando`, el filtro de `planesARevisar`): escritos a mano en dos
 * lados, el dia que alguien cambie una redaccion el filtro deja de reconocer su
 * propio motivo y el bug es silencioso.
 *
 * ── Las tres clases de `terminal` ──
 *
 * `terminal: true` quiere decir "dejá de preguntar por este plan", no "este plan
 * ya no cobra", y confundirlas fue un bug real (ver `puedeSeguirCobrando`). Lo
 * que distingue una clase de otra es el motivo:
 *
 *   1. **Sin motivo: MP dio de baja la suscripcion** (`cancelled`). Lo escribe
 *      `reconcileSubscription`. El plan tuvo una suscripcion de verdad, que pudo o
 *      no haber cobrado.
 *
 *   2. **[MOTIVO_ABANDONO]: un checkout que nadie pago.** Lo escribe el barrido
 *      nocturno sobre un plan que a los 30 dias seguia sin NINGUNA suscripcion.
 *      Al marcarlo no habia nada que hubiera podido cobrar. El `init_point` no
 *      vence, asi que despues puede pagarse; el motivo no se borra (se escribe con
 *      `merge`), y por eso `puedeSeguirCobrando` lo trata distinto de los demas.
 *
 *   3. **[MOTIVO_REEMPLAZO]: lo reemplazo otro plan.** Lo escribe `darDeBajaUnPlan`
 *      cuando un plan nuevo queda confirmado, y SOLO si MP le encuentra al plan al
 *      menos una suscripcion (viva, que se da de baja, o ya cancelada): un plan sin
 *      ninguna no se marca terminal. Tuvo una suscripcion de verdad, y un plan que
 *      pago y despues se reemplazo sigue siendo la evidencia de ese pago.
 */

/** Ver la clase 2 del encabezado. */
export const MOTIVO_ABANDONO = "checkout abandonado";

/** Ver la clase 3 del encabezado. */
export const MOTIVO_REEMPLAZO = "reemplazado por otro plan";

/**
 * Este plan todavia PUEDE estar cobrandole al usuario, asi que hay que mirarlo.
 *
 * Vive aca y no en `reconcile.ts` (que la re-exporta) por el mismo motivo que los
 * motivos: la lee `diferir-primer-cobro.ts` para saber que planes del alumno
 * pueden tener una suscripcion viva, y un import hacia `reconcile.ts` seria
 * circular.
 *
 * `terminal` NO significa "muerto", y confundir las dos cosas fue un bug real de
 * la primera version de la baja: filtraba con `terminal === true` pelado y
 * dejaba afuera al checkout ABANDONADO que despues se pago.
 *
 * Esa poblacion existe y el repo la construyo a proposito. `esAbandonado` marca
 * terminal a los 30 dias, pero el `init_point` de un plan NO VENCE: el PF puede
 * encontrar la pestaña vieja al dia 35 y pagarla. `reconcile-my-checkout.ts` lo
 * documenta y lo rescata justamente por eso — su `planesDelPf` sigue
 * consultando los terminal CON motivo porque «un terminal con motivo es una
 * apuesta sobre el futuro, no un hecho».
 *
 * Con el filtro pelado, ese PF hacia upgrade y su plan viejo —vivo y
 * cobrando— quedaba fuera de la baja PARA SIEMPRE: el barrido tampoco lo
 * reconcilia, asi que ninguna corrida futura lo reintentaba. Cobro doble
 * permanente, justo en el caso que la baja de los reemplazados existe para
 * cerrar.
 *
 * Los otros dos terminal si son hechos y se saltean: una baja del PF (que MP ya
 * confirmo con `cancelled`) y una baja NUESTRA que MP acepto.
 */
export function puedeSeguirCobrando(datos: Record<string, unknown> | undefined): boolean {
  if (datos?.terminal !== true) return true;
  return datos?.terminalReason === MOTIVO_ABANDONO;
}

/**
 * Campo de `mp_plans/{planId}` con el momento (ms) en que la persona ejerció el
 * ARREPENTIMIENTO. Lo escribe `arrepentimiento-por-mail.ts`, y sólo después de
 * haber cortado la suscripción en Mercado Pago.
 *
 * Vive aca (y `reconcile.ts` lo re-exporta) porque tambien lo lee
 * `diferir-primer-cobro.ts`: un plan arrepentido se devolvio entero, asi que no
 * puede ser la evidencia de un pago.
 */
export const CAMPO_ARREPENTIDO = "arrepentidoAtMs";

/**
 * Cuándo se arrepintió, o `null` si este plan no pasó por ahí.
 *
 * ── Por qué el reconciliador tiene que saberlo ──
 *
 * Una baja común conserva el acceso hasta el fin del período pagado: es la
 * rama `cancelled` de `effectiveWeightLimit` / `athleteStatusDesde`, y es lo que
 * prometen los términos §7. El arrepentimiento es lo contrario: se devuelve TODO
 * lo pagado, así que los beneficios terminan en el acto.
 *
 * Cortar el acceso una vez no alcanza. Este reconciliador corre de nuevo con
 * cada evento de Mercado Pago y con el barrido de las 03:00, y cada vez volvería
 * a calcular «cancelado, con período hasta el día X» y a devolverle el acceso.
 * Por eso el corte es un dato del plan y no una escritura suelta.
 *
 * Sólo cuenta con `status === "cancelled"`: si MP dijera otra cosa la
 * suscripción sigue viva y cobrando, y ese caso es una cancelación que falló,
 * no un arrepentimiento.
 */
export function arrepentidoAtDe(datos: Record<string, unknown> | undefined): number | null {
  const v = datos?.[CAMPO_ARREPENTIDO];
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}
