/**
 * notifyDailyReminders — el PLANIFICADOR de los recordatorios diarios del atleta.
 *
 * Corre todos los días a las 06:00 ART y NO manda nada. Para cada atleta decide
 * si hoy le toca un recordatorio, de qué tipo y a QUÉ HORA, y lo deja escrito en
 * `users/{uid}.dailyReminderPlan`. Quien lo manda es `dispatchDailyReminders`
 * (`dispatch-daily-reminders.ts`), que corre cada 15 minutos y despacha los
 * planes que ya vencieron. COMO MÁXIMO UN push por atleta por día.
 *
 * Todo se calcula en el servidor: el cliente no participa, así que un teléfono
 * apagado, una app sin abrir o una versión vieja no cambian nada.
 *
 * ─── Por qué dos funciones y no una ────────────────────────────────────────
 *
 * El recordatorio sale a la hora en que ESE atleta suele entrenar (ver «A qué
 * hora sale cada uno»), no a una hora fija para todos. Una sola corrida diaria
 * no puede hacerlo: la hora cambia por atleta. Planificar una vez (el escaneo de
 * 9 semanas es la parte cara) y despachar cada 15 minutos (barato: sólo lee los
 * planes de hoy) separa el costo del cálculo del costo de la puntualidad.
 *
 * El despachante es además quien sabe lo que el planificador no puede: lo que
 * pasó DESPUÉS de las 06:00. Si el atleta ya arrancó una sesión, no manda nada.
 *
 * ─── Los tres recordatorios, en orden de prioridad ─────────────────────────
 *
 * 1. `streak-at-risk` — "Hoy o se corta 🔥". El atleta tiene una racha semanal
 *    de 1 semana o más (semanas cumplidas consecutivas ANTERIORES a la actual),
 *    la semana en curso no cumplió, y le faltan exactamente tantos
 *    entrenamientos como días le quedan contando hoy (lunes=7 … domingo=1):
 *    si hoy no entrena, matemáticamente ya no llega. Se excluye a quien ya
 *    completó una sesión hoy.
 *
 * 2. `training-due` — "Hoy toca entrenar 💪". La MISMA condición «al límite»
 *    (la semana en curso no cumplió, faltan exactamente tantos como días quedan
 *    contando hoy, no entrenó hoy), pero para quien NO tiene racha: la semana
 *    anterior tampoco cumplió. No hay nada que sostener, sólo un objetivo que
 *    todavía se alcanza si arranca hoy.
 *
 *    El 1 y el 2 son EXCLUYENTES y los separa una sola pregunta, la racha: con 1
 *    semana o más sale `streak-at-risk`, con 0 sale `training-due`. Dado que
 *    está al límite no hay un tercer caso: ningún atleta califica a los dos, y
 *    ninguno queda al límite sin tipo. Es la misma cuenta (`weekLimitPlanFor`):
 *    no hay dos reglas del «límite» que puedan diferir.
 *
 * 3. `comeback-reminder` — "Te extrañamos en el gym 💪". Su última sesión que
 *    cuenta tiene entre 4 y 17 días ART calendario, y no se le mandó este tipo
 *    en los últimos 7 días (se reintenta recién al día 7, no al 6). En la
 *    práctica son DOS avisos por período de inactividad —el día 4 y el día 11—
 *    y después silencio hasta que vuelva a entrenar (ver abajo).
 *
 * El 1 y el 2 le ganan al 3: si califica a cualquiera de los dos, el plan es ése
 * y NO se planifica comeback ese día. No se escribe `lastComebackReminderDate`,
 * así que el cooldown de 7 días no corre y el «volvé a entrenar» queda
 * disponible mientras el atleta siga en la ventana [4, 17] (al día siguiente, si
 * ya no está al límite). Hay UN plan por atleta por día: un plan nuevo
 * reemplaza al anterior.
 *
 * ─── El "volvé a entrenar" tiene TOPE: dos avisos y silencio ───────────────
 *
 * Decisión de producto (2026-10-15, #1449): a quien deja de entrenar le llegan
 * a lo sumo DOS avisos —día 4 y día 11 sin entrenar— y después nada hasta que
 * vuelva a completar una sesión. Más avisos a alguien que no responde es la
 * forma más rápida de que apague TODAS las notificaciones de TREINO (chat y
 * turnos incluidos) o desinstale. No perseguimos a los churneados.
 *
 * El tope no guarda estado: sale de la ventana [COMEBACK_MIN_DAYS,
 * COMEBACK_MAX_DAYS] = [4, 17] combinada con el cooldown de 7 días. En 14 días
 * de ventana no entran tres envíos separados por 7 (harían falta 4, 11 y 18),
 * así que el máximo es dos aunque el primero salga tarde (un día de scheduler
 * caído, un opt-out que se prendió después). Al volver a entrenar, la cuenta
 * arranca desde la nueva última sesión.
 *
 * El cooldown se evalúa al PLANIFICAR y se vuelve a verificar al RESERVAR (en el
 * despachante), y `lastComebackReminderDate` se escribe cuando el push sale, no
 * cuando se planifica. Por eso un plan que no se despacha (el atleta entrenó, el
 * envío falló todo el día) no consume nada del tope: mañana se vuelve a evaluar
 * con la misma ventana.
 *
 * ─── A quién mira: el límite conocido del «hoy toca» ───────────────────────
 *
 * El planificador sólo ve a los atletas con AL MENOS UNA sesión que cuenta en la
 * ventana del escaneo (8 semanas + la actual). Quien nunca entrenó, o cuya
 * última sesión ya salió de la ventana, no aparece y no recibe `training-due`.
 * Es el alcance decidido, no un descuido: verlo exigiría recorrer `users` entero
 * en vez de las sesiones.
 *
 * Y el «hoy toca» es SÓLO para quien está en movimiento: entrenó hace menos de
 * COMEBACK_MIN_DAYS (4) días o ya entrenó esta semana. Al que no hizo nada esta
 * semana y lleva 4 o más sin entrenar lo maneja el comeback, con su tope de dos
 * y después silencio. Sin esa guarda, quien dejó de
 * entrenar recibía un «hoy toca» por semana —el día en que «faltan = quedan»—
 * durante ~8 semanas, mientras su última sesión siguiera en la ventana: el
 * churneado que #1449 decidió no perseguir. La guarda vive en `weekLimitPlanFor`
 * y, como condición necesaria barata, en el filtro del handler.
 *
 * ─── A qué hora sale cada uno ──────────────────────────────────────────────
 *
 * El horario habitual de entrenamiento se aprende de las sesiones del atleta
 * (`habitual-time.ts` tiene el algoritmo, la muestra de 12 y el desempate):
 *
 *   · Racha en riesgo y «hoy toca»: habitual + 60 minutos. Llega una hora
 *     después de cuando suele entrenar, o sea cuando "se colgó". Sin patrón
 *     claro: 18:00. Es la MISMA función (`streakSendMinute`) para los dos: son
 *     el mismo momento de la semana, el último en que todavía se llega.
 *   · Volver a entrenar: a la hora habitual. Sin patrón claro: 09:00.
 *   · Los tres, acotados a [08:00, 22:30]. El piso es 08:00 porque este
 *     planificador corre a las 06:00 y tiene que terminar de escribir los planes
 *     antes de que el primero venza.
 *
 * El horario NO se guarda: se recalcula en cada corrida con las sesiones que el
 * escaneo ya trajo, así que cuando el atleta cambia de hábito se adapta solo.
 * Esas sesiones son las de la ventana de 9 semanas, no el historial entero: quien
 * entrena pocas veces por semana puede tener menos de 12 ahí, y la muestra es lo
 * que haya (hace falta un grupo de 4 dentro de una hora para que haya patrón).
 * Traer más historial costaría una lectura por sesión extra por candidato.
 *
 * ─── El plan: `users/{uid}.dailyReminderPlan` ──────────────────────────────
 *
 *   { date: "YYYY-MM-DD" (ART),
 *     kind: "streak-at-risk" | "training-due" | "comeback-reminder",
 *     sendAtMinute: 0..1439 (minuto del día ART),
 *     missing, streakWeeks }   ← racha
 *     missing                  ← hoy toca (sin racha: no lleva `streakWeeks`)
 *     daysSince                ← comeback
 *
 * Lleva los datos del texto, así que el despachante no vuelve a leer sesiones ni
 * rutinas para armarlo. Se escribe SÓLO si el atleta pasó el opt-out y no tiene
 * `lastDailyReminderDate === hoy`. Un plan de un día anterior que haya quedado en
 * el doc no hace daño y no hace falta limpiarlo: el despachante consulta por la
 * fecha de HOY, así que no lo ve; se pisa solo el día que haya otro plan.
 *
 * ─── La racha: port, no reglas propias ─────────────────────────────────────
 *
 * El cálculo vive en `weekly-streak.ts`, un port de la lógica de Dart contrastado
 * contra los fixtures compartidos (`conformance/session_counting.json`,
 * `conformance/routine_selection.json`). Si el servidor tuviera su propia regla,
 * el push diría "tu racha de 4 semanas" y la app 3. El objetivo semanal sale de
 * la rutina ACTIVA del atleta, que se resuelve con la misma cadena de tres
 * niveles que usa el Home. Esa misma racha es la que decide, para quien está al
 * límite, entre `streak-at-risk` (racha ≥ 1) y `training-due` (racha 0).
 *
 * ─── Costo de lecturas ─────────────────────────────────────────────────────
 *
 * Planificador (una vez por día):
 *
 * 1. UNA collectionGroup query paginada sobre `sessions` (ventana de 9 semanas),
 *    filtrada y agrupada en memoria por uid. Cuesta una lectura por sesión de la
 *    ventana, todos los días: crece con la base de usuarios y con la frecuencia
 *    de entrenamiento, no con cuántos reciben push. Si algún día pesa, el
 *    remedio es denormalizar `lastSessionAt` en `users/{uid}`, no achicar la
 *    ventana.
 * 2. Un atleta pasa a ser CANDIDATO si por las sesiones ya cargadas puede llegar
 *    a calificar (ver `summarizeActivity`): para el «al límite» (racha u «hoy
 *    toca») alcanza con que NO haya entrenado hoy; para el comeback, que lleve de
 *    4 a 17 días. Para los candidatos: el doc del usuario, y una escritura si le
 *    toca plan.
 * 3. Las lecturas de RUTINAS (2 queries, y 1 doc más si el marcador apunta al
 *    catálogo) se hacen para todo candidato que ya pasó los filtros baratos (es
 *    atleta, no apagó el push, no se le mandó hoy). Ver el siguiente párrafo.
 * 4. Si la racha llega al borde de la ventana, se completa con una query extra
 *    sobre las sesiones de ESE usuario, para que el "racha de M semanas" del
 *    texto sea exacto y no un piso. Sólo para `streak-at-risk`.
 * 5. El horario habitual no cuesta lecturas: sale de las sesiones del punto 1.
 *
 * ⚠️  Por qué el «al límite» NO tiene pre-filtro por sesiones. Antes la racha
 * tenía uno gratis: `previousWeekCount >= currentWeekCount + daysLeft`, condición
 * NECESARIA para racha ≥ 1 (al límite el objetivo vale `currentWeekCount +
 * daysLeft`, y la semana anterior tiene que haberlo cumplido). El «hoy toca» es
 * justo el COMPLEMENTO —racha 0 es `previousWeekCount < objetivo`—, así que ese
 * filtro lo deja afuera y no hay que reusarlo. Lo que falta es el objetivo, y el
 * objetivo es la rutina. Desde las sesiones no se acota: es cualquier entero ≥ 1
 * (sin rutina, 1). Se evaluó `currentWeekCount + daysLeft <= 7`
 * (`kMaxRoutineDays`) y se descartó: a las 06:00 sólo descarta a quien ya hizo
 * dos sesiones en un mismo día, o sea casi a nadie, y se apoya en un tope que
 * sólo impone el editor del cliente —las reglas no se lo exigen a un PF ni a un
 * Pro—. No ahorra nada que valga el riesgo de perder un positivo.
 *
 * El costo, entonces: la rutina se lee para TODO atleta con una sesión en la
 * ventana que no entrenó antes de las 06:00 y no apagó el push (casi todos los
 * activos), no sólo para los que traían una semana anterior buena. Por atleta:
 * 1 doc de usuario (ya se leía), 2 queries de rutinas (la de asignadas trae
 * hasta 20 docs) y 1 doc si el marcador apunta al catálogo. El otro costo es el
 * TIEMPO, no las lecturas: el bucle es secuencial (varios viajes a Firestore por
 * atleta) y corre bajo `timeoutSeconds: 540`; un timeout a mitad de la corrida
 * deja sin plan a los que quedaron. A modo de cuenta, a ~200 ms por atleta
 * caben unos 2.700 en 540 s. No está medido contra la base real. Si se acerca,
 * el remedio es procesar a los atletas en tandas con concurrencia acotada, o
 * denormalizar el objetivo semanal en `users/{uid}` cuando se escribe la
 * rutina; NO volver a un filtro que pierda positivos.
 *
 * Despachante (cada 15 minutos): UNA query a `users` por igualdad sobre
 * `dailyReminderPlan.date` (sólo los planes de HOY), más, por cada plan VENCIDO,
 * una query de una lectura a las sesiones de ese atleta y la transacción de la
 * reserva. Los planes que todavía no vencieron cuestan su lectura en cada tick
 * desde las 08:00 hasta que les toca (un doc entero de `users`): ≈ planes
 * pendientes × ticks de espera (a modo de cuenta: 1.000 planes que esperan 20
 * ticks de promedio son 20.000 lecturas por día). No está medido contra la base
 * real. Si pesara, el remedio es un índice compuesto (`date ==`, `sendAtMinute
 * <=`) que filtre en el servidor, y por eso mismo NO se agrega ahora: es un
 * deploy de índices a producción.
 *
 * ⚠️  ÍNDICE: la collectionGroup query exige el single-field index de scope
 * COLLECTION_GROUP sobre `sessions.startedAt`, que ya existe como `fieldOverrides`
 * en `firestore.indexes.json` (lo agregó `notifyMonthlyReport`; el porqué largo
 * está en la cabecera de `notify-monthly-report.ts`). NO se agrega otro override:
 * un fieldOverride REEMPLAZA la configuración del campo en vez de sumarse, y
 * declarar uno nuevo le borraría a `startedAt` los índices que ya sostienen
 * `SessionRepository.listByUid`, los contadores del finish y `ranking-aggregate`.
 * Las queries de rutinas usan los tres compuestos que el cliente ya declara. La
 * query del despachante es una igualdad sobre un campo de un mapa, que Firestore
 * indexa solo: no hace falta ni compuesto ni override.
 *
 * ─── Idempotencia ──────────────────────────────────────────────────────────
 *
 * El planificador es idempotente: correrlo dos veces el mismo día reescribe el
 * mismo plan. El que MANDA es el despachante, y ahí `users/{uid}.lastDailyReminderDate`
 * (YYYY-MM-DD ART) guarda el día del último push; si ya vale hoy, el atleta se
 * saltea tanto al planificar como al despachar. `lastComebackReminderDate` guarda
 * el último "volvé a entrenar" para el cooldown. Mismo patrón que
 * `notifyMonthlyReport`: el día se RESERVA en una transacción ANTES de despachar
 * —dos corridas solapadas no pueden mandar las dos— y se SUELTA, restaurando los
 * valores previos y el plan, si el envío falla, para que el próximo tick reintente.
 *
 * ─── Opt-out: ANTES de reservar, y no sólo en sendFcm ──────────────────────
 *
 * `notificationPrefs.recordatorios_entrenamiento.push === false` saltea al
 * usuario antes de planificar, y se vuelve a verificar en la reserva del
 * despachante, antes de llamar a `sendFcm`. No es redundante con el `prefKey`
 * que se le pasa igual: `sendFcm` con una preferencia apagada frena el banner del
 * sistema pero SÍ escribe la entrada de `users/{uid}/notifications` (el historial
 * in-app es otro canal). Sin este corte, quien apagó los recordatorios se
 * encontraría una fila nueva por día en su bandeja. Una preferencia ausente
 * cuenta como encendida.
 *
 * ─── Deep link ─────────────────────────────────────────────────────────────
 *
 * Los tres tipos aterrizan en `/home`: la pestaña Inicio del atleta, que es donde
 * vive `EmpezarEntrenamientoCard` ("EMPEZAR ENTRENAMIENTO", con el día de hoy ya
 * resuelto y un toque a la sesión). `/workout` también es válido, pero deja al
 * atleta frente a la lista de rutinas a elegir, un paso más lejos de entrenar.
 *
 * ─── Reglas de Firestore ───────────────────────────────────────────────────
 *
 * Los tres campos (`dailyReminderPlan`, `lastDailyReminderDate`,
 * `lastComebackReminderDate`) los escribe este backend con el Admin SDK, pero
 * `firestore.rules` NO los pinea: el dueño puede actualizar cualquier campo no
 * protegido de su propio `users/{uid}`. No importa: el único perjudicado por
 * pisarlos es el propio dueño. Con `lastDailyReminderDate` futuro se silencia a
 * sí mismo; borrándolo, o borrando `lastComebackReminderDate`, se saltea el
 * cooldown, pero igual recibe a lo sumo UN push por día. Escribiéndose un
 * `dailyReminderPlan` a mano lo único que logra es mandarse un push a sí mismo:
 * el despachante valida la forma del plan (un plan malformado se borra sin
 * mandar) y arma el texto sólo con enteros. Y apagar los recordatorios ya tiene
 * su interruptor oficial en `notificationPrefs`. Nadie puede tocar el doc de
 * OTRO, y `role` SÍ está pineado (inmutable), así que el filtro "sólo atletas" no
 * se puede falsear.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import {
  DocumentData,
  Query,
  QueryDocumentSnapshot,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { artDateKey } from "../mail/format";
import { comebackSendMinute, habitualStartMinute, streakSendMinute } from "./habitual-time";
import {
  DAY_MS,
  WEEK_MS,
  artDayNumber,
  daysLeftInWeekArt,
  mondayOfWeekArt,
  previousWeekArt,
  resolveActiveRoutineId,
  sessionCountsAsWorkout,
  toArgentina,
  weekStartInstantArt,
  weeklyStreakFromStarts,
  weeklyTargetFromRoutine,
} from "./weekly-streak";

/**
 * La clave de `users/{uid}.notificationPrefs` que apaga estos recordatorios.
 *
 * Es el MISMO literal que `kPrefRecordatoriosEntrenamiento` en
 * `lib/features/profile/domain/notification_pref_keys.dart`; el test de deriva
 * `notification_pref_keys_drift_test.dart` lee este archivo y los compara. Tiene
 * que seguir siendo un literal simple en una sola línea.
 */
