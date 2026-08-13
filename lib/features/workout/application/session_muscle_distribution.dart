import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../insights/application/routine_slot_groups.dart';
import '../../insights/domain/muscle_group.dart';
import '../../insights/domain/radar_axis.dart';
import '../domain/set_log.dart';
import 'exercise_providers.dart';
import 'session_providers.dart';

/// Distribución muscular de UNA sesión: sets y volumen (reps × kg) por eje
/// del radar. Los mapas son sparse — solo ejes con ≥1 set atribuido — igual
/// que `MuscleDistributionInsights.currentSetsByAxis`.
typedef SessionMuscleDistribution = ({
  Map<RadarAxis, int> setsByAxis,
  Map<RadarAxis, double> volumeKgByAxis,
});

const SessionMuscleDistribution emptySessionMuscleDistribution = (
  setsByAxis: <RadarAxis, int>{},
  volumeKgByAxis: <RadarAxis, double>{},
);

/// Pure top-level aggregator para el resumen post-entreno — no Riverpod,
/// fully testable. Mismo split "pure fn behind a thin provider" y mismo fold
/// `raw → toDisplayGroup() → RadarAxis.fromDisplayGroup()` que
/// [aggregateMuscleDistribution], pero acotado a los [setLogs] de UNA sesión
/// (sin ventana temporal ni comparación current/previous).
///
/// [muscleGroupByExerciseId] resuelve cada `SetLog.exerciseId` a su string
/// crudo de `muscleGroup` — el caller (provider) hace la resolución
/// "catálogo primero, slot de rutina como fallback". Strings desconocidos o
/// excluidos de Insights (`cardio`/`full_body` → `toDisplayGroup()` null) se
/// skipean silenciosamente, misma regla que el radar de períodos.
SessionMuscleDistribution aggregateSessionMuscleDistribution({
  required List<SetLog> setLogs,
  required Map<String, String> muscleGroupByExerciseId,
}) {
  final setsByAxis = <RadarAxis, int>{};
  final volumeKgByAxis = <RadarAxis, double>{};
  for (final log in setLogs) {
    final displayGroup =
        muscleGroupByExerciseId[log.exerciseId]?.toDisplayGroup();
    if (displayGroup == null) continue;
    final axis = RadarAxis.fromDisplayGroup(displayGroup);
    setsByAxis[axis] = (setsByAxis[axis] ?? 0) + 1;
    volumeKgByAxis[axis] =
        (volumeKgByAxis[axis] ?? 0) + log.reps * log.weightKg;
  }
  return (setsByAxis: setsByAxis, volumeKgByAxis: volumeKgByAxis);
}

/// Distribución muscular de la sesión del resumen post-entreno.
///
/// Watchea [sessionSummaryProvider] con la MISMA key que la pantalla, así el
/// fetch de sesión + setLogs se comparte (Riverpod dedupea) en vez de
/// re-leerse de Firestore. La resolución exerciseId → muscleGroup copia el
/// orden establecido por los providers del radar de Insights: catálogo
/// público primero (O(1)), slots de la rutina de la sesión como fallback
/// para ejercicios custom ausentes del catálogo (#442).
final sessionMuscleDistributionProvider = FutureProvider.autoDispose
    .family<SessionMuscleDistribution, ({String uid, String sessionId})>(
        (ref, key) async {
  if (key.uid.isEmpty) return emptySessionMuscleDistribution;

  final summary = await ref.watch(sessionSummaryProvider(key).future);
  final session = summary.session;
  if (session == null || summary.setLogs.isEmpty) {
    return emptySessionMuscleDistribution;
  }

  final exercises = await ref.watch(exercisesProvider.future);
  final catalogById = {for (final e in exercises) e.id: e.muscleGroup};

  // El fallback de slots de rutina cuesta un fetch frío de la rutina — solo
  // vale la pena si la sesión tiene algún ejercicio custom fuera del catálogo.
  // Con ejercicios 100% stock (el caso común) se evita el round-trip y la
  // sección aparece junto con el resto del resumen, sin pop-in.
  final needsSlotFallback =
      summary.setLogs.any((log) => !catalogById.containsKey(log.exerciseId));
  final slotGroupById = needsSlotFallback
      ? await slotMuscleGroupsForSessions(ref, [session])
      : const <String, String>{};

  final muscleGroupByExerciseId = <String, String>{
    ...catalogById,
    for (final entry in slotGroupById.entries)
      if (!catalogById.containsKey(entry.key)) entry.key: entry.value,
  };

  return aggregateSessionMuscleDistribution(
    setLogs: summary.setLogs,
    muscleGroupByExerciseId: muscleGroupByExerciseId,
  );
});
