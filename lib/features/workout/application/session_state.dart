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
    this.droppedExerciseIds = const {},
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

  /// Ejercicios que el atleta dejó FUERA DE HOY para que la sesión entrara en
  /// el tiempo que tenía (#645). Vacío = la sesión va tal como está el plan.
  ///
  /// Es local a la sesión, exactamente como [setCountOverride]: la rutina
  /// persistida NO se toca. Un plan que armó un PF sigue diciendo lo que
  /// decía; lo que cambia es lo que se hace hoy.
  ///
  /// Un ejercicio acá vale CERO series hoy — [plannedSetsFor] devuelve 0 — así
  /// que sale del denominador de [isFullyCompleted] y del cursor del player.
  /// Se lo mantiene aparte de [setCountOverride] y no como "override a 0"
  /// porque la UI necesita distinguir *sacado* de *hecho*: con sólo el
  /// override, un ejercicio recortado renderiza como bloque completado y el
  /// atleta lee "lo hiciste" sobre algo que no hizo.
  final Set<String> droppedExerciseIds;

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
  ///
  /// Un ejercicio en [droppedExerciseIds] vale 0 y gana sobre cualquier
  /// override: si se lo sacó de hoy, hoy no tiene series.
  int plannedSetsFor(RoutineSlot slot) {
    if (droppedExerciseIds.contains(slot.exerciseId)) return 0;
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
  ///
  /// **#645 — una sesión recortada a propósito SÍ cuenta como completa.** Los
  /// ejercicios en [droppedExerciseIds] valen 0 y por lo tanto salen del
  /// denominador: el atleta que declaró que tenía 40 minutos, eligió el
  /// recorte que la app le propuso e hizo todo lo que quedó, hizo todo lo que
  /// se propuso hacer hoy — que es exactamente la pregunta que
  /// `wasFullyCompleted` contesta. Marcarlo incompleto convertiría el feature
  /// en un castigo por usarlo, y es la misma semántica que ya tenía bajar
  /// series con `removeSet`, que también baja el denominador.
  ///
  /// El guard de `totalPlanned == 0` sigue cubriendo el borde: un recorte que
  /// deja la sesión en cero no completa nada. `planSessionTimeFit` además
  /// nunca propone ese recorte.
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

  /// Los slots que SÍ se hacen hoy — el día menos lo que se recortó (#645).
  /// Es el universo que la UI de progreso tiene que contar: un ejercicio
  /// sacado no es un pendiente ni un hecho, no está.
  Iterable<RoutineSlot> get activeSlots =>
      day.slots.where((s) => !droppedExerciseIds.contains(s.exerciseId));

  /// Cantidad de ejercicios que se hacen hoy. Denominador de "X / Y ejercicios".
  int get activeExerciseCount => activeSlots.length;

  /// Cantidad de ejercicios del día con todos sus sets completados.
  ///
  /// Los recortados NO cuentan: `plannedSetsFor` les da 0, así que
  /// [isExerciseDone] los daría por hechos y el contador diría "5/5" sobre una
  /// sesión de la que salieron dos.
  int get completedExerciseCount =>
      activeSlots.where((s) => isExerciseDone(s.exerciseId)).length;

  // ── Mutación ──────────────────────────────────────────────────────────────

  SessionState copyWith({
    Session? session,
    RoutineDay? day,
    List<SetLog>? setLogs,
    int? currentExerciseIndex,
    int? elapsedSeconds,
    Map<String, int>? setCountOverride,
    Set<String>? droppedExerciseIds,
  }) =>
      SessionState(
        session: session ?? this.session,
        day: day ?? this.day,
        setLogs: setLogs ?? this.setLogs,
        currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        setCountOverride: setCountOverride ?? this.setCountOverride,
        droppedExerciseIds: droppedExerciseIds ?? this.droppedExerciseIds,
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
          mapEquals(setCountOverride, other.setCountOverride) &&
          setEquals(droppedExerciseIds, other.droppedExerciseIds);

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
        Object.hashAllUnordered(droppedExerciseIds),
      );
}
