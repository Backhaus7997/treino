import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider, sessionRepositoryProvider;
import '../../workout/application/session_duration.dart'
    show maxWorkoutDuration;
import '../../workout/domain/session.dart';
import '../../workout/domain/set_log.dart';
import '../../workout/domain/set_log_identity.dart';
import '../domain/wear_workout_plan.dart';
import '../domain/wear_workout_session.dart';
import '../presentation/wear/wear_view_models.dart';

/// En qué anda el entreno del reloj.
///
/// Espeja `session: WorkoutSession?` de watchOS, que es la forma que `WearRoot`
/// ya tiene: si hay entreno, gana sobre todo lo demás.
sealed class WearSessionState {
  const WearSessionState();
}

/// No hay entreno. El reloj muestra HOY.
class WearSessionIdle extends WearSessionState {
  const WearSessionIdle();
}

/// Abriendo: se está resolviendo si hay uno activo, o creando uno.
class WearSessionOpening extends WearSessionState {
  const WearSessionOpening();
}

/// Hay entreno en curso.
class WearSessionRunning extends WearSessionState {
  const WearSessionRunning(this.session);

  final WearWorkoutSession session;
}

/// No se pudo abrir. Es distinto de [WearSessionIdle]: acá hubo un intento.
class WearSessionFailed extends WearSessionState {
  const WearSessionFailed(this.motivo);

  final String motivo;
}

final wearSessionProvider =
    NotifierProvider<WearSessionNotifier, WearSessionState>(
  WearSessionNotifier.new,
);

/// Abre, adopta y mantiene el entreno del reloj.
///
/// ## La regla que no se negocia: ADOPTAR antes que CREAR
///
/// `start` llama SIEMPRE a `getActive` antes de crear. No es prolijidad: es que
/// `SessionRepository.create` no tiene ningún guard, así que crear a ciegas
/// mientras el teléfono ya tiene una sesión abierta deja DOS activas.
///
/// Y dos activas no es un empate benigno. `getActive` barre: cierra CUALQUIER
/// activa que no sea la más nueva por `startedAt` —tenga ocho horas o cinco
/// minutos— marcándola `wasFullyCompleted: false`. La que sobrevive es la del
/// reloj, porque es la más nueva. O sea: el entreno que el atleta está haciendo
/// EN EL TELÉFONO, con series cargadas, muere y lo expulsan del player.
///
/// ## El plan sale de la POSICIÓN DE LA SESIÓN
///
/// Nunca de «el día que tocaría hoy». Ver `wearWorkoutPlanFrom` — es el bug más
/// caro del lado Apple.
class WearSessionNotifier extends Notifier<WearSessionState> {
  StreamSubscription<List<SetLog>>? _series;
  var _muerto = false;

  @override
  WearSessionState build() {
    ref.onDispose(() {
      _muerto = true;
      _series?.cancel();
    });

    // ⚠️ El uid llega ASÍNCRONO, y esto costó una corrida en el reloj.
    //
    // `currentUidProvider` sale de `authStateChangesProvider`, que es un stream:
    // cuando este notifier se construye, Firebase Auth todavía no restauró la
    // sesión y el uid es null. Leerlo UNA sola vez acá —que es lo que hacía—
    // daba null en todo arranque en frío, la adopción volvía en silencio, y el
    // reloj mostraba HOY teniendo un entreno abierto. Se recuperaba sólo si el
    // atleta tocaba Empezar, porque ese camino corre mucho después.
    //
    // Se ESCUCHA. `fireImmediately` cubre el arranque en caliente, donde el uid
    // ya está.
    ref.listen<String?>(
      currentUidProvider,
      (previo, nuevo) {
        if (nuevo == null || nuevo.isEmpty) return;
        if (previo == nuevo) return;
        // En microtask porque `fireImmediately` dispara este listener DENTRO
        // del build, y `_adoptarSiHay` mira `state` — que todavía no existe.
        // Riverpod tira "Tried to read the state of an uninitialized provider".
        unawaited(Future<void>.microtask(() => _adoptarSiHay(nuevo)));
      },
      fireImmediately: true,
    );

    // Adoptar es asíncrono, así que el estado inicial es Idle y la adopción lo
    // corrige. Arrancar en Opening haría parpadear un spinner en el caso
    // normal, que es no tener ningún entreno abierto.
    return const WearSessionIdle();
  }

  String? get _uid => ref.read(currentUidProvider);

  /// Si el atleta ya tiene un entreno abierto —lo empezó en el teléfono, o el
  /// reloj se reinició en medio— el reloj se suma a ÉSE.
  Future<void> _adoptarSiHay(String uid) async {
    // No pisar un entreno que ya se abrió por otro camino.
    if (state is! WearSessionIdle) return;

    try {
      final abierta = await ref.read(sessionRepositoryProvider).getActive(uid);
      if (abierta == null) return;
      await _abrir(uid, abierta);
    } catch (e) {
      debugPrint('[wear-session] no se pudo adoptar el entreno abierto — $e');
      // Se queda en Idle a propósito: no poder adoptar no es no poder entrenar.
      // El atleta todavía puede tocar Empezar, y ese camino vuelve a intentar.
    }
  }

