import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/argentina_time.dart';
import '../../../core/utils/streak_calculator.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/domain/session.dart';
import '../domain/muscle_group.dart';
import '../domain/weekly_insights.dart';

/// [UX-week-day-selector] Family key for [athleteWeekInsightsProvider].
/// Explicit [uid] (NOT `currentUidProvider`) and explicit [weekStart] (must
/// already be normalized to a Monday 00:00 local via [mondayOfWeek]) — same
/// pattern `athleteDayInsightsProvider` uses so the SAME provider can serve
/// the athlete's own paged week view.
typedef AthleteWeekInsightsKey = ({String uid, DateTime weekStart});

/// [UX-week-day-selector] Per-week aggregate for [key.uid], for the week
/// starting [key.weekStart] (Monday 00:00 local) — generalizes the old
/// hardwired "current week only" `weeklyInsightsProvider` so the SEMANA card
/// can page to past weeks. `streak` and `monthSessionsCount` are computed
/// from the FULL session history regardless of which week is shown (they are
/// not week-scoped concepts), matching the original provider's semantics.
final athleteWeekInsightsProvider = FutureProvider.autoDispose
    .family<WeeklyInsights?, AthleteWeekInsightsKey>((ref, key) async {
  if (key.uid.isEmpty) return null;

  final repo = ref.read(sessionRepositoryProvider);

  // Rango de semana — lunes 00:00 local (ya normalizado por el caller) hasta
  // el siguiente lunes (exclusivo). Aritmética de calendario (no Duration)
  // para que el borde caiga en medianoche local incluso atravesando un
  // cambio de horario (DST).
  final weekStart = DateTime.utc(
    key.weekStart.year,
    key.weekStart.month,
    key.weekStart.day,
  );
  final weekEndExclusive =
      DateTime.utc(weekStart.year, weekStart.month, weekStart.day + 7);
  final now = argentinaNow();

  // Todas las sessions del usuario (listByUid ya viene ordenado DESC por
  // startedAt en SessionRepository).
  final allSessions = await repo.listByUid(key.uid);
  final mostRecentSession = allSessions.isNotEmpty ? allSessions.first : null;

  // Filtro a la semana pedida + finished.
  final weekSessions = allSessions.where((s) {
    final started = toArgentina(s.startedAt);
    return !started.isBefore(weekStart) &&
        started.isBefore(weekEndExclusive) &&
        s.countsAsWorkout;
  }).toList();

  // Días entrenados (0=lun..6=dom).
  final daysTrained = List<bool>.filled(7, false);
  for (final s in weekSessions) {
    final dayIndex = toArgentina(s.startedAt).weekday - DateTime.monday;
    if (dayIndex >= 0 && dayIndex < 7) {
      daysTrained[dayIndex] = true;
    }
  }

  // Catálogo de ejercicios → index por id para lookup O(1).
  final exercises = await ref.watch(exercisesProvider.future);
  final byId = {for (final e in exercises) e.id: e};

  // Rutina de la sesión más reciente (mejor heurística disponible hasta que
  // UserProfile.currentRoutineId exista). Se trae antes de los setLogs porque
  // sus slots llevan el `muscleGroup` denormalizado — la única fuente del
  // grupo para ejercicios custom del trainer, que NO están en el catálogo
  // público.
  final routine = mostRecentSession != null
      ? await ref.watch(routineByIdProvider(mostRecentSession.routineId).future)
      : null;

  // Fallback exerciseId → muscleGroup String desde los slots de la rutina.
  // Cubre ejercicios custom ausentes del catálogo, cuyos setLogs sólo guardan
  // exerciseId (SetLog no denormaliza el grupo).
  final slotGroupById = <String, String>{};
  if (routine != null) {
    for (final day in routine.days) {
      for (final slot in day.slots) {
        slotGroupById.putIfAbsent(slot.exerciseId, () => slot.muscleGroup);
      }
    }
  }

  // setsByGroup — los setLogs de cada session de la semana. Las lecturas por
  // sesión se paralelizan con Future.wait (una subcolección por sesión) para
  // colapsar N round-trips seriales en un batch.
  final setsByGroup = <MuscleGroupDisplay, int>{};
  final logsPerSession = await Future.wait(
    weekSessions.map((s) => repo.listSetLogs(uid: key.uid, sessionId: s.id)),
  );
  for (final logs in logsPerSession) {
    for (final log in logs) {
      // Catálogo público primero; si el id es custom (ausente), resolver vía
      // el muscleGroup denormalizado del slot de la rutina.
      final groupRaw =
          byId[log.exerciseId]?.muscleGroup ?? slotGroupById[log.exerciseId];
      final group = groupRaw?.toDisplayGroup();
      if (group != null) {
        setsByGroup[group] = (setsByGroup[group] ?? 0) + 1;
      }
    }
  }

  // targetByGroup — usa el `muscleGroup` ya denormalizado del slot (correcto
  // para ejercicios custom y sin depender de que el catálogo esté completo).
  // Si el usuario nunca entrenó o la rutina no se encuentra, queda vacío y las
  // progress bars se renderizan sin target.
  final targetByGroup = <MuscleGroupDisplay, int>{};
  if (routine != null) {
    for (final day in routine.days) {
      for (final slot in day.slots) {
        final group = slot.muscleGroup.toDisplayGroup();
        if (group != null) {
          targetByGroup[group] = (targetByGroup[group] ?? 0) + slot.targetSets;
        }
      }
    }
  }

  // streak — días consecutivos entrenados (incluye hoy si entrenó, sino
  // cuenta desde ayer). ADR-WRS-08: lifted to lib/core/utils/streak_calculator.dart
  // in PR#2.
  // NB: computeStreak now buckets in the Argentina calendar frame internally
  // (#411), consistent with the rest of Insights. Its `now` param is a REAL
  // instant (normalized with `.toUtc()` inside) — passing the ART-framed `now`
  // above would double-shift and corrupt the day math, so we deliberately let
  // it default to `DateTime.now()`, same as every other computeStreak caller
  // (workout_days_providers / profile_stats / session_repository).
  final streak = computeStreak(allSessions);

  // monthSessionsCount — sesiones finished en el mes calendario actual.
  // ADR-WRS-03: mes calendario ARGENTINA (mismo frame que el resto de Insights),
  // NOT ventana de 30 días.
  final monthSessionsCount = allSessions.where((s) {
    if (!s.countsAsWorkout) return false;
    final local = toArgentina(s.startedAt);
    return local.year == now.year && local.month == now.month;
  }).length;

  // Bug fix (abandoned-session-streak-reports): "entrenó alguna vez" se
  // deriva de la MISMA lectura `allSessions` de arriba — sin fetch extra.
  // Desacopla el hub de reportes históricos del `_EmptyState` de onboarding
  // en insights_screen.dart: una semana en 0 no implica cuenta nueva.
  final hasEverCompletedAnyWorkout = allSessions.any((s) => s.countsAsWorkout);

  return WeeklyInsights(
    weekStart: weekStart,
    weekEnd: weekEndExclusive.subtract(const Duration(milliseconds: 1)),
    daysTrained: daysTrained,
    sessionsCount: weekSessions.length,
    // Hardcoded 5 — decisión 5. Refinar cuando Coach exponga plannedDays.
    plannedSessionsCount: 5,
    setsByGroup: setsByGroup,
    targetByGroup: targetByGroup,
    streak: streak,
    monthSessionsCount: monthSessionsCount,
    hasEverCompletedAnyWorkout: hasEverCompletedAnyWorkout,
  );
});

