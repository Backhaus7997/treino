import '../domain/plan_advance.dart';
import '../domain/routine.dart';
import '../domain/session.dart';

/// La posición (semana, día) que le toca a [routine] según su historial: la
/// última sesión terminada de ESA rutina + 1, cíclico (`nextPlanPosition`).
///
/// Es la cuenta de la card de Inicio, extraída para que el detalle de la
/// rutina use la misma (#1509): Inicio ofrecía EMPEZAR y el detalle del mismo
/// día decía REPETIR, porque el detalle miraba «¿se hizo alguna vez?» en todo
/// el historial y Inicio «¿qué sigue?» en el ciclo.
///
/// Toma la sesión más reciente por `startedAt` en vez de confiar en el orden
/// de la lista: el repo las devuelve descendentes, pero esto no lo asume.
PlanPosition nextPositionForRoutine(Routine routine, List<Session> sessions) {
  Session? last;
  for (final s in sessions) {
    if (s.routineId != routine.id || !s.countsAsWorkout) continue;
    if (last == null || s.startedAt.isAfter(last.startedAt)) last = s;
  }
  return nextPlanPosition(
    lastFinished: last == null
        ? null
        : (dayNumber: last.dayNumber, weekNumber: last.weekNumber),
    numDays: routine.days.length,
    numWeeks: routine.numWeeks,
  );
}
