import '../../features/workout/domain/routine.dart';
import '../../features/workout/domain/session.dart';
import 'argentina_time.dart';

/// Fallback de objetivo semanal cuando el atleta no tiene rutina activa, o la
/// que tiene no define ni un día con ejercicios.
///
/// Uno, no cero: con cero el `>=` daría siempre verdadero y la racha contaría
/// semanas en las que el atleta no entrenó nunca. Con uno, la regla degrada a
/// "al menos una sesión por semana" — indulgente, pero honesta y siempre
/// verdadera sobre el dato que muestra.
const int weeklyStreakFallbackTarget = 1;

/// Cuántas sesiones por semana exige [routine] para que la semana cuente.
///
/// Es la cantidad de días del plan **con al menos un ejercicio**: un
/// [RoutineDay] con `slots` vacío es válido en el dominio (SCENARIO-046) y es
/// como se modela un día de descanso — contarlo inflaría el objetivo y le
/// mataría la racha a alguien que cumplió su plan completo.
///
/// Sin rutina, o con una rutina que es toda días vacíos, cae en
/// [weeklyStreakFallbackTarget].
int weeklyTargetFromRoutine(Routine? routine) {
  if (routine == null) return weeklyStreakFallbackTarget;
  final trainingDays = routine.days.where((d) => d.slots.isNotEmpty).length;
  return trainingDays > 0 ? trainingDays : weeklyStreakFallbackTarget;
}

/// Racha SEMANAL: cuántas semanas consecutivas el atleta cumplió el objetivo
/// de días de su rutina.
///
/// SEMÁNTICA (decisión de producto, 2026-09-02) — reemplaza a la racha por día
/// de `computeStreak`. Una semana "cuenta" cuando tiene al menos
/// [weeklyTarget] sesiones que califican como entrenamiento
/// ([Session.countsAsWorkout]: `finished` Y `wasFullyCompleted`). La racha es
/// la corrida de semanas consecutivas cumplidas hacia atrás. Ejemplo del
/// producto: rutina de 3 días, tres semanas cumplidas, en la cuarta falla un
/// día → la racha vale 3.
///
/// LA SEMANA EN CURSO NUNCA ROMPE LA RACHA. Es la contraparte exacta del día
/// de gracia de `computeStreak`: el miércoles con 1 de 3 sesiones hechas la
/// semana no fracasó, todavía no terminó. Entonces:
///   - si la semana actual YA cumplió el objetivo, suma;
///   - si todavía no, no suma pero tampoco corta — se sigue contando desde la
///     semana anterior.
/// Sin esta regla la racha de todo el mundo se caería a 0 cada lunes a la
/// medianoche y volvería a subir el día que entrenaran: un número que parpadea
/// no es un número en el que se pueda confiar.
///
/// Semanas lunes-domingo en el frame ART vía [mondayOfWeekArt] — el mismo
/// borde que Insights y `session_recognition`, NO la timezone del dispositivo.
/// Ver `argentina_time.dart` para por qué todo concepto de calendario se
/// ancla a ART.
///
/// LIMITACIÓN CONOCIDA, y es real: [weeklyTarget] es el objetivo de la rutina
/// activa **de hoy**, aplicado hacia atrás a todas las semanas. No guardamos
/// historial de qué rutina cursaba el atleta en cada semana pasada, así que
/// alguien que pasa de 3 a 5 días por semana va a ver su racha histórica
/// recalculada contra 5 y probablemente acortada. Es el precio de no
/// versionar el plan por semana; si algún día molesta, la solución es
/// estampar el objetivo en la sesión al crearla, no adivinar acá.
///
/// [now] es un instante REAL (cualquier flag) — se normaliza con `.toUtc()`
/// internamente. NO le pases `argentinaNow()`, sería doble corrimiento. Mismo
/// contrato que `computeStreak`.
///
/// O(n) para bucketear + O(racha) para contar.
int computeWeeklyStreak({
  required List<Session> sessions,
  required int weeklyTarget,
  DateTime? now,
}) =>
    weeklyStreakOf(
      sessions: sessions,
      weeklyTarget: weeklyTarget,
      now: now,
    ).streak;

/// La racha semanal + si la semana EN CURSO ya cumplió el objetivo.
///
/// El segundo dato existe para el camino de ESCRITURA. La `rachaSemanas`
/// denormalizada sólo se persiste cuando la semana en curso cumplió, y así el
/// sello de frescura pasa a significar "la semana sellada CONTÓ para la
/// racha" — que es lo que el decay de [effectiveRachaSemanas] necesita poder
/// asumir para juzgar con una semana de gracia.
///
/// Sin esa regla el decay miente: un atleta con objetivo 3 que hace UNA sesión
/// en la semana W sella un valor que viene de W-1, y al llegar W+1 el sello
/// tiene una semana de antigüedad y pasa el filtro de gracia — aunque W ya
/// cerró incumplida y la racha en vivo es 0. Rankings mostrando 5 contra un
/// Perfil que dice 0 es exactamente el #552 otra vez.
({int streak, bool currentWeekMet}) weeklyStreakOf({
  required List<Session> sessions,
  required int weeklyTarget,
  DateTime? now,
}) {
  // Un objetivo de 0 haría que `>=` diera verdadero para toda semana vacía y
  // la racha se volvería "semanas desde que existe el mundo".
  final target = weeklyTarget > 0 ? weeklyTarget : weeklyStreakFallbackTarget;

  final nowArt = toArgentina((now ?? DateTime.now()).toUtc());
  final currentWeek = mondayOfWeekArt(nowArt);

  // Sesiones que califican, contadas por lunes de su semana ART.
  // `session.startedAt` siempre viene UTC-flagged (TimestampConverter hace
  // `.toUtc()`), así que `toArgentina` es exacto.
  final countByWeek = <DateTime, int>{};
  for (final session in sessions) {
    if (!session.countsAsWorkout) continue;
    final weekStart = mondayOfWeekArt(toArgentina(session.startedAt));
    countByWeek[weekStart] = (countByWeek[weekStart] ?? 0) + 1;
  }

  bool met(DateTime weekStart) => (countByWeek[weekStart] ?? 0) >= target;

  var streak = 0;

  // La semana en curso suma sólo si ya cumplió; si no, se saltea sin cortar.
  final currentWeekMet = met(currentWeek);
  if (currentWeekMet) streak++;

  var cursor = _previousWeek(currentWeek);
  while (met(cursor)) {
    streak++;
    cursor = _previousWeek(cursor);
  }

  return (streak: streak, currentWeekMet: currentWeekMet);
}

/// Lunes de la semana anterior a [weekStart]. Vía constructor de calendario
/// (no `subtract`) por la misma razón que [mondayOfWeekArt]: mantiene el borde
/// clavado a medianoche.
DateTime _previousWeek(DateTime weekStart) =>
    DateTime.utc(weekStart.year, weekStart.month, weekStart.day - 7);
