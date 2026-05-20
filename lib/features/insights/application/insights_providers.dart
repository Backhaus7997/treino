import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/exercise_providers.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/domain/session.dart';
import '../../workout/domain/session_status.dart';
import '../domain/muscle_group.dart';
import '../domain/weekly_insights.dart';

/// Calcula los agregados de la semana actual del usuario para la pantalla
/// de Insights. autoDispose: se re-evalúa cada vez que se monta la pantalla.
final weeklyInsightsProvider =
    FutureProvider.autoDispose<WeeklyInsights?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;

  final repo = ref.read(sessionRepositoryProvider);

  // Rango de semana — lunes 00:00 local hasta el siguiente lunes (exclusivo).
  final now = DateTime.now().toLocal();
  final weekStart = _mondayOfWeek(now);
  final weekEndExclusive = weekStart.add(const Duration(days: 7));

  // Todas las sessions del usuario (listByUid ya viene ordenado DESC por
  // startedAt en SessionRepository).
  final allSessions = await repo.listByUid(uid);
  final mostRecentSession = allSessions.isNotEmpty ? allSessions.first : null;

  // Filtro a esta semana + finished.
  final weekSessions = allSessions.where((s) {
    final started = s.startedAt.toLocal();
    return !started.isBefore(weekStart) &&
        started.isBefore(weekEndExclusive) &&
        s.status == SessionStatus.finished;
  }).toList();

  // Días entrenados (0=lun..6=dom).
  final daysTrained = List<bool>.filled(7, false);
  for (final s in weekSessions) {
    final dayIndex = s.startedAt.toLocal().weekday - DateTime.monday;
    if (dayIndex >= 0 && dayIndex < 7) {
      daysTrained[dayIndex] = true;
    }
  }

  // Catálogo de ejercicios → index por id para lookup O(1).
  final exercises = await ref.watch(exercisesProvider.future);
  final byId = {for (final e in exercises) e.id: e};

  // setsByGroup — iterar los setLogs de cada session de la semana.
  final setsByGroup = <MuscleGroupDisplay, int>{};
  for (final s in weekSessions) {
    final logs = await repo.listSetLogs(uid: uid, sessionId: s.id);
    for (final log in logs) {
      final group = byId[log.exerciseId]?.muscleGroup.toDisplayGroup();
      if (group != null) {
        setsByGroup[group] = (setsByGroup[group] ?? 0) + 1;
      }
    }
  }

  // targetByGroup — de la rutina de la sesión más reciente (mejor heurística
  // disponible hasta que UserProfile.currentRoutineId exista). Si el usuario
  // nunca entrenó (no hay session) o la rutina no se encuentra, queda vacío
  // y las progress bars se renderizan sin target.
  final targetByGroup = <MuscleGroupDisplay, int>{};
  if (mostRecentSession != null) {
    final routine = await ref
        .watch(routineByIdProvider(mostRecentSession.routineId).future);
    if (routine != null) {
      for (final day in routine.days) {
        for (final slot in day.slots) {
          final group = byId[slot.exerciseId]?.muscleGroup.toDisplayGroup();
          if (group != null) {
            targetByGroup[group] =
                (targetByGroup[group] ?? 0) + slot.targetSets;
          }
        }
      }
    }
  }

  // streak — días consecutivos entrenados (incluye hoy si entrenó, sino
  // cuenta desde ayer). ADR-WRS-08: _computeStreak queda inline en PR#1;
  // PR#2 lo extrae a lib/core/utils/streak_calculator.dart.
  final streak = _computeStreak(allSessions, now: now);

  // monthSessionsCount — sesiones finished en el mes calendario actual.
  // ADR-WRS-03: mes calendario, NOT ventana de 30 días.
  final monthSessionsCount = allSessions.where((s) {
    if (s.status != SessionStatus.finished) return false;
    final local = s.startedAt.toLocal();
    return local.year == now.year && local.month == now.month;
  }).length;

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
  );
});

// ── Streak algorithm ──────────────────────────────────────────────────────────
//
// ADR-WRS-08: stays inline for PR#1. PR#2 lifts to
// lib/core/utils/streak_calculator.dart.
//
// Algorithm (ADR-WRS-02 — Q2 lock):
//   1. Build a set of unique local dates where a finished session started.
//   2. Check if today is in the set (trained today):
//      → If yes, count backwards from today including today.
//   3. If today is NOT in the set (not yet trained today):
//      → Count backwards starting from yesterday.
//
// O(n) to build the set + O(streak) to count.

/// Visible-for-testing alias so unit tests can call `_computeStreak` directly
/// via the exported symbol [computeStreakForTest].
@visibleForTesting
int computeStreakForTest(List<Session> sessions, {required DateTime now}) =>
    _computeStreak(sessions, now: now);

int _computeStreak(List<Session> sessions, {required DateTime now}) {
  final todayLocal = now.toLocal();
  final todayDate = DateTime(todayLocal.year, todayLocal.month, todayLocal.day);

  // Build a set of unique local dates with at least one finished session.
  final trainedDates =
      sessions.where((s) => s.status == SessionStatus.finished).map((s) {
    final local = s.startedAt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }).toSet();

  var streak = 0;
  var cursor = todayDate;

  // Try counting from today.
  while (trainedDates.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  // If today was not trained, try counting from yesterday.
  if (streak == 0) {
    cursor = todayDate.subtract(const Duration(days: 1));
    while (trainedDates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }

  return streak;
}

// ── Week helpers ──────────────────────────────────────────────────────────────

DateTime _mondayOfWeek(DateTime now) {
  final daysFromMonday = now.weekday - DateTime.monday;
  return DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: daysFromMonday));
}
