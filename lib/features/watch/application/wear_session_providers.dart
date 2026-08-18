import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider, sessionRepositoryProvider;
import '../../workout/domain/session.dart';
import '../../workout/domain/set_log.dart';
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

    // Adoptar es asíncrono, así que el estado inicial es Idle y la adopción lo
    // corrige. Arrancar en Opening haría parpadear un spinner en el caso
    // normal, que es no tener ningún entreno abierto.
    unawaited(_adoptarSiHay());

    return const WearSessionIdle();
  }

  String? get _uid => ref.read(currentUidProvider);

  /// Si el atleta ya tiene un entreno abierto —lo empezó en el teléfono, o el
  /// reloj se reinició en medio— el reloj se suma a ÉSE.
  Future<void> _adoptarSiHay() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;

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

  void _set(WearSessionState nuevo) {
    if (_muerto) return;
    state = nuevo;
  }
}
