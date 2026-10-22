import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_clock.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/data/session_repository.dart';
import '../../workout/domain/rest_rules.dart';
import '../../workout/domain/rest_state.dart';
import '../data/wear_workout_service.dart';
import 'wear_rest_providers.dart';
import 'wear_session_providers.dart';

/// El descanso de este reloj, compartido con el teléfono por la sesión (#1616).
///
/// Mismo camino que el cronómetro del ejercicio por tiempo
/// (`WearTimerSync`, en `wear_timer_sync_providers.dart`), y por las mismas dos
/// razones escritas allá: la Data Layer exige el reloj emparejado con ESE
/// teléfono, y un mensaje se pierde si el otro no escucha. El descanso es
/// ESTADO, y el estado vive en la sesión.
///
/// El descanso nativo sigue siendo el que manda en la muñeca —deadline en
/// `elapsedRealtime`, alarma exacta, vibración aunque Dart duerma— y arranca
/// SIEMPRE, con o sin red. La sesión es el espejo: la escritura no se espera.
class WearRestSync {
  const WearRestSync({
    required WearWorkoutService service,
    required SessionRepository repo,
    required String? uid,
    required String? sessionId,
  })  : _service = service,
        _repo = repo,
        _uid = uid,
        _sessionId = sessionId;

  final WearWorkoutService _service;
  final SessionRepository _repo;
  final String? _uid;
  final String? _sessionId;

  bool get _puedeSincronizar =>
      (_uid?.isNotEmpty ?? false) && (_sessionId?.isNotEmpty ?? false);

  /// Marcó la serie [setNumber] de [exerciseId]: arranca el descanso acá y lo
  /// anota en la sesión, con este reloj como dueño.
  ///
  /// Con [seconds] en cero o menos es SALTAR, no "nada": una serie de un
  /// ejercicio sin descanso significa que el atleta ya volvió a entrenar, y el
  /// descanso que venía corriendo tiene que cortarse también en el teléfono.
  Future<void> arrancar({
    required String exerciseId,
    required int setNumber,
    required int seconds,
  }) async {
    if (seconds <= 0) return saltar();
    // El instante se toma ANTES de arrancar el nativo: lo que se anota y lo
    // que cuenta la muñeca quedan separados por lo que tarda una llamada al
    // MethodChannel, muy por debajo de [RestRules.mirrorTolerance].
    final descanso = RestState.startedAt(
      exerciseId: exerciseId,
      setNumber: setNumber,
      totalSeconds: seconds,
      start: AppClock.now().toUtc(),
      owner: RestOwner.reloj,
    );
    await _service.startRest(seconds);
    if (!_puedeSincronizar) return;
    unawaited(
      _repo
          .writeRest(uid: _uid!, sessionId: _sessionId!, rest: descanso)
          .catchError(
            (Object e) => debugPrint('[wear-descanso] no se pudo anotar — $e'),
          ),
    );
  }

  /// SALTAR: lo corta acá y en la sesión, o sea también en el teléfono.
  Future<void> saltar() async {
    await _service.cancelRest();
    if (!_puedeSincronizar) return;
    unawaited(
      _repo.clearRest(uid: _uid!, sessionId: _sessionId!).catchError(
            (Object e) => debugPrint('[wear-descanso] no se pudo borrar — $e'),
          ),
    );
  }
}

final wearRestSyncProvider = Provider<WearRestSync>((ref) {
  final sesion = ref.watch(wearSessionProvider);
  return WearRestSync(
    service: ref.watch(wearWorkoutServiceProvider),
    repo: ref.watch(sessionRepositoryProvider),
    uid: ref.watch(currentUidProvider),
    sessionId: sesion is WearSessionRunning ? sesion.session.sessionId : null,
  );
});

/// Lo que la sesión dice del descanso, visto desde el reloj.
///
/// Emite el valor inicial al suscribirse: el reloj que se abre a mitad de un
/// descanso que arrancó el teléfono lo encuentra corriendo.
final wearSessionRestProvider = StreamProvider<RestState?>((ref) {
  final sesion = ref.watch(wearSessionProvider);
  if (sesion is! WearSessionRunning) return const Stream.empty();
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return const Stream.empty();

  return ref.watch(sessionRepositoryProvider).watchRest(
        uid: uid,
        sessionId: sesion.session.sessionId,
      );
});

/// Refleja en el descanso nativo lo que dice la sesión.
///
/// Se lee de forma EAGER en `main_wear.dart`, como `wearTimerInboxProvider`:
/// sin eso nadie escucha y el descanso del teléfono nunca llega a la muñeca.
///
/// La decisión es [RestRules.decide], la misma que toman el teléfono y el
/// reloj de Apple: adoptar lo que dice la sesión, cortar el propio si allá ya
/// no hay, o no tocar nada si ya coinciden. Espejar NO escribe: si escribiera,
/// cada aparato le contestaría al otro y el descanso rebotaría para siempre.
///
/// ## Por qué se encolan
///
/// Cada espejado son dos idas al nativo —leer y después arrancar o cortar—. Si
/// llegan dos cambios seguidos (el teléfono marcó y enseguida sumó +15 s), sin
/// cola el segundo puede leer el estado ANTES de que el primero arranque, y el
/// orden de las dos escrituras al nativo queda librado al azar. En fila, el
/// último cambio de la sesión es el último que llega al nativo.
final wearRestInboxProvider = Provider<void>((ref) {
  final service = ref.watch(wearWorkoutServiceProvider);
  var cola = Future<void>.value();

  ref.listen<AsyncValue<RestState?>>(
    wearSessionRestProvider,
    (_, next) {
      // Sólo DATOS: un error de red no dice que el descanso se haya saltado.
      if (next is! AsyncData<RestState?>) return;
      final remoto = next.value;
      cola = cola
          .then((_) => espejarDescansoEnElReloj(service, remoto))
          .catchError(
            (Object e) => debugPrint('[wear-descanso] no se pudo espejar — $e'),
          );
    },
    // Un descanso ya en curso al suscribirse no se espejaría hasta el próximo
    // cambio del documento, que puede no llegar nunca: mientras corre, el
    // instante de fin no cambia.
    fireImmediately: true,
  );
});

/// Una vuelta del espejo. Pública sólo para poder medirla.
@visibleForTesting
Future<void> espejarDescansoEnElReloj(
  WearWorkoutService service,
  RestState? remoto,
) async {
  // `AppClock` y no `DateTime.now()`: lo que se le pasa al nativo es una resta
  // contra el reloj de pared, y con la hora sin inyectar el test daría un
  // número u otro según lo que tardara la máquina. Mismo motivo que en el
  // espejo del cronómetro.
  final ahora = AppClock.now().toUtc();
  final local = await service.restState();
  // El descanso nativo está en `elapsedRealtime`, que no significa nada en otro
  // aparato. Para compararlo con la sesión se lo lleva a tiempo de pared por
  // lo que FALTA, que sí es comparable.
  final localHasta = (local == null || local.finished)
      ? null
      : ahora.add(Duration(milliseconds: local.remainingMs));

  switch (RestRules.decide(
    local: localHasta,
    remote: remoto?.endsAt,
    now: ahora,
  )) {
    case RestMirrorAction.adopt:
      debugPrint('[wear-descanso] espejo de la sesión: $remoto');
      await service.startRestFor(remoto!.endsAt.difference(ahora));
    case RestMirrorAction.stop:
      debugPrint('[wear-descanso] la sesión ya no tiene descanso: se corta');
      await service.cancelRest();
    case RestMirrorAction.keep:
      break;
  }
}
