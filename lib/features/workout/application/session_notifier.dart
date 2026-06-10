import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../domain/routine_day.dart';
import '../domain/set_log.dart';
import '../../workout/application/routine_providers.dart';
import 'session_init.dart';
import 'session_providers.dart';
import 'session_state.dart';

/// Notifier de sesión activa. Despacha Path A (FreshSession) o Path B
/// (ResumeSession) via switch sobre el arg sellado. Diseño §3.3.
/// Base class: AutoDisposeFamilyAsyncNotifier (requerido por
/// AsyncNotifierProvider.autoDispose.family en Riverpod 2.x).
class SessionNotifier
    extends AutoDisposeFamilyAsyncNotifier<SessionState, SessionInit> {
  Timer? _timer;
  bool _finalized = false;

  @override
  Future<SessionState> build(SessionInit arg) async {
    final state = switch (arg) {
      FreshSession(
        routineId: final rid,
        dayNumber: final dn,
        weekNumber: final wn,
      ) =>
        await _buildFresh(rid, dn, wn),
      ResumeSession(sessionId: final sid) => await _buildResume(sid),
    };

    // El timer empieza DESPUÉS de armar el estado para que ambos paths
    // compartan el mismo punto de inicio. Diseño §7.
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    return state;
  }

  // ── Path A — Sesión nueva ─────────────────────────────────────────────────

  Future<SessionState> _buildFresh(
    String routineId,
    int dayNumber,
    int weekNumber,
  ) async {
    final routine = await ref.read(routineByIdProvider(routineId).future);
    if (routine == null) {
      throw StateError('Rutina $routineId no encontrada');
    }
    final day = routine.days.firstWhere(
      (d) => d.dayNumber == dayNumber,
      orElse: () => throw StateError(
        'Día $dayNumber no encontrado en rutina $routineId',
      ),
    );

    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      throw StateError('SessionNotifier construido sin usuario autenticado');
    }
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routine.name,
      startedAt: DateTime.now(),
      dayNumber: dayNumber,
      weekNumber: weekNumber,
    );

    return SessionState(
      session: session,
      day: day,
      setLogs: const [],
      currentExerciseIndex: 0,
      elapsedSeconds: 0,
    );
  }

  // ── Path B — Retomar sesión existente ────────────────────────────────────

  Future<SessionState> _buildResume(String sessionId) async {
    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      throw StateError('Resume solicitado sin usuario autenticado');
    }

    // Adaptación al contrato real de Etapa 1: getActive + listSetLogs.
    final session = await repo.getActive(uid);
    if (session == null) {
      throw StateError(
        'Resume solicitado para $sessionId pero no hay sesión activa',
      );
    }
    if (session.id != sessionId) {
      throw StateError(
        'Sesión activa ${session.id} no coincide con la solicitada $sessionId',
      );
    }
    final recoveredLogs = await repo.listSetLogs(
      uid: uid,
      sessionId: session.id,
    );

    final routine =
        await ref.read(routineByIdProvider(session.routineId).future);
    if (routine == null) {
      throw StateError('Rutina ${session.routineId} no encontrada');
    }
    final day = routine.days.firstWhere(
      (d) => d.dayNumber == session.dayNumber,
      orElse: () => throw StateError(
        'Día ${session.dayNumber} no encontrado en rutina ${session.routineId}',
      ),
    );

    final currentIndex =
        _nextIncompleteIndex(day, recoveredLogs, session.weekNumber);
    final elapsed = DateTime.now()
        .difference(session.startedAt)
        .inSeconds
        .clamp(0, 1 << 31);

    return SessionState(
      session: session,
      day: day,
      setLogs: List<SetLog>.unmodifiable(recoveredLogs),
      currentExerciseIndex: currentIndex,
      elapsedSeconds: elapsed,
    );
  }

  // ── Mutaciones públicas ───────────────────────────────────────────────────

  Future<void> logSet(SetLog setLog) async {
    final current = state.value;
    if (current == null || _finalized) return;

    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    // El repo asigna el id de Firestore al doc y devuelve el SetLog
    // persisted — usamos ese para que `updateSet` futuro pueda referirse
    // por id (sino el log local quedaría con id=''').
    final persisted = await repo.addSetLog(
      uid: uid,
      sessionId: current.session.id,
      setLog: setLog,
    );

    final newLogs = [...current.setLogs, persisted];
    final newIndex =
        _nextIncompleteIndex(current.day, newLogs, current.session.weekNumber);

    state = AsyncData(current.copyWith(
      setLogs: newLogs,
      currentExerciseIndex: newIndex,
    ));
  }

  /// Actualiza un set ya logueado con nuevos reps/peso. Llamado por el
  /// flow de edición inline cuando el usuario corrige una fila done.
  /// [updated] debe traer el id existente en Firestore.
  Future<void> updateSet(SetLog updated) async {
    final current = state.value;
    if (current == null || _finalized) return;
    if (updated.id.isEmpty) {
      throw StateError('updateSet requires an existing SetLog id');
    }

    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    await repo.updateSetLog(
      uid: uid,
      sessionId: current.session.id,
      setLog: updated,
    );

    final newLogs = current.setLogs
        .map((l) => l.id == updated.id ? updated : l)
        .toList(growable: false);
    state = AsyncData(current.copyWith(setLogs: newLogs));
  }

  Future<void> abandonSession() async {
    if (_finalized) return;
    final current = state.value;
    if (current == null) return;

    _finalize();
    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    await repo.finish(
      uid: uid,
      sessionId: current.session.id,
      finishedAt: DateTime.now(),
      wasFullyCompleted: false,
      totalVolumeKg: current.totalVolumeKg,
      durationMin: _durationMin(current.elapsedSeconds),
    );
    state = AsyncData(current.copyWith(
      session: current.session.copyWith(wasFullyCompleted: false),
    ));
  }

  Future<void> finishSession() async {
    if (_finalized) return;
    final current = state.value;
    if (current == null) return;
    if (!current.isFullyCompleted) {
      throw StateError(
          'finishSession llamado antes de que isFullyCompleted sea true');
    }

    _finalize();
    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    await repo.finish(
      uid: uid,
      sessionId: current.session.id,
      finishedAt: DateTime.now(),
      wasFullyCompleted: true,
      totalVolumeKg: current.totalVolumeKg,
      durationMin: _durationMin(current.elapsedSeconds),
    );
    // Solo en el path "finished fully completed" — los abandonos no cuentan
    // como "routine_finished" para producto. Si más adelante producto pide
    // ver abandons, se agrega `routine_abandoned` aparte.
    ref.read(analyticsServiceProvider).logRoutineFinished(
          routineId: current.session.routineId,
          sessionId: current.session.id,
          durationSeconds: current.elapsedSeconds,
        );
    state = AsyncData(current.copyWith(
      session: current.session.copyWith(wasFullyCompleted: true),
    ));
  }

  // ── Helpers privados ─────────────────────────────────────────────────────

  void _onTick(Timer _) {
    final current = state.value;
    if (current == null || _finalized) return;
    final elapsed =
        DateTime.now().difference(current.session.startedAt).inSeconds;
    state = AsyncData(current.copyWith(elapsedSeconds: elapsed));
  }

  void _finalize() {
    _finalized = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Returns the index of the first slot that still needs sets logged.
  /// Uses [slot.effectiveSetsForWeek(weekNumber).length] so periodized plans
  /// respect the correct week's prescription. (REQ-PERIOD-040)
  /// Single-week sessions pass weekNumber=0; effectiveSetsForWeek(0) falls
  /// back to effectiveSets semantics (REQ-PERIOD-042 backward-compat).
  int _nextIncompleteIndex(RoutineDay day, List<SetLog> logs, int weekNumber) {
    for (var i = 0; i < day.slots.length; i++) {
      final slot = day.slots[i];
      final count = logs.where((l) => l.exerciseId == slot.exerciseId).length;
      if (count < slot.effectiveSetsForWeek(weekNumber).length) return i;
    }
    return day.slots.length - 1;
  }

  int _durationMin(int elapsedSeconds) {
    if (elapsedSeconds <= 0) return 1;
    return (elapsedSeconds + 59) ~/ 60;
  }
}
