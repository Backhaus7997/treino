import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// Canal de error SEPARADO del AsyncValue.
  ///
  /// Por qué no mutamos `state` a AsyncError en un fallo de logSet/updateSet:
  /// la pantalla renderiza via `sessionAsync.when(...)` con flags por defecto
  /// (skipError:false). En Riverpod 2.6.1, `when()` enruta al branch `error:`
  /// cuando `hasError && (!hasValue || !skipError)`. Un AsyncError.copyWithPrevious
  /// conserva `hasValue==true` PERO también `hasError==true`, así que `when()`
  /// igual cae en `error:` y vuela TODA la UI de sesión activa (timer, stats,
  /// sets logueados) por un único set que falló — peor que el no-op anterior.
  ///
  /// En su lugar emitimos el fallo por este ValueNotifier sin tocar el estado
  /// de datos: la sesión activa sigue intacta y la UI puede escucharlo
  /// (addListener / ref.listen) para mostrar un SnackBar con Reintentar
  /// (copy: sessionLogSetError) y reaccionar sin perder la pantalla.
  final ValueNotifier<SessionLogError?> _logSetError =
      ValueNotifier<SessionLogError?>(null);

  /// Canal observable de fallos de log/update de sets. La capa de UI lo escucha
  /// para feedback visible (SnackBar + Reintentar) sin destruir la sesión.
  ValueListenable<SessionLogError?> get logSetError => _logSetError;

  /// La UI llama esto al mostrar el feedback para no re-emitir el mismo error.
  void clearLogSetError() => _logSetError.value = null;

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
      _logSetError.dispose();
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

    // Clamp weekNumber into [0, numWeeks-1] so a malformed URL like
    // ?week=99 on a 2-week plan or ?week=-1 never persists an out-of-range
    // value to Firestore. The upper bound is floored at 0 because a corrupt
    // doc with numWeeks <= 0 would otherwise make clamp() throw (upper < lower).
    final maxWeek = routine.numWeeks > 1 ? routine.numWeeks - 1 : 0;
    final clampedWeek = weekNumber.clamp(0, maxWeek);

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
      weekNumber: clampedWeek,
    );

    // REQ-WPRES-021 (ADR-WPRES-09): filter slots by presence BEFORE building
    // session state so buildBlocks, isFullyCompleted, _nextIncompleteIndex,
    // and completedExerciseCount all see only the present slots. Filtering
    // here — not in the render — prevents completion deadlocks for absent slots.
    // numWeeks==1 → all masks empty → presentSlots == day.slots (invariant).
    final presentSlots = [
      for (final s in day.slots)
        if (s.isPresentInWeek(clampedWeek)) s
    ];
    final sessionDay = day.copyWith(slots: presentSlots);

    return SessionState(
      session: session,
      day: sessionDay,
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

    // REQ-WPRES-021 (ADR-WPRES-09): apply the same presence filter as _buildFresh
    // so resumed sessions also see only slots present in session.weekNumber.
    final presentSlots = [
      for (final s in day.slots)
        if (s.isPresentInWeek(session.weekNumber)) s
    ];
    final sessionDay = day.copyWith(slots: presentSlots);

    final currentIndex =
        _nextIncompleteIndex(sessionDay, recoveredLogs, session.weekNumber);
    final elapsed = DateTime.now()
        .difference(session.startedAt)
        .inSeconds
        .clamp(0, 1 << 31);

    return SessionState(
      session: session,
      day: sessionDay,
      setLogs: List<SetLog>.unmodifiable(recoveredLogs),
      currentExerciseIndex: currentIndex,
      elapsedSeconds: elapsed,
    );
  }

  // ── Mutaciones públicas ───────────────────────────────────────────────────

  /// Guard anti doble-tap: mientras un logSet está persistiendo en Firestore
  /// (~300ms), ignora taps adicionales. Sin esto, cada tap extra creaba un doc
  /// nuevo → sets duplicados masivamente en el historial (device feedback
  /// 2026-06-12).
  bool _isLoggingSet = false;

  Future<void> logSet(SetLog setLog) async {
    final current = state.value;
    if (current == null || _finalized || _isLoggingSet) return;

    // Idempotencia por identidad lógica del set (exerciseId + setNumber): si esa
    // serie de ese ejercicio ya quedó logueada, no la dupliques. Cubre también
    // taps secuenciales sobre un set ya marcado, no solo la race del doble-tap.
    final alreadyLogged = current.setLogs.any(
      (l) =>
          l.exerciseId == setLog.exerciseId && l.setNumber == setLog.setNumber,
    );
    if (alreadyLogged) return;

    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    _isLoggingSet = true;
    try {
      final repo = ref.read(sessionRepositoryProvider);
      // El repo asigna el id de Firestore al doc y devuelve el SetLog
      // persisted — usamos ese para que `updateSet` futuro pueda referirse
      // por id (sino el log local quedaría con id='').
      final persisted = await repo.addSetLog(
        uid: uid,
        sessionId: current.session.id,
        setLog: setLog,
      );

      // Re-leemos el estado: pudo cambiar durante el await.
      final latest = state.value ?? current;
      final newLogs = [...latest.setLogs, persisted];
      final newIndex = _nextIncompleteIndex(
        latest.day,
        newLogs,
        latest.session.weekNumber,
      );

      state = AsyncData(latest.copyWith(
        setLogs: newLogs,
        currentExerciseIndex: newIndex,
      ));
    } catch (e) {
      // El write a Firestore falló (red caída, permisos, offline). NO mutamos
      // `state` a AsyncError: eso flipearía `when()` al branch `error:` y volaría
      // toda la sesión activa por un solo set fallido (ver doc de _logSetError).
      // Emitimos el fallo por el canal separado conservando la acción para que la
      // UI pueda mostrar SnackBar + Reintentar. setLogs no se toca: no hubo
      // optimismo que revertir, así que la fila sigue interactiva sin loguear.
      _logSetError.value =
          SessionLogError(action: SessionLogAction.log, setLog: setLog);
    } finally {
      _isLoggingSet = false;
    }
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

    try {
      await repo.updateSetLog(
        uid: uid,
        sessionId: current.session.id,
        setLog: updated,
      );

      // Re-leemos el estado: pudo cambiar durante el await (p.ej. un logSet
      // concurrente). Sin esto, sobrescribiríamos con el snapshot viejo y
      // perderíamos el set recién logueado. Mismo patrón que logSet.
      final latest = state.value ?? current;
      final newLogs = latest.setLogs
          .map((l) => l.id == updated.id ? updated : l)
          .toList(growable: false);
      state = AsyncData(latest.copyWith(setLogs: newLogs));
    } catch (e) {
      // Mismo fallo silencioso que logSet: editar el peso/reps de una serie ya
      // hecha podía romper el write sin feedback. NO mutamos `state` a AsyncError
      // (volaría la sesión via when() error:). Emitimos por el canal separado
      // para que la UI muestre SnackBar + Reintentar. El cambio local no se aplica:
      // la fila sigue mostrando el valor previamente persistido.
      _logSetError.value =
          SessionLogError(action: SessionLogAction.update, setLog: updated);
    }
  }

  /// Reintenta la última operación de log/update que falló. Lo invoca la acción
  /// "Reintentá" del SnackBar (capa de UI). Limpia el canal de error y re-despacha
  /// hacia logSet/updateSet, que volverán a emitir por el canal si vuelve a fallar.
  Future<void> retryLastLogError() async {
    final pending = _logSetError.value;
    if (pending == null) return;
    _logSetError.value = null;
    switch (pending.action) {
      case SessionLogAction.log:
        await logSet(pending.setLog);
      case SessionLogAction.update:
        await updateSet(pending.setLog);
    }
  }

  Future<void> abandonSession() async {
    if (_finalized) return;
    final current = state.value;
    if (current == null) return;

    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    // Mark finalized BEFORE the await so a concurrent abandon/finish call is a
    // no-op (the SCENARIO-266 double-finish guard). The timer is NOT cancelled
    // yet: if the write fails we reset _finalized and keep the notifier (and its
    // timer) alive so the user can retry. Only after the write succeeds do we
    // tear down the timer. Otherwise a failed Firestore write would leave the
    // session active in Firestore but the local notifier dead and frozen.
    _finalized = true;
    try {
      await repo.finish(
        uid: uid,
        sessionId: current.session.id,
        finishedAt: DateTime.now(),
        wasFullyCompleted: false,
        totalVolumeKg: current.totalVolumeKg,
        durationMin: _durationMin(current.elapsedSeconds),
      );
    } catch (_) {
      _finalized = false;
      rethrow;
    }
    _finalize();
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

    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    // Mark finalized BEFORE the await so a concurrent finish/abandon call is a
    // no-op. The timer stays alive until the write succeeds: on failure we reset
    // _finalized and keep the notifier usable so the user can retry, instead of
    // leaving the session active in Firestore while the local notifier is frozen.
    _finalized = true;
    try {
      await repo.finish(
        uid: uid,
        sessionId: current.session.id,
        finishedAt: DateTime.now(),
        wasFullyCompleted: true,
        totalVolumeKg: current.totalVolumeKg,
        durationMin: _durationMin(current.elapsedSeconds),
      );
    } catch (_) {
      _finalized = false;
      rethrow;
    }
    _finalize();
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

/// Qué operación de set falló, para que el reintento despache al método correcto.
enum SessionLogAction { log, update }

/// Evento de fallo de log/update de set emitido por [SessionNotifier.logSetError].
///
/// Viaja por un canal separado del AsyncValue para que la UI pueda mostrar
/// feedback visible (SnackBar con copy `sessionLogSetError` + acción Reintentar
/// → [SessionNotifier.retryLastLogError]) SIN destruir la sesión activa. Lleva el
/// [setLog] original para que el reintento re-despache la misma operación.
@immutable
class SessionLogError {
  const SessionLogError({required this.action, required this.setLog});

  final SessionLogAction action;
  final SetLog setLog;
}
