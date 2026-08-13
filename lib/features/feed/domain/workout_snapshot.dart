import 'package:freezed_annotation/freezed_annotation.dart';

import '../../insights/domain/radar_axis.dart';
import '../../workout/domain/set_log.dart';

part 'workout_snapshot.freezed.dart';
part 'workout_snapshot.g.dart';

/// Cap de ejercicios embebidos en un [WorkoutSnapshot]. Espejo del bound
/// `exercises.size() <= 30` en firestore.rules (bloque posts) — el snapshot
/// viaja embebido en el doc del post y el límite de 1 MiB por doc es el
/// backstop duro; este cap mantiene el doc chico en el caso normal.
const int kMaxSnapshotExercises = 30;

/// Detalle del entrenamiento embebido en un [Post] de share-a-workout, para
/// que OTROS usuarios vean el desglose (ejercicios con sets/reps/peso) + la
/// distribución muscular, como el historial propio del autor.
///
/// Es un SNAPSHOT denormalizado a propósito: las sesiones viven en
/// `users/{uid}/sessions` y firestore.rules solo se las deja leer al dueño
/// (o a su trainer vía session_share), así que el detalle NO puede leerse
/// del origen — se congela al compartir, igual que [WorkoutStats].
///
/// Null en posts manuales y en posts legacy que preceden este campo — la
/// card del feed esconde la sección expandible en ese caso.
@freezed
class WorkoutSnapshot with _$WorkoutSnapshot {
  const factory WorkoutSnapshot({
    /// Ejercicios en orden de primera aparición en la sesión, cada uno con
    /// sus [SetLog] completos — el render rehidrata y reusa
    /// `SessionExerciseBlock` tal cual, sin adaptadores.
    required List<WorkoutSnapshotExercise> exercises,

    /// Sets por eje del radar, key = `RadarAxis.name` ('back', 'chest', …).
    /// Sparse — solo ejes con ≥1 set — igual que
    /// `SessionMuscleDistribution.setsByAxis`. Precomputado al compartir
    /// porque el viewer no puede resolver exerciseId → muscleGroup de
    /// ejercicios custom ajenos (la rutina del autor es privada).
    @Default(<String, int>{}) Map<String, int> setsByAxis,

    /// Volumen (reps × kg) por eje del radar, misma key y sparseness que
    /// [setsByAxis].
    @Default(<String, double>{}) Map<String, double> volumeKgByAxis,

    /// True si la sesión tenía más de [kMaxSnapshotExercises] ejercicios y
    /// la lista quedó truncada.
    @Default(false) bool truncated,
  }) = _WorkoutSnapshot;

  factory WorkoutSnapshot.fromJson(Map<String, Object?> json) =>
      _$WorkoutSnapshotFromJson(json);
}

/// Un ejercicio del snapshot: nombre + sus sets, en el mismo shape que
/// consume `SessionExerciseBlock(exerciseName:, sets:)`.
@freezed
class WorkoutSnapshotExercise with _$WorkoutSnapshotExercise {
  const factory WorkoutSnapshotExercise({
    required String exerciseName,
    required List<SetLog> sets,
  }) = _WorkoutSnapshotExercise;

  factory WorkoutSnapshotExercise.fromJson(Map<String, Object?> json) =>
      _$WorkoutSnapshotExerciseFromJson(json);
}

/// Builder puro del snapshot — sin Riverpod, fully testable.
///
/// Agrupa [setLogs] por `exerciseName` preservando orden de primera
/// aparición (mismo fold que `SessionDetailScreen`: map literal `{}` es
/// LinkedHashMap en Dart) y trunca a [kMaxSnapshotExercises] ejercicios,
/// marcando [WorkoutSnapshot.truncated].
///
/// [setsByAxis] / [volumeKgByAxis] vienen del agregador por-sesión
/// (`aggregateSessionMuscleDistribution`) — acá solo se serializan las keys
/// a `RadarAxis.name`.
WorkoutSnapshot buildWorkoutSnapshot({
  required List<SetLog> setLogs,
  Map<RadarAxis, int> setsByAxis = const {},
  Map<RadarAxis, double> volumeKgByAxis = const {},
}) {
  final grouped = <String, List<SetLog>>{};
  for (final log in setLogs) {
    grouped.putIfAbsent(log.exerciseName, () => []).add(log);
  }
  return WorkoutSnapshot(
    exercises: [
      for (final entry in grouped.entries.take(kMaxSnapshotExercises))
        WorkoutSnapshotExercise(exerciseName: entry.key, sets: entry.value),
    ],
    setsByAxis: {
      for (final entry in setsByAxis.entries) entry.key.name: entry.value,
    },
    volumeKgByAxis: {
      for (final entry in volumeKgByAxis.entries) entry.key.name: entry.value,
    },
    truncated: grouped.length > kMaxSnapshotExercises,
  );
}