  /// Empieza el entreno de hoy, o se suma al que ya esté abierto.
  Future<void> start(WearTodaysWorkout hoy) async {
    if (state is WearSessionRunning || state is WearSessionOpening) return;

    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      _set(const WearSessionFailed('sin sesión'));
      return;
    }

    _set(const WearSessionOpening());
    final repo = ref.read(sessionRepositoryProvider);

    try {
      // ADOPTAR PRIMERO. Ver el encabezado de la clase.
      final abierta = await repo.getActive(uid);
      if (abierta != null) {
        debugPrint('[wear-session] adoptando el entreno abierto '
            '${abierta.id} (día ${abierta.dayNumber})');
        await _abrir(uid, abierta);
        return;
      }

      final creada = await repo.create(
        uid: uid,
        routineId: hoy.routineId,
        routineName: hoy.routineName,
        startedAt: DateTime.now(),
        dayNumber: hoy.dayNumber,
        weekNumber: hoy.weekNumber,
      );
      debugPrint('[wear-session] entreno creado ${creada.id} '
          '(día ${creada.dayNumber}, semana ${creada.weekNumber})');
      await _abrir(uid, creada);
    } catch (e) {
      debugPrint('[wear-session] no se pudo empezar — $e');
      _set(const WearSessionFailed('no se pudo empezar el entreno'));
    }
  }

  /// Resuelve el plan de [sesion] y engancha el historial en vivo.
  Future<void> _abrir(String uid, Session sesion) async {
    final rutina = await ref.read(routineByIdProvider(sesion.routineId).future);
    if (rutina == null) {
      _set(const WearSessionFailed('no se encontró la rutina'));
      return;
    }

    final plan = wearWorkoutPlanFrom(
      routine: rutina,
      dayNumber: sesion.dayNumber,
      weekNumber: sesion.weekNumber,
    );
    if (plan == null) {
      _set(const WearSessionFailed('la rutina no tiene ese día'));
      return;
    }

    _set(
      WearSessionRunning(
        WearWorkoutSession(
          sessionId: sesion.id,
          startedAt: sesion.startedAt,
          plan: plan,
          logged: const [],
        ),
      ),
    );

    _escucharSeries(uid, sesion.id);
  }

  /// El historial en vivo. **Es la única fuente de `logged`.**
  ///
  /// Acá se cobra la diferencia con watchOS: allá no hay listeners y por eso
  /// existe toda la máquina de avisos por WatchConnectivity. Wear tiene el SDK,
  /// así que una serie marcada en el teléfono llega sola —mediana medida de 206
  /// ms— y el cursor se recalcula con ella.
  ///
  /// Pisa la lista ENTERA en cada snapshot. Nunca hace merge: si el teléfono
  /// borró una serie, tiene que desaparecer, y eso con un merge es imposible.
  void _escucharSeries(String uid, String sessionId) {
    _series?.cancel();
    _series = ref
        .read(sessionRepositoryProvider)
        .watchSetLogs(uid: uid, sessionId: sessionId)
        .listen(
      (series) {
        final actual = state;
        if (actual is! WearSessionRunning) return;
        if (actual.session.sessionId != sessionId) return;

        _set(
          WearSessionRunning(
            actual.session.copyWith(
              logged: [
                for (final s in series)
                  WearLoggedSet(
                    docId: s.id,
                    exerciseId: s.exerciseId,
                    setNumber: s.setNumber,
                    reps: s.reps,
                    weightKg: s.weightKg,
                  ),
              ],
            ),
          ),
        );
      },
      onError: (Object e) {
        debugPrint('[wear-session] el historial dejó de llegar — $e');
        // NO se cambia de estado: el entreno sigue, con lo último que se supo.
        // Sacarlo de Running por un corte de red le borraria al atleta la
        // pantalla en medio de una serie.
      },
    );
  }

  /// Marca una serie del entreno.
  ///
  /// [exerciseId] lo pasa la FILA, no se resuelve del cursor. Entre que la fila
  /// se dibuja y el atleta la toca puede llegar un snapshot del teléfono que
  /// mueva el cursor, y la serie terminaría escrita en OTRO ejercicio.
  ///
  /// Es idempotente por identidad lógica: dos toques sobre la misma serie
  /// escriben una sola vez. El guard es POR SERIE y no global —a diferencia del
  /// `_isLoggingSet` del teléfono— porque en la muñeca marcar dos series
  /// seguidas rápido es normal, y un candado global se comería la segunda.
  Future<void> logSet({
    required String exerciseId,
    required int setNumber,
  }) async {
    final actual = state;
    if (actual is! WearSessionRunning) return;
    final sesion = actual.session;

    final identidad = '${exerciseId}__$setNumber';
    // Ya marcada, o con una escritura en vuelo. `identities` incluye `pending`.
    if (sesion.identities.contains(identidad)) return;

    final ejercicio = _ejercicioDe(sesion, exerciseId);
    if (ejercicio == null) return;
    if (setNumber < 1 || setNumber > ejercicio.sets.length) return;
    final spec = ejercicio.sets[setNumber - 1];

    final uid = _uid;
    if (uid == null || uid.isEmpty) return;

    // El círculo se llena en el toque: la escritura tiene un viaje de red por
    // delante y esperar a que vuelva se siente roto en la muñeca.
    _set(
      WearSessionRunning(
        sesion.copyWith(pending: {...sesion.pending, identidad}),
      ),
    );

    try {
      await ref.read(sessionRepositoryProvider).addSetLogFromWatch(
        uid: uid,
        sessionId: sesion.sessionId,
        setLog: SetLog(
          id: '',
          exerciseId: exerciseId,
          exerciseName: ejercicio.exerciseName,
          setNumber: setNumber,
          // Con un rango se registra el MÁXIMO: es el objetivo del plan.
          // Misma regla que watchOS; el atleta corrige desde el teléfono.
          reps: spec.reps ?? spec.repsMax ?? spec.repsMin ?? 0,
          weightKg: spec.weightKg ?? 0,
          completedAt: DateTime.now(),
        ),
        // El historial que el listener ya trajo. Sin esto, cada serie
        // releería la colección entera. Ver `addSetLogFromWatch`.
        knownRemote: [
          for (final l in sesion.logged)
            RemoteSetLogRef(
              docId: l.docId,
              exerciseId: l.exerciseId,
              setNumber: l.setNumber,
            ),
        ],
      );
    } catch (e) {
      debugPrint('[wear-session] no se pudo marcar $identidad — $e');
    } finally {
      // Sale de pending pase lo que pase. Si la escritura falló, el círculo se
      // vacía — que es honesto: la serie NO quedó guardada. Si salió bien, el
      // listener ya la trajo y `logged` la sostiene.
      _sacarDePending(identidad);
    }
  }

  /// Cierra el entreno como COMPLETADO.
  ///
  /// Sólo se ofrece con todas las series de todos los ejercicios hechas
  /// (`isFullyCompleted`), que es pedido del dueño: tenerlo a la vista antes
  /// invita a cerrar el entreno de más.
  Future<void> finish() => _cerrar(completo: true);

  /// Abandona el entreno sin completarlo.
  ///
  /// Existe porque sin esto una lesión deja la sesión abierta para siempre y el
  /// atleta sin salida si no tiene el teléfono a mano — la deuda §8.3 del
  /// companion de Apple, que allá ya se cerró.
  Future<void> abandon() => _cerrar(completo: false);

  Future<void> _cerrar({required bool completo}) async {
    final actual = state;
    if (actual is! WearSessionRunning) return;
    final sesion = actual.session;

    final uid = _uid;
    if (uid == null || uid.isEmpty) return;

    final ahora = DateTime.now();
    try {
      await ref.read(sessionRepositoryProvider).finish(
            uid: uid,
            sessionId: sesion.sessionId,
            finishedAt: ahora,
            totalVolumeKg: sesion.totalVolumeKg,
            durationMin: _duracionMin(sesion.startedAt, ahora),
            wasFullyCompleted: completo,
          );
    } catch (e) {
      debugPrint('[wear-session] no se pudo cerrar el entreno — $e');
      // Se queda en Running: si la escritura falló, la sesión sigue abierta en
      // Firestore y sacar al atleta de la pantalla le mentiría.
      return;
    }

    _series?.cancel();
    _series = null;
    _set(const WearSessionIdle());
  }

  /// Minutos del entreno, redondeados hacia arriba y con el mismo tope que usa
  /// el teléfono.
  ///
  /// No hay timer: un tick por segundo en un ARM de 32 bits es un rebuild por
  /// segundo durante todo el entreno. Como el número sólo hace falta al cerrar,
  /// se calcula ahí.
  int _duracionMin(DateTime desde, DateTime hasta) {
    final segundos = hasta
        .difference(desde)
        .inSeconds
        .clamp(0, maxWorkoutDuration.inSeconds);
    return (segundos + 59) ~/ 60;
  }

  WearPlannedExercise? _ejercicioDe(WearWorkoutSession s, String exerciseId) {
    for (final e in s.plan.exercises) {
      if (e.exerciseId == exerciseId) return e;
    }
    return null;
  }

  void _sacarDePending(String identidad) {
    final actual = state;
    if (actual is! WearSessionRunning) return;
    if (!actual.session.pending.contains(identidad)) return;
    _set(
      WearSessionRunning(
        actual.session.copyWith(
          pending: {...actual.session.pending}..remove(identidad),
        ),
      ),
    );
  }

  void _set(WearSessionState nuevo) {
    if (_muerto) return;
    state = nuevo;
  }
}