export const DAILY_REMINDERS_PREF_KEY = "recordatorios_entrenamiento";

/** Adónde llevan los tres tipos de push. Ver «Deep link» en la cabecera. */
export const DAILY_REMINDER_DEEP_LINK = "/home";

/** El campo de `users/{uid}` donde el planificador deja el plan del día. */
export const DAILY_REMINDER_PLAN_FIELD = "dailyReminderPlan";

/**
 * La ruta que consulta el despachante (`where(…, "==", hoy)`). Va aparte de la
 * anterior para que los dos archivos no armen el string cada uno por su lado.
 */
export const DAILY_REMINDER_PLAN_DATE_PATH = `${DAILY_REMINDER_PLAN_FIELD}.date`;

/** Cuántos días calendario ART sin entrenar disparan el "volvé a entrenar". */
export const COMEBACK_MIN_DAYS = 4;

/**
 * Último día calendario ART sin entrenar en que todavía sale un "volvé a
 * entrenar". Con el cooldown de 7 deja exactamente dos avisos: día 4 y día 11.
 * Ver «El "volvé a entrenar" tiene TOPE» en la cabecera.
 */
export const COMEBACK_MAX_DAYS = 17;

/** Días que tienen que pasar desde el último "volvé a entrenar" para otro. */
export const COMEBACK_COOLDOWN_DAYS = 7;

