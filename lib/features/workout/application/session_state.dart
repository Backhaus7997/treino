import 'package:flutter/foundation.dart';

import '../domain/routine_day.dart';
import '../domain/routine_slot.dart';
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
    this.setCountOverride = const {},
  });

  final Session session;
  final RoutineDay day;
  final List<SetLog> setLogs;
  final int currentExerciseIndex;
  final int elapsedSeconds;

  /// Session-local per-exercise ABSOLUTE set-count override
  /// (exerciseId -> sets-today). Empty = no exercise was changed this
  /// session, fall back to the plan count everywhere. Populated only via
  /// [SessionNotifier.addSet]/`removeSet` (live-set-editing AD-1). NEVER a
  /// delta — always the absolute count to render/gate against.
  final Map<String, int> setCountOverride;

  // ── Getters derivados ────────────────────────────────────────────────────

  /// 0-based week number active in this session (from [session.weekNumber]).
  /// Single-week sessions use 0; effectiveSetsForWeek(0) falls back to
  /// effectiveSets semantics, keeping behavior identical. (REQ-PERIOD-040)
  int get activeWeek => session.weekNumber;

  /// The session-local "sets today" for [slot] — THE single resolver every
  /// completion/render denominator must route through (live-set-editing
  /// AD-1/AD-5). Returns the override when the athlete added/removed a set
  /// for this exercise this session; otherwise falls back to the plan's
  /// [RoutineSlot.effectiveSetsForWeek] count. Never reads the plan count
  /// directly outside this method — every other site (isFullyCompleted,
  /// isExerciseDone, and the 7 sites in session_notifier.dart /
  /// session_player_screen.dart) call this instead.
  int plannedSetsFor(RoutineSlot slot) {
    final planned = slot.effectiveSetsForWeek(session.weekNumber).length;
    return setCountOverride[slot.exerciseId] ?? planned;
  }

  /// Verdadero cuando cada slot del día tiene al menos `plannedSetsFor(slot)` logs.
  ///
  /// QA-WKT-005: un día sin trabajo a hacer NO cuenta como completado. Sin este
  /// guard, un día con `slots: []` (o una semana donde todos los slots quedan
  /// enmascarados por presencia, con `plannedSetsFor == 0`) daba `every` sobre
  /// nada = `true`, así que una sesión de 0 sets quedaba instantáneamente
  /// "completa" → habilitaba TERMINAR, incrementaba workoutsCount/racha y
  /// marcaba el día del plan como hecho (farmeo de racha en dos taps).
  bool get isFullyCompleted {
    final totalPlanned =
        day.slots.fold<int>(0, (sum, slot) => sum + plannedSetsFor(slot));
    if (totalPlanned == 0) return false;
    return day.slots.every(
      (slot) => setsLoggedFor(slot.exerciseId) >= plannedSetsFor(slot),
    );
  }

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
    return setsLoggedFor(exerciseId) >= plannedSetsFor(slot);
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
    Map<String, int>? setCountOverride,
  }) =>
      SessionState(
        session: session ?? this.session,
        day: day ?? this.day,
        setLogs: setLogs ?? this.setLogs,
        currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        setCountOverride: setCountOverride ?? this.setCountOverride,
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
          elapsedSeconds == other.elapsedSeconds &&
          mapEquals(setCountOverride, other.setCountOverride);

  @override
  int get hashCode => Object.hash(
        session,
        day,
        Object.hashAll(setLogs),
        currentExerciseIndex,
        elapsedSeconds,
        Object.hashAllUnordered(
          setCountOverride.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
}
