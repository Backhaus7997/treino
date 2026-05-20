import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/streak_calculator.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart';
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
  // cuenta desde ayer). ADR-WRS-08: lifted to lib/core/utils/streak_calculator.dart
  // in PR#2.
  final streak = computeStreak(allSessions, now: now);

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

// ── Week helpers ──────────────────────────────────────────────────────────────

DateTime _mondayOfWeek(DateTime now) {
  final daysFromMonday = now.weekday - DateTime.monday;
  return DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: daysFromMonday));
}