/** Semanas COMPLETAS anteriores a la actual que cubre la query de sesiones. */
export const STREAK_WINDOW_WEEKS = 8;

const PAGE_SIZE = 500;

/**
 * Tope de páginas de la query de extensión por usuario. Es un cinturón: 20
 * páginas son 10.000 sesiones, que ningún atleta junta. Sin tope, un dato raro
 * (una racha "infinita" por un objetivo mal leído) sería un bucle de lecturas.
 */
const MAX_EXTENSION_PAGES = 20;

type Db = ReturnType<typeof getFirestore>;

export type DailyReminderKind = "streak-at-risk" | "training-due" | "comeback-reminder";

/**
 * El plan del día de UN atleta: lo escribe este planificador en
 * `users/{uid}.dailyReminderPlan` y lo consume `dispatchDailyReminders`. Lleva
 * los datos del texto para que el despachante no tenga que recalcular la racha ni
 * releer rutinas. Ver «El plan» en la cabecera.
 */
export type DailyReminderPlan =
  | {
      date: string;
      kind: "streak-at-risk";
      /** Minuto del día ART (0..1439) a partir del cual puede salir. */
      sendAtMinute: number;
      missing: number;
      streakWeeks: number;
    }
  | {
      date: string;
      kind: "training-due";
      sendAtMinute: number;
      /** Entrenamientos que faltan; al límite, también los días que quedan contando hoy. */
      missing: number;
    }
  | {
      date: string;
      kind: "comeback-reminder";
      sendAtMinute: number;
      daysSince: number;
    };

