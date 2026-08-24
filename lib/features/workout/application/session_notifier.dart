import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/utils/network_timeouts.dart';
import '../../watch/application/watch_credential_providers.dart'
    show watchLauncherServiceProvider, watchNudgeServiceProvider;
import '../../watch/data/watch_launcher_service.dart';
import '../../watch/data/watch_nudge_service.dart';
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

  /// Suscripciones vivas a la sesión mientras el player está abierto.
  ///
  /// El RELOJ escribe en la MISMA sesión: series nuevas y el cierre del
  /// entreno. Sin escuchar, el teléfono se quedaba con la foto que sacó al
  /// abrir — el atleta marcaba en la muñeca y la pantalla del celular no se
  /// movía.
  StreamSubscription<List<SetLog>>? _setLogsSub;
  StreamSubscription<bool>? _finishedSub;

  /// Se dispara cuando el entreno se cerró DESDE OTRO LADO (el reloj).
  ///
  /// Canal aparte del estado por el mismo motivo que [_logSetError]: mutar el
  /// AsyncValue tiraría abajo toda la pantalla. La UI lo escucha para salir del
  /// player, que es lo correcto — la sesión ya está en el historial.
  final ValueNotifier<bool> _finishedElsewhere = ValueNotifier<bool>(false);

  /// La UI escucha esto para cerrar el player cuando el reloj terminó el
  /// entreno.
  ValueListenable<bool> get finishedElsewhere => _finishedElsewhere;

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
    _watchRemoteChanges(state.session.id);
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
      _setLogsSub?.cancel();
      _finishedSub?.cancel();
      _logSetError.dispose();
      _finishedElsewhere.dispose();
    });

    return state;
  }

  /// Engancha el estado a lo que pase con la sesión en Firestore.
  ///
  /// Es lo que vuelve al reloj un complemento de verdad: lo que se marca en la
  /// muñeca aparece en el teléfono sin que el atleta toque nada, y terminar en
  /// un lado termina en los dos.
  void _watchRemoteChanges(String sessionId) {
    final uid = ref.read(currentUidProvider);
    if (uid == null || uid.isEmpty) return;
    final repo = ref.read(sessionRepositoryProvider);

    _setLogsSub = repo
        .watchSetLogs(uid: uid, sessionId: sessionId)
        .listen(_applyRemoteSetLogs, onError: (_) {
      // Un stream caído no puede tumbar el entreno: se sigue con lo local,
      // que es exactamente el comportamiento que había antes de esto.
    });

    _finishedSub = repo
        .watchSessionFinished(uid: uid, sessionId: sessionId)
        .listen((finished) {
      if (!finished || _finalized) return;
      // Lo cerró el reloj. Se marca finalizado ANTES de avisar para que un
      // `finishSession`/`abandonSession` que llegue después sea no-op: escribir
      // encima pisaría el volumen y la duración que ya calculó el reloj.
      _finalized = true;
      _timer?.cancel();
      _timer = null;
      _finishedElsewhere.value = true;
      final currentUid = ref.read(currentUidProvider);
      if (currentUid != null) ref.invalidate(sessionsByUidProvider(currentUid));
    }, onError: (_) {});
  }

  /// Deja UNA sola serie por `exerciseId + setNumber`, quedándose con la
  /// primera.
  ///
  /// Es un INVARIANTE, no un parche puntual. Dos series con la misma identidad
  /// lógica no existen: el teléfono las contaba doble, inflaba el volumen, daba
  /// un ejercicio por terminado antes de tiempo y bloqueaba la serie siguiente.
  ///
  /// Se aplica en el único punto donde el estado recibe una lista MEZCLADA —
  /// local + lo que llega del stream— en vez de confiar en que cada camino
  /// chequee. Perseguir camino por camino ya falló una vez: se arregló `logSet`
  /// y el estado volvió a duplicar por otra ventana de carrera que no pude
  /// aislar. Un invariante en un solo lugar no depende de haberlos encontrado
  /// a todos.
  ///
  /// Devuelve la MISMA lista si no había nada que sacar, para no crear objetos
  /// nuevos en el camino caliente.
  static List<SetLog> _dedupedLogs(List<SetLog> logs) {
    final seen = <String>{};
    final out = <SetLog>[];
    for (final l in logs) {
      if (seen.add('${l.exerciseId}__${l.setNumber}')) out.add(l);
    }
    return out.length == logs.length ? logs : List<SetLog>.unmodifiable(out);
  }

  /// Reemplaza las series con lo que dice Firestore.
  ///
  /// Se pisa entero en vez de mezclar porque el remoto YA es la fuente de
  /// verdad: `logSet`, `updateSetLog` y `deleteSetLog` escriben primero y
  /// recién después tocan el estado, así que lo local nunca tiene nada que el
  /// remoto no tenga. Mezclar solo agregaría la chance de resucitar una serie
  /// borrada.
  void _applyRemoteSetLogs(List<SetLog> remote) {
    final current = state.valueOrNull;
    if (current == null) return;
    // Sin cambios reales no se emite: cada emisión reconstruye la pantalla del
    // entreno, y Firestore repite el snapshot ante cualquier escritura de la
    // sesión.
    final clean = _dedupedLogs(remote);
    if (listEquals(current.setLogs, clean)) return;
    state = AsyncData(
      current.copyWith(setLogs: List<SetLog>.unmodifiable(clean)),
    );
  }

  // ── Path A — Sesión nueva ─────────────────────────────────────────────────

  Future<SessionState> _buildFresh(
    String routineId,
    int dayNumber,
    int weekNumber,
  ) async {
    // Misma cota que en `_buildResume`: empezar un entreno tampoco puede quedar
    // colgado sin salida.
    final routine = await ref
        .read(routineByIdProvider(routineId).future)
        .timeout(ref.read(firestoreReadTimeoutProvider));
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
    _nudgeWatch(WatchNudgeService.reasonWorkoutStarted);
    // DESPUÉS de que `repo.create` resolvió, nunca antes: el reloj lee Firestore
    // por REST y no tiene listeners. Si se abriera antes de que el documento con
    // `status: active` exista, no encontraría sesión que adoptar y se quedaría
    // en la pantalla equivocada, sin nada que lo corrija después.
    _launchWatch();

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

  /// Le avisa al reloj que el estado del entreno cambió.
  ///
  /// El reloj habla Firestore por REST y no tiene listeners, así que sin este
  /// aviso solo se entera cuando el atleta lo mira. La idea es la contraria:
  /// que si empezaste a entrenar en el celular la muñeca se ponga en modo
  /// entreno sola.
  ///
  /// Fire-and-forget y sin `await`: corre en el camino de empezar y terminar un
  /// entreno, que es lo más caliente de la app. Un reloj que no está a mano no
  /// puede demorar ni romper eso — se pone al día cuando el atleta lo mire.
  void _nudgeWatch(String reason) {
    try {
      unawaited(ref.read(watchNudgeServiceProvider).nudge(reason: reason));
    } catch (_) {
      // `ref.read` tira si el notifier ya se descartó (la ruta del player puede
      // salir mientras la escritura está en vuelo — ver la nota de #497 más
      // abajo). Un aviso perdido no justifica tumbar el cierre del entreno.
    }
  }

  /// Abre la app del reloj, si hay uno emparejado.
  ///
  /// Hermano de [_nudgeWatch] pero NO el mismo camino: `nudge` exige
  /// alcanzabilidad y se descarta cuando la app del reloj está cerrada, que es
  /// justo el caso que esto resuelve. Ver [WatchLauncherService].
  ///
  /// Fire-and-forget con la misma disciplina: abrir el reloj es un agregado y
  /// no puede demorar ni romper el arranque del entreno, que es lo más caliente
  /// de la app.
  void _launchWatch() {
    try {
      unawaited(ref.read(watchLauncherServiceProvider).launchWorkout());
    } catch (_) {
      // Idem [_nudgeWatch]: `ref.read` tira si el notifier ya se descartó.
    }
  }

  // ── Path B — Retomar sesión existente ────────────────────────────────────

  Future<SessionState> _buildResume(String sessionId) async {
    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      throw StateError('Resume solicitado sin usuario autenticado');
    }

    // Cada lectura va ACOTADA. Sin cota, un `get()` que no resuelve deja este
    // build en `AsyncLoading` para siempre: spinner eterno sobre un entreno ya
    // empezado, sin excepción ni salida. Ver `network_timeouts.dart`.
    final timeout = ref.read(firestoreReadTimeoutProvider);

    // Adaptación al contrato real de Etapa 1: getActive + listSetLogs.
    final session = await repo.getActive(uid).timeout(timeout);
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
    // Retomar también abre el reloj. Antes este camino no le avisaba NADA — ni
    // siquiera el nudge—, así que un entreno retomado desde el teléfono dejaba
    // la muñeca sin enterarse.
    _launchWatch();
    final recoveredLogs = await repo
        .listSetLogs(
          uid: uid,
          sessionId: session.id,
        )
        .timeout(timeout);

    final routine = await ref
        .read(routineByIdProvider(session.routineId).future)
        .timeout(timeout);
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
      // ⚠️ Y ahora puede cambiar por el STREAM, no solo por otra operación
      // local. La escritura de arriba dispara su propio snapshot de Firestore,
      // y si ese snapshot llega ANTES que este append, la serie entra dos veces
      // en el estado local. Se veía como un ejercicio "4/4" con solo 3 series
      // cargadas y el volumen inflado — Firestore estaba bien, el que contaba
      // de más era el teléfono.
      //
      // Se compara TAMBIÉN por identidad lógica y no solo por id: si esa serie
      // la escribió el reloj, su documento tiene otro id (determinístico) y por
      // id no matchearía.
      final alreadyInState = latest.setLogs.any(
        (l) =>
            l.id == persisted.id ||
            (l.exerciseId == persisted.exerciseId &&
                l.setNumber == persisted.setNumber),
      );
      final newLogs = _dedupedLogs(
        alreadyInState ? latest.setLogs : [...latest.setLogs, persisted],
      );
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
      // El reloj no tiene listeners: hasta que no se entere de esta serie,
      // marcarla en la muñeca escribiría un SEGUNDO documento de la misma
      // serie (los dos clientes generan ids distintos) y el atleta la vería
      // marcada dos veces.
      _nudgeWatch(WatchNudgeService.reasonSetLogged);
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

      // El setNumber nuevo se aplica como valor ABSOLUTO, no como un `-1`.
      //
      // Un delta se aplica DOS VECES. `updateSetLog` de arriba dispara su propio
      // snapshot de Firestore (compensación de latencia: llega antes de que el
      // `await` resuelva), el listener de `watchSetLogs` lo mete en el estado ya
      // renumerado, y este `map` volvía a restarle uno. Con 3 series y borrando
      // la 2, la sobreviviente pasaba de 3 → 2 por el stream → 1 por el map, y
      // el estado quedaba con DOS series en setNumber 1 y NINGUNA en 2.
      //
      // Se veía así: la fila 2 sin tildar aunque la serie existía en Firestore,
      // y la fila 3 ofrecida para cargar. Reproducido en el simulador el
      // 2026-08-12. Es la misma trampa del §4.5 del HANDOFF que ya había mordido
      // a `logSet` — "la propia escritura dispara su snapshot"— y por eso la
      // defensa correcta es la misma: que el camino sea idempotente, no que
      // adivine si el stream ya pasó.
      //
      // El valor absoluto es EXACTAMENTE el que se escribió a Firestore arriba,
      // así que aplicarlo sobre un estado ya renumerado es un no-op.
      final renumbered = {
        for (final s in survivorsAbove) s.id: s.setNumber - 1,
      };
      // Pasa por el invariante, igual que `logSet` y `_applyRemoteSetLogs`.
      // `removeSet` era el ÚNICO camino de mutación que lo salteaba, y por eso
      // las dos series con el mismo setNumber sobrevivían en el estado.
      final newLogs = _dedupedLogs(
        latest.setLogs
            .where((l) => target == null || l.id != target.id)
            .map((l) {
          final nuevo = renumbered[l.id];
          return nuevo == null ? l : l.copyWith(setNumber: nuevo);
        }).toList(growable: false),
      );
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

  /// Deja [exerciseIds] FUERA DE HOY para que la sesión entre en el tiempo que
  /// el atleta declaró tener (#645).
  ///
  /// NO escribe nada: el recorte vive en [SessionState.droppedExerciseIds], que
  /// es local a la sesión igual que `setCountOverride`. La rutina persistida no
  /// se toca, y un plan asignado por un PF sigue diciendo exactamente lo que
  /// decía — el atleta recorta su día, no el plan de su entrenador.
  ///
  /// Es aditivo (se acumula con lo ya recortado) e idempotente: recortar dos
  /// veces lo mismo no emite estado nuevo.
  ///
  /// **Un ejercicio con series ya cargadas NUNCA se saca**, aunque venga en
  /// [exerciseIds]. Sacarlo escondería trabajo real detrás de un ajuste de
  /// tiempo, que es justo lo que el diálogo de `removeSet` existe para evitar.
  /// `planSessionTimeFit` ya no lo propone; acá se lo sostiene como invariante
  /// para que ningún llamador futuro pueda romperlo.
  Future<void> dropExercisesForToday(Iterable<String> exerciseIds) async {
    final current = state.value;
    if (current == null || _finalized) return;

    final worked = current.setLogs.map((l) => l.exerciseId).toSet();
    final next = {
      ...current.droppedExerciseIds,
      ...exerciseIds.where((id) => !worked.contains(id)),
    };
    if (setEquals(next, current.droppedExerciseIds)) return;

    state = AsyncData(current.copyWith(
      droppedExerciseIds: next,
      currentExerciseIndex: _indexAfterDrop(current, next),
    ));
  }

  /// Devuelve a la sesión TODO lo que se había recortado (#645) — el "deshacer"
  /// del ajuste de tiempo. Vuelve a poner el día como lo dice el plan.
  Future<void> restoreDroppedExercises() async {
    final current = state.value;
    if (current == null || _finalized) return;
    if (current.droppedExerciseIds.isEmpty) return;

    state = AsyncData(current.copyWith(
      droppedExerciseIds: const <String>{},
      currentExerciseIndex: _indexAfterDrop(current, const <String>{}),
    ));
  }

  /// Recalcula el cursor del player para el set de recortados [dropped].
  ///
  /// Hace falta porque el cursor puede quedar apuntando a algo que ya no se
  /// hace: con los tres primeros ejercicios hechos y los dos últimos sacados,
  /// `currentExerciseIndex` seguía en el 4to — un ejercicio que salió de la
  /// sesión. Se resuelve con el mismo resolver que usan logSet/removeSet, así
  /// que un recortado (planned 0) nunca puede ser "el que sigue".
  int _indexAfterDrop(SessionState current, Set<String> dropped) =>
      _nextIncompleteIndex(
        current.day,
        current.setLogs,
        current.session.weekNumber,
        (s) => dropped.contains(s.exerciseId)
            ? 0
            : (current.setCountOverride[s.exerciseId] ??
                s.effectiveSetsForWeek(current.session.weekNumber).length),
      );

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
    _nudgeWatch(WatchNudgeService.reasonWorkoutFinished);
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
    _nudgeWatch(WatchNudgeService.reasonWorkoutFinished);
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
    // `length - 1` sobre una lista VACÍA da -1, y ese -1 termina en
    // `SessionState.currentExerciseIndex`, o sea en un índice negativo sobre la
    // lista de ejercicios.
    //
    // No es hipotético: los dos paths de build filtran los slots por
    // `isPresentInWeek(weekNumber)` (REQ-WPRES-021), así que un día cuyos slots
    // estén TODOS ausentes en esa semana —periodización legítima— deja la lista
    // en cero. Devolver 0 mantiene el índice dentro del dominio; la pantalla ya
    // sabe dibujar un día sin ejercicios, lo que no sabe es indexar en -1.
    return day.slots.isEmpty ? 0 : day.slots.length - 1;
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