/// Calcula los agregados de la SEMANA ACTUAL del usuario logueado. Delgado
/// wrapper sobre [athleteWeekInsightsProvider] con `weekStart` fijo a "esta
/// semana" — mantenido para consumers existentes (home's `EstaSemanaCard`)
/// que no necesitan pagear semanas. autoDispose: se re-evalúa cada vez que
/// se monta la pantalla.
final weeklyInsightsProvider =
    FutureProvider.autoDispose<WeeklyInsights?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;

  final weekStart = mondayOfWeek(argentinaNow());
  return ref.watch(
    athleteWeekInsightsProvider((uid: uid, weekStart: weekStart)).future,
  );
});

// ── Week helpers ──────────────────────────────────────────────────────────────

/// [UX-week-day-selector] Monday 00:00 local of the week containing [now].
/// Public (was `_mondayOfWeek`) so the SEMANA card's paging logic
/// (`insights_screen.dart`) can compute prior/next week boundaries with the
/// same calendar-arithmetic, DST-safe rule.
DateTime mondayOfWeek(DateTime now) {
  final daysFromMonday = now.weekday - DateTime.monday;
  // Resta de días vía constructor de calendario para normalizar el borde a
  // medianoche. UTC-flagged para vivir en el frame ART (mismo que las
  // comparaciones de sesión vía toArgentina); pasarle argentinaNow() da el
  // lunes calendario de Argentina.
  return DateTime.utc(now.year, now.month, now.day - daysFromMonday);
}