export interface NotifyDailyRemindersResult {
  /** Planes escritos. El planificador NO manda pushes: eso es del despachante. */
  planned: number;
  plannedStreakAtRisk: number;
  plannedTrainingDue: number;
  plannedComeback: number;
  /** Candidatos que terminaron sin plan por una razón de negocio. */
  skipped: number;
  skippedNotAthlete: number;
  skippedOptedOut: number;
  skippedAlreadySent: number;
  skippedCooldown: number;
  /** No estaba al límite (ni racha ni «hoy toca») y tampoco le tocaba comeback. */
  skippedNotAtRisk: number;
  /** Candidatos que tiraron un error. */
  failed: number;
  /** Atletas que pasaron el filtro barato por sesiones: planned + skipped + failed. */
  candidates: number;
  scannedSessions: number;
  /** Atletas con al menos una sesión que cuenta en la ventana. */
  athletesWithSessions: number;
  /** Hoy en ART, YYYY-MM-DD: el `date` de los planes y lo que mira `lastDailyReminderDate`. */
  dateKey: string;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

// ─── Copy ─────────────────────────────────────────────────────────────────────

/** Título y cuerpo del "racha en riesgo". Singular y plural correctos. */
export function streakAtRiskCopy(
  missing: number,
  streakWeeks: number,
): { title: string; body: string } {
  // El verbo concuerda también: "Te falta 1 entrenamiento", no "Te faltan 1".
  const falta = missing === 1 ? "falta" : "faltan";
  const sesiones = missing === 1 ? "entrenamiento" : "entrenamientos";
  const semanas = streakWeeks === 1 ? "semana" : "semanas";
  return {
    title: "Hoy o se corta 🔥",
    body:
      `Te ${falta} ${missing} ${sesiones} esta semana ` +
      `para sostener tu racha de ${streakWeeks} ${semanas}.`,
  };
}

/**
 * Título y cuerpo del "hoy toca entrenar". Al límite, los entrenamientos que
 * faltan son también los días que quedan contando hoy: el texto usa el mismo
 * número para las dos cosas. Con 1 falta, hoy es el último día de la semana.
 */
export function trainingDueCopy(missing: number): { title: string; body: string } {
  const body =
    missing === 1 ?
      "Te falta 1 entrenamiento y hoy es el último día. " +
        "Si entrenás hoy, llegás a tu objetivo de la semana." :
      `Te faltan ${missing} entrenamientos y quedan ${missing} días. ` +
        "Si arrancás hoy, llegás a tu objetivo de la semana.";
  return { title: "Hoy toca entrenar 💪", body };
}

/** Título y cuerpo del "volvé a entrenar". */
export function comebackCopy(daysSince: number): { title: string; body: string } {
  const dias = daysSince === 1 ? "día" : "días";
  return {
    title: "Te extrañamos en el gym 💪",
    body: `Hace ${daysSince} ${dias} que no entrenás. ¿Arrancamos hoy?`,
  };
}

/** El texto de un plan. Lo arma el despachante, que es quien manda. */
export function reminderCopy(plan: DailyReminderPlan): { title: string; body: string } {
  switch (plan.kind) {
  case "streak-at-risk":
    return streakAtRiskCopy(plan.missing, plan.streakWeeks);
  case "training-due":
    return trainingDueCopy(plan.missing);
  case "comeback-reminder":
    return comebackCopy(plan.daysSince);
  }
}

// ─── Fechas ART como texto ────────────────────────────────────────────────────

const DATE_KEY = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Días calendario entre dos claves YYYY-MM-DD, o `null` si alguna no parsea. */
export function daysBetweenDateKeys(fromKey: string, toKey: string): number | null {
  const from = DATE_KEY.exec(fromKey);
  const to = DATE_KEY.exec(toKey);
  if (!from || !to) return null;
  const fromMs = Date.UTC(Number(from[1]), Number(from[2]) - 1, Number(from[3]));
  const toMs = Date.UTC(Number(to[1]), Number(to[2]) - 1, Number(to[3]));
  return Math.round((toMs - fromMs) / DAY_MS);
}

/**
 * ¿Pasó el cooldown del "volvé a entrenar"? Nunca enviado (o un valor que no es
 * una fecha) cuenta como cumplido. Con `COMEBACK_COOLDOWN_DAYS = 7`: enviado el
 * día D, el D+6 sigue bloqueado y el D+7 pasa.
 */
export function comebackCooldownElapsed(last: unknown, todayKey: string): boolean {
  if (typeof last !== "string") return true;
  const elapsed = daysBetweenDateKeys(last, todayKey);
  if (elapsed === null) return true;
  return elapsed >= COMEBACK_COOLDOWN_DAYS;
}

// ─── Lo que se sabe de un atleta sólo por sus sesiones ───────────────────────

interface Activity {
  /** Sesiones que cuentan en la semana en curso. */
  currentWeekCount: number;
  /** Sesiones que cuentan en la semana anterior. */
  previousWeekCount: number;
  /** Ya completó una sesión HOY (fecha ART). */
  trainedToday: boolean;
  /** Días calendario ART desde la última sesión que cuenta. */
  daysSinceLast: number;
}

interface Calendar {
  /** Lunes de la semana en curso, en el marco ART. */
  currentWeek: number;
  previousWeek: number;
  todayNumber: number;
  daysLeft: number;
  todayKey: string;
}

function summarizeActivity(startsMs: readonly number[], cal: Calendar): Activity {
  let currentWeekCount = 0;
  let previousWeekCount = 0;
  let trainedToday = false;
  let lastMs = Number.NEGATIVE_INFINITY;

  for (const ms of startsMs) {
    const week = mondayOfWeekArt(toArgentina(ms));
    if (week === cal.currentWeek) currentWeekCount++;
    else if (week === cal.previousWeek) previousWeekCount++;
    if (artDayNumber(ms) === cal.todayNumber) trainedToday = true;
    if (ms > lastMs) lastMs = ms;
  }

  return {
    currentWeekCount,
    previousWeekCount,
    trainedToday,
    daysSinceLast: cal.todayNumber - artDayNumber(lastMs),
  };
}

/**
 * ¿Está «en movimiento»? Entrenó hace menos de COMEBACK_MIN_DAYS días, o ya
 * entrenó esta semana. Es la condición del «hoy toca»: separa al que va a mitad
 * de su semana del que dejó de entrenar (ése es del comeback).
 */
function isInMotion(activity: Activity): boolean {
  return activity.daysSinceLast < COMEBACK_MIN_DAYS || activity.currentWeekCount > 0;
}

// ─── Lecturas de rutinas → objetivo semanal ──────────────────────────────────

/**
 * El objetivo semanal del atleta: los días con ejercicios de su rutina ACTIVA,
 * o 1 si no tiene ninguna. Mismas queries que `RoutineRepository` y misma
 * cadena de prioridad que `todaysRoutineProvider`, que es la que alimenta la
 * racha que el atleta ve en la app.
 */
async function loadWeeklyTarget(
  db: Db,
  uid: string,
  activeRoutineId: unknown,
): Promise<number> {
  const marker = typeof activeRoutineId === "string" ? activeRoutineId : null;

  const [assignedSnap, ownSnap] = await Promise.all([
    // `RoutineRepository.listAssignedTo`: el `limit(20)` va ANTES de descartar
    // las archivadas, igual que allá (las archivadas ocupan lugar).
    db
      .collection("routines")
      .where("assignedTo", "==", uid)
      .where("source", "==", "trainer-assigned")
      .orderBy("createdAt", "desc")
      .limit(20)
      .get(),
    // `RoutineRepository.listUserCreated`.
    db
      .collection("routines")
      .where("createdBy", "==", uid)
      .where("source", "==", "user-created")
      .where("status", "==", "active")
      .orderBy("createdAt", "desc")
      .get(),
  ]);

  // El filtro de archivadas va del lado del cliente en Dart (los docs viejos no
  // traen `status`), y acá también: `!== "archived"` deja pasar los que no lo
  // traen y los valores desconocidos, que Dart interpreta como `active`.
  const assigned = assignedSnap.docs.filter((d) => d.data().status !== "archived");
  const own = ownSnap.docs;

  let resolvedId = resolveActiveRoutineId({
    activeRoutineId: marker,
    assignedIds: assigned.map((d) => d.id),
    selfCreatedIds: own.map((d) => d.id),
  });

  // El catálogo se consulta en un único caso, igual que en el Home: hay
  // marcador y no matcheó contra los planes del atleta. Entonces puede ser una
  // plantilla del sistema que eligió SEGUIR sin copiarla. Como el catálogo sólo
  // participa del tier 0, alcanza con preguntar si ESE id es una plantilla del
  // catálogo (`listSystemTemplates`: source == 'system' && visibility ==
  // 'public'), sin traer las demás.
  let catalogData: DocumentData | undefined;
  if (marker !== null && marker !== "" && resolvedId !== marker) {
    const snap = await db.collection("routines").doc(marker).get();
    const data = snap.data();
    if (snap.exists && data?.source === "system" && data.visibility === "public") {
      catalogData = data;
      resolvedId = resolveActiveRoutineId({
        activeRoutineId: marker,
        assignedIds: assigned.map((d) => d.id),
        selfCreatedIds: own.map((d) => d.id),
        catalogIds: [marker],
      });
    }
  }

  if (resolvedId === null) return weeklyTargetFromRoutine(null);

  const routine =
    assigned.find((d) => d.id === resolvedId)?.data() ??
    own.find((d) => d.id === resolvedId)?.data() ??
    (resolvedId === marker ? catalogData : undefined);

  return weeklyTargetFromRoutine(routine);
}

// ─── Racha exacta cuando toca el borde de la ventana ─────────────────────────

function timestampMs(value: unknown): number | null {
  const date = (value as { toDate?: () => Date } | null | undefined)?.toDate?.();
  return date instanceof Date && !Number.isNaN(date.getTime()) ? date.getTime() : null;
}

/**
 * Completa la racha de UN usuario cuando la corrida de semanas cumplidas llegó
 * al borde de la ventana: pide, de a páginas y de la más nueva a la más vieja,
 * las sesiones anteriores a la ventana hasta encontrar una semana que corte (o
 * quedarse sin sesiones).
 *
 * Una página puede cortar una semana por la mitad, así que cada vez se declara
 * «completo» sólo desde el lunes SIGUIENTE a la sesión más vieja de la página:
 * una semana a medio cargar no puede juzgarse.
 */
async function exactStreakWeeks(
  db: Db,
  uid: string,
  input: { startsMs: readonly number[]; target: number; now: Date; windowStartMs: number },
): Promise<number> {
  const { target, now, windowStartMs } = input;
  const starts = [...input.startsMs];
  let detail = weeklyStreakFromStarts({
    countingStartsMs: starts,
    weeklyTarget: target,
    now,
    dataStart: new Date(windowStartMs),
  });

  let cursor: QueryDocumentSnapshot | undefined;
  for (let page = 0; detail.truncated && page < MAX_EXTENSION_PAGES; page++) {
    let query: Query = db
      .collection("users")
      .doc(uid)
      .collection("sessions")
      .where("startedAt", "<", Timestamp.fromDate(new Date(windowStartMs)))
      .orderBy("startedAt", "desc")
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();

    let oldestMs = Number.POSITIVE_INFINITY;
    for (const doc of snap.docs) {
      const data = doc.data();
      const ms = timestampMs(data.startedAt);
      if (ms === null) continue;
      if (ms < oldestMs) oldestMs = ms;
      if (sessionCountsAsWorkout(data.status, data.wasFullyCompleted)) starts.push(ms);
    }

    const exhausted = snap.size < PAGE_SIZE || !Number.isFinite(oldestMs);
    cursor = snap.docs[snap.docs.length - 1];
    detail = weeklyStreakFromStarts({
      countingStartsMs: starts,
      weeklyTarget: target,
      now,
      // Agotadas las sesiones no hay nada más que cargar: se tiene todo.
      dataStart: exhausted ? undefined : new Date(weekStartInstantArt(oldestMs) + WEEK_MS),
    });
    if (exhausted) break;
  }

  if (detail.truncated) {
    // Sólo si se agotó MAX_EXTENSION_PAGES. El número es un piso, no una mentira
    // grande: se loguea para poder verlo.
    logger.warn("notifyDailyReminders: streak still truncated after extension pages", {
      uid,
      streak: detail.streak,
      pages: MAX_EXTENSION_PAGES,
    });
  }
  return detail.streak;
}

// ─── Decisión por atleta ──────────────────────────────────────────────────────

type SkipReason = "not-athlete" | "opted-out" | "already-sent" | "cooldown" | "not-at-risk";

type Outcome =
  | { status: "planned"; kind: DailyReminderKind }
  | { status: "skipped"; reason: SkipReason };

interface RunContext {
  db: Db;
  now: Date;
  cal: Calendar;
  windowStartMs: number;
}

/**
 * Sólo un `push === false` EXPLÍCITO apaga; igual criterio que `sendFcm`. Se
 * exporta porque el despachante tiene que aplicar EXACTAMENTE el mismo criterio
 * al reservar: dos copias de un predicado de preferencias es cómo uno de los dos
 * lados se queda mandando lo que el otro ya no.
 */
export function pushOptedOut(user: DocumentData): boolean {
  const prefs = user.notificationPrefs as
    | Record<string, { push?: unknown } | undefined>
    | null
    | undefined;
  return prefs?.[DAILY_REMINDERS_PREF_KEY]?.push === false;
}

/**
 * ¿Está el atleta AL LÍMITE hoy? Si lo está, devuelve el plan —de racha si tiene
 * racha, de «hoy toca» si no— y si no, `null`.
 *
 * «Al límite» es que le falten exactamente tantos entrenamientos como días le
 * quedan contando hoy: si hoy no entrena, ya no llega. Lo único que no se sabe
 * hasta acá es el objetivo REAL (la rutina), y sin él no hay ningún pre-filtro
 * por sesiones que sirva para los dos tipos (ver «Costo de lecturas»), así que
 * todo atleta que no entrenó hoy pasa por esta lectura.
 *
 * La racha separa los dos tipos: la semana en curso no cuenta (nunca rompe la
 * racha), así que `streak < 1` es que la semana ANTERIOR no cumplió.
 */
async function weekLimitPlanFor(
  ctx: RunContext,
  uid: string,
  user: DocumentData,
  startsMs: readonly number[],
  activity: Activity,
): Promise<DailyReminderPlan | null> {
  const target = await loadWeeklyTarget(ctx.db, uid, user.activeRoutineId);

  // «Faltan exactamente tantos como días quedan»: el objetivo tiene que ser lo
  // que lleva la semana más los días que restan.
  const missing = target - activity.currentWeekCount;
  if (missing <= 0 || missing !== ctx.cal.daysLeft) return null;

  const detail = weeklyStreakFromStarts({
    countingStartsMs: startsMs,
    weeklyTarget: target,
    now: ctx.now,
    dataStart: new Date(ctx.windowStartMs),
  });
  // Con `missing > 0` la semana en curso no cumplió; es una guarda, no un caso.
  if (detail.currentWeekMet) return null;

  // Los dos tipos salen a la misma hora: la de la racha. Ver «A qué hora sale».
  const date = ctx.cal.todayKey;
  const sendAtMinute = streakSendMinute(habitualStartMinute(startsMs));

  // Racha 0: la semana anterior tampoco cumplió. No hay nada que sostener, pero
  // sí un objetivo semanal que todavía se alcanza si entrena hoy. SÓLO para quien
  // está en movimiento: entrenó en los últimos 3 días o ya entrenó ESTA semana
  // (el que hizo lunes y martes y llega al domingo con 1 por hacer va a mitad de
  // su semana, no abandonó). Al que no hizo nada esta semana y lleva 4 o más sin
  // entrenar lo maneja el comeback, con su tope de dos y después silencio. Sin
  // esta guarda, quien dejó de entrenar recibía un «hoy toca» por semana durante
  // ~8 semanas (mientras su última sesión siguiera en la ventana): perseguir al
  // churneado que #1449 decidió no perseguir.
  //
  // Hoy el filtro barato del handler ya garantiza esto (quien no está en
  // movimiento y pasa ese filtro sólo puede tener racha ≥ 1), así que esta guarda
  // no cambia el resultado: es LA REGLA, y aquel filtro es la optimización. Se
  // dejan las dos para que tocar el filtro no reabra la persecución.
  if (detail.streak < 1) {
    if (!isInMotion(activity)) return null;
    return { date, kind: "training-due", sendAtMinute, missing };
  }

  // La corrida llegó al borde de la ventana: el número real puede ser mayor.
  let streakWeeks = detail.streak;
  if (detail.truncated) {
    streakWeeks = await exactStreakWeeks(ctx.db, uid, {
      startsMs,
      target,
      now: ctx.now,
      windowStartMs: ctx.windowStartMs,
    });
  }

  return { date, kind: "streak-at-risk", sendAtMinute, missing, streakWeeks };
}

/**
 * Decide el plan de UN atleta y, si le toca uno, lo escribe. No manda nada y no
 * reserva nada: el marcador `lastDailyReminderDate` lo escribe el despachante
 * cuando el push sale de verdad.
 *
 * La escritura es un `update` simple y no una transacción: lo que podría cambiar
 * entre la lectura previa y la escritura (el opt-out, un envío del mismo día) lo
 * vuelve a verificar el despachante dentro de SU transacción antes de mandar. Un
 * plan de más es inofensivo; un push de más no.
 */
async function planCandidate(
  ctx: RunContext,
  uid: string,
  startsMs: readonly number[],
  activity: Activity,
  flags: { limitCandidate: boolean; comebackCandidate: boolean },
): Promise<Outcome> {
  const { limitCandidate, comebackCandidate } = flags;
  const userRef = ctx.db.collection("users").doc(uid);

  // Lectura previa, sólo para descartar barato ANTES de leer rutinas.
  const snap = await userRef.get();
  const user = snap.data();
  if (!snap.exists || !user || user.role !== "athlete") {
    return { status: "skipped", reason: "not-athlete" };
  }
  if (pushOptedOut(user)) return { status: "skipped", reason: "opted-out" };
  if (user.lastDailyReminderDate === ctx.cal.todayKey) {
    return { status: "skipped", reason: "already-sent" };
  }

  const date = ctx.cal.todayKey;

  // «Al límite» primero (racha u «hoy toca»): si califica, el plan es ése y NO
  // hay comeback hoy, ni se consume su cooldown.
  const limitPlan = limitCandidate ?
    await weekLimitPlanFor(ctx, uid, user, startsMs, activity) :
    null;
  if (limitPlan) {
    await userRef.update({ [DAILY_REMINDER_PLAN_FIELD]: limitPlan });
    return { status: "planned", kind: limitPlan.kind };
  }

  if (comebackCandidate) {
    if (!comebackCooldownElapsed(user.lastComebackReminderDate, date)) {
      return { status: "skipped", reason: "cooldown" };
    }
    const plan: DailyReminderPlan = {
      date,
      kind: "comeback-reminder",
      sendAtMinute: comebackSendMinute(habitualStartMinute(startsMs)),
      daysSince: activity.daysSinceLast,
    };
    await userRef.update({ [DAILY_REMINDER_PLAN_FIELD]: plan });
    return { status: "planned", kind: plan.kind };
  }

  return { status: "skipped", reason: "not-at-risk" };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

/**
 * Handler con el reloj inyectado. Ya no recibe `Messaging`: el planificador no
 * manda nada, así que no hay FCM que reemplazar (eso quedó en el despachante).
 */
export async function notifyDailyRemindersHandler(
  app: App,
  now: Date,
): Promise<NotifyDailyRemindersResult> {
  const db = getFirestore(app);
  const nowMs = now.getTime();

  const currentWeek = mondayOfWeekArt(toArgentina(nowMs));
  const cal: Calendar = {
    currentWeek,
    previousWeek: previousWeekArt(currentWeek),
    todayNumber: artDayNumber(nowMs),
    daysLeft: daysLeftInWeekArt(nowMs),
    todayKey: artDateKey(now),
  };
  // Lunes 00:00 ART de hace 8 semanas, como INSTANTE real.
  const windowStartMs = weekStartInstantArt(nowMs) - STREAK_WINDOW_WEEKS * WEEK_MS;

  // ── 1. Una sola query paginada, agrupada por uid en memoria ──
  const startsByUid = new Map<string, number[]>();
  let scannedSessions = 0;
  let cursor: QueryDocumentSnapshot | undefined;

  do {
    let query: Query = db
      .collectionGroup("sessions")
      .where("startedAt", ">=", Timestamp.fromDate(new Date(windowStartMs)))
      .where("startedAt", "<", Timestamp.fromDate(now))
      .orderBy("startedAt", "asc")
      .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();

    for (const sessionDoc of page.docs) {
      scannedSessions++;
      const data = sessionDoc.data();
      if (!sessionCountsAsWorkout(data.status, data.wasFullyCompleted)) continue;

      const startedMs = timestampMs(data.startedAt);
      const uid = sessionDoc.ref.parent.parent?.id;
      if (startedMs === null || !uid) {
        logger.warn("notifyDailyReminders: session without startedAt or user parent", {
          sessionPath: sessionDoc.ref.path,
        });
        continue;
      }
      const list = startsByUid.get(uid);
      if (list) list.push(startedMs);
      else startsByUid.set(uid, [startedMs]);
    }

    cursor = page.size === PAGE_SIZE ? page.docs[page.docs.length - 1] : undefined;
  } while (cursor);

  // ── 2. Por atleta ──
  const ctx: RunContext = { db, now, cal, windowStartMs };
  const result: NotifyDailyRemindersResult = {
    planned: 0,
    plannedStreakAtRisk: 0,
    plannedTrainingDue: 0,
    plannedComeback: 0,
    skipped: 0,
    skippedNotAthlete: 0,
    skippedOptedOut: 0,
    skippedAlreadySent: 0,
    skippedCooldown: 0,
    skippedNotAtRisk: 0,
    failed: 0,
    candidates: 0,
    scannedSessions,
    athletesWithSessions: startsByUid.size,
    dateKey: cal.todayKey,
  };

  for (const [uid, startsMs] of startsByUid) {
    const activity = summarizeActivity(startsMs, cal);

    // Filtro barato, sólo con lo que ya está en memoria. Quien ya entrenó hoy no
    // recibe nada: ni el «al límite» (racha u «hoy toca», que lo excluyen) ni el
    // comeback (tendría `daysSinceLast = 0`).
    //
    // El «al límite» puede ser racha (≥ 1) u «hoy toca» (racha 0), y cada uno
    // tiene su condición NECESARIA barata:
    //   - racha ≥ 1 exige haber cumplido la semana anterior con el objetivo que
    //     hoy lo pondría al límite (`semana en curso + días que quedan`);
    //   - «hoy toca» exige estar en movimiento (`isInMotion`; ver
    //     `weekLimitPlanFor`).
    // Si no cumple ninguna, no se leen rutinas: el inactivo sin racha sólo puede
    // recibir el comeback, y el que pasó el tope del comeback ni se lee.
    if (activity.trainedToday) continue;
    const canBeStreak =
      activity.previousWeekCount >= activity.currentWeekCount + cal.daysLeft;
    const limitCandidate = canBeStreak || isInMotion(activity);
    const comebackCandidate =
      activity.daysSinceLast >= COMEBACK_MIN_DAYS &&
      activity.daysSinceLast <= COMEBACK_MAX_DAYS;
    if (!limitCandidate && !comebackCandidate) continue;

    result.candidates++;
    try {
      const outcome = await planCandidate(ctx, uid, startsMs, activity, {
        limitCandidate,
        comebackCandidate,
      });

      if (outcome.status === "planned") {
        result.planned++;
        if (outcome.kind === "streak-at-risk") result.plannedStreakAtRisk++;
        else if (outcome.kind === "training-due") result.plannedTrainingDue++;
        else result.plannedComeback++;
        continue;
      }

      result.skipped++;
      switch (outcome.reason) {
      case "not-athlete":
        result.skippedNotAthlete++;
        break;
      case "opted-out":
        result.skippedOptedOut++;
        break;
      case "already-sent":
        result.skippedAlreadySent++;
        break;
      case "cooldown":
        result.skippedCooldown++;
        break;
      case "not-at-risk":
        result.skippedNotAtRisk++;
        break;
      }
    } catch (error: unknown) {
      result.failed++;
      // `Error` no se serializa en el logger (sale `{}`): se loguea el mensaje.
      logger.error("notifyDailyReminders: failed for athlete", {
        uid,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  logger.info("notifyDailyReminders: run complete", result);
  return result;
}

/**
 * Corre todos los días a las 06:00 ART, en la misma región que el resto de las
 * CFs de TREINO. Sólo planifica; `dispatchDailyReminders` es quien manda.
 * `timeoutSeconds: 540` porque, a diferencia del reporte mensual, el escaneo es
 * de 9 semanas todos los días y las lecturas por candidato son secuenciales. Las
 * 06:00 dejan dos horas de margen hasta el primer horario posible de envío
 * (08:00).
 */
export const notifyDailyReminders = onSchedule(
  {
    schedule: "0 6 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
    timeoutSeconds: 540,
  },
  async () => {
    const result = await notifyDailyRemindersHandler(ensureApp(), new Date());
    logger.info("notifyDailyReminders: scheduled run done", result);
  },
);
