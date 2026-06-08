import 'package:flutter/foundation.dart';

import '../domain/routine_day.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';

/// DTO inmutable que representa el estado en memoria de la sesión activa.
///
/// NO usa @freezed — no se serializa, no requiere build_runner.
/// Los getters `isFullyCompleted` y `totalVolumeKg` son derivados (no almacenados)
/// para evitar inconsistencias en copyWith. Diseño §3.2.
@immutable
class SessionState {
  const SessionState({
    required this.session,
    required this.day,
    required this.setLogs,
    required this.currentExerciseIndex,
    required this.elapsedSeconds,
  });

  final Session session;
  final RoutineDay day;
  final List<SetLog> setLogs;
  final int currentExerciseIndex;
  final int elapsedSeconds;

  // ── Getters derivados ────────────────────────────────────────────────────

  /// Verdadero cuando cada slot del día tiene al menos `effectiveSets.length` logs.
  bool get isFullyCompleted => day.slots.every((slot) {
        final count = setsLoggedFor(slot.exerciseId);
        return count >= slot.effectiveSets.length;
      });

  /// Suma de reps × weightKg sobre todos los setLogs.
  double get totalVolumeKg =>
      setLogs.fold<double>(0.0, (sum, l) => sum + l.reps * l.weightKg);

  // ── UI helpers ────────────────────────────────────────────────────────────

  /// Cantidad de sets logueados para el ejercicio dado.
  int setsLoggedFor(String exerciseId) =>
      setLogs.where((l) => l.exerciseId == exerciseId).length;

  /// Verdadero si el ejercicio tiene todos sus sets completados.
  bool isExerciseDone(String exerciseId) {
    final slot = day.slots.firstWhere((s) => s.exerciseId == exerciseId);
    return setsLoggedFor(exerciseId) >= slot.effectiveSets.length;
  }

  /// Cantidad de ejercicios del día con todos sus sets completados.
  int get completedExerciseCount =>
      day.slots.where((s) => isExerciseDone(s.exerciseId)).length;

  // ── Mutación ──────────────────────────────────────────────────────────────

  SessionState copyWith({
    Session? session,
    RoutineDay? day,
    List<SetLog>? setLogs,
    int? currentExerciseIndex,
    int? elapsedSeconds,
  }) =>
      SessionState(
        session: session ?? this.session,
        day: day ?? this.day,
        setLogs: setLogs ?? this.setLogs,
        currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );

  // ── Igualdad estructural ──────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionState &&
          runtimeType == other.runtimeType &&
          session == other.session &&
          day == other.day &&
          listEquals(setLogs, other.setLogs) &&
          currentExerciseIndex == other.currentExerciseIndex &&
          elapsedSeconds == other.elapsedSeconds;

  @override
  int get hashCode => Object.hash(
        session,
        day,
        Object.hashAll(setLogs),
        currentExerciseIndex,
        elapsedSeconds,
      );
}
