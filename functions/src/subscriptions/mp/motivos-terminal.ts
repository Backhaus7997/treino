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
