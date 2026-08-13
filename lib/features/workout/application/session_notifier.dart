import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../domain/routine_day.dart';
import '../domain/routine_slot.dart';
import '../domain/set_log.dart';
import '../../workout/application/routine_providers.dart';
import 'session_init.dart';
import 'session_duration.dart';
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
  int _elapsedBaseSeconds = 0;
  DateTime? _elapsedBaseAt;

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
    _resetElapsedBaseline(elapsedSeconds: 0, at: session.startedAt);

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

    // No setCountOverride exists yet at build time (it is session-local and
    // starts empty every resume — live-set-editing PR1 doesn't persist it),
    // so the plain weekNumber-based resolution is correct here.
    final currentIndex =
        _nextIncompleteIndex(sessionDay, recoveredLogs, session.weekNumber);
    final now = DateTime.now();
    final elapsed = sanitizedActiveSessionElapsedSeconds(
      session: session,
      setLogs: recoveredLogs,
      now: now,
    );
    _resetElapsedBaseline(elapsedSeconds: elapsed, at: now);

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
        latest.plannedSetsFor,
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

  /// Agrega un set extra a [slot] más allá del plan actual (live-set-editing
  /// AD-1/AD-2). SOLO bumpea `setCountOverride[slot.exerciseId]` a
  /// `plannedSetsFor(slot) + 1` — NO escribe ningún `setLog` acá. La fila
  /// nueva se renderiza vacía (AD-4, sin SetSpec) y el write real ocurre
  /// cuando el athlete la completa y dispara el `logSet` existente con
  /// `setNumber = newCount`. La idempotencia por `exerciseId+setNumber` de
  /// `logSet` (línea ~207) ya cubre un doble-tap sobre esa fila nueva — no se
  /// necesita un guard nuevo.
  Future<void> addSet(RoutineSlot slot) async {
    final current = state.value;
    if (current == null || _finalized) return;

    final newCount = current.plannedSetsFor(slot) + 1;
    state = AsyncData(current.copyWith(
      setCountOverride: {
        ...current.setCountOverride,
        slot.exerciseId: newCount,
      },
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

  /// Elimina un set de [slot] (live-set-editing AD-2/AD-3/AD-5).
  ///
  /// [target] es el `SetLog` ya persistido si la fila estaba logueada, o
  /// `null` si es una fila pendiente/sin loguear (el "+ agregar serie" que
  /// todavía no se completó) — en ese caso NO hay write a Firestore, solo se
  /// baja el override.
  ///
  /// Sigue la misma disciplina de race que [updateSet]: re-lee `state.value`
  /// DESPUÉS de cada await (nunca sobrescribe con el snapshot capturado antes
  /// del await), nunca muta `state` a `AsyncError` ante un fallo (emite por
  /// `_logSetError` en su lugar), y respeta `_finalized`.
  ///
  /// Si [target] existe: borra el doc vía [SessionRepository.deleteSetLog] y
  /// renumera los sobrevivientes de ese ejercicio con `setNumber >
  /// target.setNumber` (AD-3, denso 1..N — nunca deja un hueco visible). El
  /// denominador de gating es SIEMPRE la cantidad de logs, nunca el
  /// `setNumber` máximo, así que un renumber parcialmente fallido no puede
  /// trabar la finalización (misma postura de fallo que un `logSet` fallido).
  ///
  /// El override nuevo queda floored al conteo de logs sobrevivientes
  /// (AD-5): `max(plannedSetsFor(slot) - 1, loggedCountAfterRemoval)` — nunca
  /// se puede esconder una fila ya logueada bajando el override por debajo de
  /// lo que ya existe.
  Future<void> removeSet(RoutineSlot slot, SetLog? target) async {
    final current = state.value;
    if (current == null || _finalized) return;

    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final repo = ref.read(sessionRepositoryProvider);
    final exerciseId = slot.exerciseId;

    try {
      List<SetLog> survivorsAbove = const [];
      if (target != null && target.id.isNotEmpty) {
        await repo.deleteSetLog(
          uid: uid,
          sessionId: current.session.id,
          setLogId: target.id,
        );

        // Renumber survivors of the SAME exercise with setNumber > the
        // deleted one, ascending order, dense 1..N (AD-3). Bounded to
        // survivors above the gap.
        survivorsAbove = current.setLogs
            .where((l) =>
                l.exerciseId == exerciseId && l.setNumber > target.setNumber)
            .toList(growable: false)
          ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
        for (final survivor in survivorsAbove) {
          await repo.updateSetLog(
            uid: uid,
            sessionId: current.session.id,
            setLog: survivor.copyWith(setNumber: survivor.setNumber - 1),
          );
        }
      }

      // Re-leemos el estado DESPUÉS de todos los awaits: pudo cambiar durante
      // el delete/renumber (p.ej. un logSet concurrente). Mismo patrón que
      // logSet/updateSet.
      final latest = state.value ?? current;
      final renumberedIds = {for (final s in survivorsAbove) s.id};
      final newLogs = latest.setLogs
          .where((l) => target == null || l.id != target.id)
          .map((l) => renumberedIds.contains(l.id)
              ? l.copyWith(setNumber: l.setNumber - 1)
              : l)
          .toList(growable: false);
      final loggedCountAfterRemoval =
          newLogs.where((l) => l.exerciseId == exerciseId).length;
      final lowered = latest.plannedSetsFor(slot) - 1;
      final newCount =
          lowered < loggedCountAfterRemoval ? loggedCountAfterRemoval : lowered;
      final newOverride = {...latest.setCountOverride, exerciseId: newCount};
      final newIndex = _nextIncompleteIndex(
        latest.day,
        newLogs,
        latest.session.weekNumber,
        (s) => s.exerciseId == exerciseId
            ? newCount
            : (latest.setCountOverride[s.exerciseId] ??
                s.effectiveSetsForWeek(latest.session.weekNumber).length),
      );

      state = AsyncData(latest.copyWith(
        setLogs: newLogs,
        setCountOverride: newOverride,
        currentExerciseIndex: newIndex,
      ));
    } catch (e) {
      // Mismo canal separado que logSet/updateSet: NO mutamos `state` a
      // AsyncError (volaría toda la sesión activa vía when() error:).
      _logSetError.value = SessionLogError(
        action: SessionLogAction.remove,
        setLog: target,
        slot: slot,
      );
    }
  }

  /// Reintenta la última operación de log/update/remove que falló. Lo invoca
  /// la acción "Reintentá" del SnackBar (capa de UI). Limpia el canal de
  /// error y re-despacha hacia logSet/updateSet/removeSet, que volverán a
  /// emitir por el canal si vuelve a fallar.
  Future<void> retryLastLogError() async {
    final pending = _logSetError.value;
    if (pending == null) return;
    _logSetError.value = null;
    switch (pending.action) {
      case SessionLogAction.log:
        await logSet(pending.setLog!);
      case SessionLogAction.update:
        await updateSet(pending.setLog!);
      case SessionLogAction.remove:
        await removeSet(pending.slot!, pending.setLog);
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
    // #367: same session-cache refresh as finishSession — the abandoned session
    // is now persisted, so historial and any session-derived view reflect it
    // (and the no-longer-active session clears) without an app restart.
    // Same audited post-dispose contract as finishSession (#497) — see there.
    ref.invalidate(sessionsByUidProvider(uid));
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
    // #497 (audited, riverpod 2.6.1): everything below runs AFTER an await, and
    // the player's `PopScope(canPop: _isFinalizing)` lets the route pop while
    // the write is in flight — so this notifier can already be disposed here.
    // That is survivable, not broken: `Ref.invalidate`/`Ref.read` delegate to
    // the container (still alive), and assigning `state` on a disposed element
    // is a tolerated no-op. The refresh and the analytics event both land.
    // Riverpod 3.x turns ref-after-dispose into an error — the tripwires in
    // session_notifier_dispose_race_test.dart go red when that day comes, and
    // the fix is a `ref.keepAlive()` across the write plus a `_disposed` guard.
    //
    // #367: refresh the session-derived caches so Home's "HOY" card advances to
    // the next plan day and Insights include this session WITHOUT restarting the
    // app. sessionsByUidProvider is a one-shot autoDispose future that never
    // re-fetches on its own here — the session player is a top-level route ABOVE
    // the shell, so the shell screens watching it stay mounted the whole workout
    // and its autoDispose cache is never released. Everything downstream
    // (todaysRoutineProvider, the Insights aggregators, historial) watches this
    // provider, so a single invalidate cascades.
    ref.invalidate(sessionsByUidProvider(uid));
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
    final elapsed = _elapsedSecondsNow();
    state = AsyncData(current.copyWith(elapsedSeconds: elapsed));
  }

  void _finalize() {
    _finalized = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Returns the index of the first slot that still needs sets logged.
  ///
  /// [plannedCountFor] resolves the session-local "sets today" for a slot
  /// (live-set-editing AD-1/AD-5, [SITE-3]) — pass
  /// `state.value?.plannedSetsFor` (bound method) from every call site so an
  /// added-beyond-plan set keeps the cursor on its exercise instead of
  /// advancing, and a removed-below-logged set doesn't wait forever. Falls
  /// back to the raw [RoutineSlot.effectiveSetsForWeek] count via [weekNumber]
  /// when no resolver is supplied (keeps existing call sites compiling without
  /// forcing every caller to thread state through immediately).
  /// Single-week sessions pass weekNumber=0; effectiveSetsForWeek(0) falls
  /// back to effectiveSets semantics (REQ-PERIOD-042 backward-compat).
  int _nextIncompleteIndex(
    RoutineDay day,
    List<SetLog> logs,
    int weekNumber, [
    int Function(RoutineSlot)? plannedCountFor,
  ]) {
    for (var i = 0; i < day.slots.length; i++) {
      final slot = day.slots[i];
      final count = logs.where((l) => l.exerciseId == slot.exerciseId).length;
      final planned = plannedCountFor != null
          ? plannedCountFor(slot)
          : slot.effectiveSetsForWeek(weekNumber).length;
      if (count < planned) return i;
    }
    return day.slots.length - 1;
  }

  int _durationMin(int elapsedSeconds) {
    if (elapsedSeconds <= 0) return 1;
    final bounded = elapsedSeconds.clamp(0, maxWorkoutDuration.inSeconds);
    return (bounded + 59) ~/ 60;
  }

  void _resetElapsedBaseline({
    required int elapsedSeconds,
    required DateTime at,
  }) {
    _elapsedBaseSeconds = elapsedSeconds.clamp(
      0,
      maxWorkoutDuration.inSeconds,
    );
    _elapsedBaseAt = at;
  }

  int _elapsedSecondsNow() {
    final baseAt = _elapsedBaseAt;
    if (baseAt == null) return 0;
    final elapsed =
        _elapsedBaseSeconds + DateTime.now().difference(baseAt).inSeconds;
    return elapsed.clamp(0, maxWorkoutDuration.inSeconds);
  }
}

/// Qué operación de set falló, para que el reintento despache al método correcto.
enum SessionLogAction { log, update, remove }

/// Evento de fallo de log/update/remove de set emitido por
/// [SessionNotifier.logSetError].
///
/// Viaja por un canal separado del AsyncValue para que la UI pueda mostrar
/// feedback visible (SnackBar con copy `sessionLogSetError` + acción Reintentar
/// → [SessionNotifier.retryLastLogError]) SIN destruir la sesión activa.
///
/// [setLog] es requerido para `log`/`update` pero puede ser `null` para
/// `remove` (una fila pendiente/sin loguear no tiene doc que referenciar).
/// [slot] solo es requerido por `remove` (live-set-editing AD-2) — `log`/
/// `update` no lo necesitan porque [setLog] ya trae `exerciseId`.
@immutable
class SessionLogError {
  const SessionLogError({
    required this.action,
    required this.setLog,
    this.slot,
  });

  final SessionLogAction action;
  final SetLog? setLog;
  final RoutineSlot? slot;
}
