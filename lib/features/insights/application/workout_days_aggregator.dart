import '../../../core/utils/argentina_time.dart';
import '../../workout/domain/session.dart';

/// [AD6] Pure function — returns the set of unique local calendar dates
/// within [month] on which [sessions] recorded at least one
/// [SessionStatus.finished] session, backing [WorkoutDaysCalendar]'s
/// trained-day marks.
///
/// Dedup por fecha calendario ART (año/mes/día, hora truncada); sólo cuentan
/// las sesiones que califican como entrenamiento.
///
/// Esta función sigue siendo por DÍA aunque la racha ya no lo sea: son dos
/// preguntas distintas. Acá se pinta la grilla del calendario —"qué días de
/// este mes entrenó"— y un día entrenado es un día entrenado. La racha
/// responde "cuántas semanas seguidas cumplió su rutina" y la calcula
/// `computeWeeklyStreak` (`lib/core/utils/weekly_streak_calculator.dart`) por
/// separado, sobre la lista completa de sesiones.
///
/// [month] may be any [DateTime] within the target calendar month — only
/// its `year`/`month` fields are used.
Set<DateTime> trainedDaysInMonth(List<Session> sessions, DateTime month) {
  final result = <DateTime>{};

  for (final session in sessions) {
    if (!session.countsAsWorkout) continue;
    final started = toArgentina(session.startedAt);
    if (started.year != month.year || started.month != month.month) continue;
    result.add(DateTime(started.year, started.month, started.day));
  }

  return result;
}
