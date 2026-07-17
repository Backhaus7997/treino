import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/argentina_time.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/domain/session.dart';
import '../domain/day_insights.dart';
import 'day_insights_aggregator.dart';

/// [AD5] Family key for [athleteDayInsightsProvider]. Explicit [uid] (NOT
/// `currentUidProvider`) so the SAME provider serves the athlete's own
/// Insights screen AND the coach's alumno-detail view — the coach passes the
/// alumno's athleteId, the athlete's own screen passes its own uid.
typedef AthleteDayInsightsKey = ({String uid, DateTime day});

/// [REQ:heat-map-per-day] [AD5] Per-day heat-map aggregate for [key.uid] on
/// [key.day] — replaces the old week-accumulated `weeklyInsightsProvider`
/// heat-map data for the body silhouette. Each day starts blank; only that
/// day's finished sessions paint it.
///
/// autoDispose: re-evaluates each time a day tile is selected, mirroring
/// `weeklyInsightsProvider`'s lifecycle.
final athleteDayInsightsProvider = FutureProvider.autoDispose
    .family<DayInsights, AthleteDayInsightsKey>((ref, key) async {
  if (key.uid.isEmpty) {
    return DayInsights(
      day: DateTime(key.day.year, key.day.month, key.day.day),
      setsByGroup: const {},
      sessionsCount: 0,
    );
  }

  final repo = ref.read(sessionRepositoryProvider);
  final allSessions = await repo.listByUid(key.uid);

  final daySessions = allSessions.where((s) {
    if (!s.countsAsWorkout) return false;
    final started = toArgentina(s.startedAt);
    return started.year == key.day.year &&
        started.month == key.day.month &&
        started.day == key.day.day;
  }).toList();

  if (daySessions.isEmpty) {
    return DayInsights(
      day: DateTime(key.day.year, key.day.month, key.day.day),
      setsByGroup: const {},
      sessionsCount: 0,
    );
  }

  // Catálogo público → lookup O(1) por exerciseId (mismo patrón que
  // weeklyInsightsProvider).
  final exercises = await ref.watch(exercisesProvider.future);
  final byId = {for (final e in exercises) e.id: e};

  // Fallback exerciseId → muscleGroup vía los slots de la rutina de CADA
  // sesión del día (un día puede tener sesiones de rutinas distintas, a
  // diferencia del weekly provider que solo mira la sesión más reciente).
  final routineIds = daySessions.map((s) => s.routineId).toSet();
  final routines = await Future.wait(
    routineIds.map((id) => ref.watch(routineByIdProvider(id).future)),
  );
  final slotGroupById = <String, String>{};
  for (final routine in routines) {
    if (routine == null) continue;
    for (final day in routine.days) {
      for (final slot in day.slots) {
        slotGroupById.putIfAbsent(slot.exerciseId, () => slot.muscleGroup);
      }
    }
  }

  final setLogsBySessionId = {
    for (final entry in await Future.wait(
      daySessions.map(
        (s) async => MapEntry(
          s.id,
          await repo.listSetLogs(uid: key.uid, sessionId: s.id),
        ),
      ),
    ))
      entry.key: entry.value,
  };

  final muscleGroupByExerciseId = <String, String>{};
  for (final logs in setLogsBySessionId.values) {
    for (final log in logs) {
      muscleGroupByExerciseId.putIfAbsent(
        log.exerciseId,
        () =>
            byId[log.exerciseId]?.muscleGroup ??
            slotGroupById[log.exerciseId] ??
            '',
      );
    }
  }

  return aggregateDayInsights(
    day: key.day,
    sessions: daySessions,
    setLogsBySessionId: setLogsBySessionId,
    muscleGroupByExerciseId: muscleGroupByExerciseId,
  );
});

/// [AD5] The last 7 calendar days (oldest first, today last) of
/// [athleteDayInsightsProvider] for [uid] — backs the Hevy-style day-strip
/// navigation. Explicit [uid] so both the athlete's own screen and the
/// coach's alumno-detail view can reuse it.
final athleteLast7DaysInsightsProvider = FutureProvider.autoDispose
    .family<List<DayInsights>, String>((ref, uid) async {
  final today = argentinaNow();
  final days = lastNDays(today, 7);

  return Future.wait(
    days.map(
      (day) => ref.watch(
        athleteDayInsightsProvider((uid: uid, day: day)).future,
      ),
    ),
  );
});
