/**
 * plazo-arrepentimiento.ts — ¿este pedido de arrepentimiento llega a tiempo?
 *
 * PURO: sin Firestore, sin red, con el reloj por parámetro. Es la decisión que
 * dice si hay plata que devolver, así que es la que tiene que poder probarse
 * con fechas concretas.
 *
 * ── La regla, y de dónde sale ──
 *
 * `docs/legal/terminos-suscripcion.md` §6: 10 días corridos desde la
 * contratación, art. 34 de la Ley 24.240. **«Si el último día del plazo cae en
 * un día inhábil, el plazo se extiende hasta el primer día hábil siguiente»**, y
 * el derecho es irrenunciable.
 *
 * ── La fecha que cuenta ──
 *
 * La de contratación que sale de NUESTRO registro con Mercado Pago (la fecha en
 * que el pagador autorizó la suscripción), nunca la que escribe la persona en
 * el formulario. El formulario deja declarar una fecha cualquiera: con ella, un
 * pedido de hace tres meses entra como «de ayer».
 *
 * ── Tres respuestas, no dos ──
 *
 *   - `dentro`    — llega a tiempo. Se puede actuar solo.
 *   - `a-revisar` — pasó el último día, pero por poco. **No se rechaza solo.**
 *   - `fuera`     — pasó por mucho. Se rechaza.
 *
 * El `a-revisar` existe por los feriados. Los fines de semana se calculan acá;
 * los feriados NO: un calendario de feriados argentinos (con los «puente» que se
 * deciden por decreto) es un dato que se pudre en silencio, y el modo de falla
 * —rechazarle a alguien un derecho irrenunciable porque el último día era
 * feriado— es exactamente el que este módulo no puede tener. Así que la franja
 * en la que un feriado PODRÍA haber corrido el plazo la resuelve una persona.
 *
 * ── Los días se cuentan en hora de Argentina ──
 *
 * Argentina es UTC-3 todo el año (no tiene horario de verano). Alguien que
 * contrató a las 22:00 de un martes no contrató «el miércoles» por ser UTC.
 * El día de contratación no se cuenta: el plazo corre desde el día siguiente y
 * vence al terminar el décimo.
 */

/** UTC-3, fijo: Argentina no tiene horario de verano. */
const ART_OFFSET_MS = 3 * 60 * 60 * 1000;
const DIA_MS = 24 * 60 * 60 * 1000;

/** Los 10 días corridos de la Ley 24.240 art. 34. */
export const PLAZO_DIAS = 10;

/**
 * Cuántos días después del último día se sigue mirando a mano.
 *
 * Cuatro: cubre un fin de semana largo con feriado puente (jueves y viernes
 * feriados más el fin de semana), que es lo más largo que puede correr un plazo
 * por días inhábiles.
 */
export const DIAS_DE_DUDA = 4;

export type EstadoDelPlazo = "dentro" | "a-revisar" | "fuera";

export interface Plazo {
  estado: EstadoDelPlazo;
  /**
   * Inicio (en ms UTC) del ÚLTIMO día del plazo, ya corrido por fin de semana.
   * `null` si no se pudo calcular. Formateado en hora de Argentina es la fecha
   * que hay que mostrarle a la persona.
   */
  ultimoDiaMs: number | null;
  /** Días corridos entre el día de contratación y el de hoy (hora Argentina). */
  diasTranscurridos: number | null;
}

/**
 * Número de día (desde 1970-01-01) en hora de Argentina.
 *
 * Es la definición de «día argentino» SIN `Intl` del repo: aritmética sobre un
 * UTC-3 fijo, que no depende de los datos de zona horaria ni del locale del
 * runtime. La usan este plazo y la cuenta de los días de prueba de un plan
 * diferido (`diasDePrueba`, en `diferir-primer-cobro.ts`): las dos tienen que
 * coincidir en qué día es, y con una sola función no pueden divergir.
 */
export function numeroDeDia(ms: number): number {
  return Math.floor((ms - ART_OFFSET_MS) / DIA_MS);
}

/** Medianoche de Argentina del día número `dia`, en ms UTC. */
function inicioDelDia(dia: number): number {
  return dia * DIA_MS + ART_OFFSET_MS;
}

/** 0 = domingo … 6 = sábado. El 1970-01-01 fue jueves. */
function diaDeLaSemana(dia: number): number {
  return (((dia + 4) % 7) + 7) % 7;
}

/**
 * Evalúa el plazo.
 *
 * @param contratoMs - Cuándo se contrató, en ms. `null` si no se sabe.
 * @param nowMs      - Reloj, inyectado.
 *
 * Sin fecha de contratación NO se decide: `a-revisar`. Ni aprobar ni rechazar a
 * ciegas — lo primero devuelve plata que no sabemos si corresponde, y lo
 * segundo le quita un derecho irrenunciable por un dato que nos faltó a nosotros.
 */
export function evaluarPlazo(contratoMs: number | null, nowMs: number): Plazo {
  if (contratoMs === null || !Number.isFinite(contratoMs)) {
    return { estado: "a-revisar", ultimoDiaMs: null, diasTranscurridos: null };
  }

  const diaContrato = numeroDeDia(contratoMs);
  const hoy = numeroDeDia(nowMs);

  let ultimoDia = diaContrato + PLAZO_DIAS;
  // Fin de semana: el plazo se extiende al lunes.
  const semana = diaDeLaSemana(ultimoDia);
  if (semana === 6) ultimoDia += 2;
  else if (semana === 0) ultimoDia += 1;

  const estado: EstadoDelPlazo =
    hoy <= ultimoDia ? "dentro" : hoy <= ultimoDia + DIAS_DE_DUDA ? "a-revisar" : "fuera";

  return {
    estado,
    ultimoDiaMs: inicioDelDia(ultimoDia),
    diasTranscurridos: hoy - diaContrato,
  };
}
