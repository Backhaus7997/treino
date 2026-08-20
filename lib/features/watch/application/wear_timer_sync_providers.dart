import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/treino_link.dart';
import '../data/wear_workout_service.dart';
import '../domain/wear_timer_sync.dart';
import 'watch_bridge_provider.dart';
import 'wear_rest_providers.dart';

/// Arranca y cancela el ejercicio por tiempo en LOS DOS aparatos.
///
/// ## Por qué está encapsulado y no suelto en la pantalla
///
/// Porque arrancar el temporizador son dos cosas —el deadline local y el aviso
/// al otro lado— y separarlas es garantizar que alguna vez se haga una sin la
/// otra. Un temporizador que corre en el reloj y no en el teléfono es peor que
/// ninguno: el atleta ve dos números distintos y no sabe a cuál creerle.
class WearTimerSync {
  const WearTimerSync({
    required WearWorkoutService service,
    required TreinoLink link,
  })  : _service = service,
        _link = link;

  final WearWorkoutService _service;
  final TreinoLink _link;

  /// Arranca acá y avisa al teléfono.
  ///
  /// El aviso va con el instante de arranque además de la duración: el mensaje
  /// tarda en cruzar y sin eso los dos aparatos mostrarían números corridos.
  Future<void> arrancar(int seconds) async {
    if (seconds <= 0) return cancelar();
    await _service.startExerciseTimer(seconds);
    unawaited(_link.send(TreinoLink.pathTimerStarted, {
      'seconds': seconds,
      'startedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  /// Cancela acá y avisa al teléfono.
  Future<void> cancelar() async {
    await _service.cancelExerciseTimer();
    unawaited(_link.send(TreinoLink.pathTimerCancelled));
  }

  /// Aplica lo que llegó del otro lado, SIN reenviar.
  ///
  /// Reenviar sería un eco: el otro aparato volvería a avisar y los dos se
  /// quedarían rebotando el mismo temporizador.
  Future<void> aplicarRemoto(TreinoLinkMessage msg) async {
    if (msg.path == TreinoLink.pathTimerCancelled) {
      debugPrint('[wear-timer] cancelado desde el teléfono');
      await _service.cancelExerciseTimer();
      return;
    }
    if (msg.path != TreinoLink.pathTimerStarted) return;

    final seconds = (msg.data['seconds'] as num?)?.toInt() ?? 0;
    final startedAt = (msg.data['startedAtEpochMs'] as num?)?.toInt();
    if (seconds <= 0 || startedAt == null) {
      debugPrint('[wear-timer] payload inservible: ${msg.data}');
      return;
    }

    final restante = wearRemainingSeconds(
      seconds: seconds,
      startedAtEpochMs: startedAt,
      nowEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (restante <= 0) {
      debugPrint('[wear-timer] llegó vencido, no se arranca');
      return;
    }

    debugPrint('[wear-timer] arrancado desde el teléfono ($restante s)');
    await _service.startExerciseTimer(restante);
  }
}

final wearTimerSyncProvider = Provider<WearTimerSync>(
  (ref) => WearTimerSync(
    service: ref.watch(wearWorkoutServiceProvider),
    link: ref.watch(treinoLinkProvider),
  ),
);

/// Escucha lo que manda el teléfono sobre el temporizador.
///
/// Se lee de forma EAGER en `main_wear.dart`: sin ese `ref.read` no hay nadie
/// escuchando y la sincronización es código muerto — el mismo patrón, y el
/// mismo riesgo, que el lifecycle de credencial del teléfono.
final wearTimerInboxProvider = Provider<void>((ref) {
  final sync = ref.watch(wearTimerSyncProvider);
  final sub = ref.watch(treinoLinkProvider).messages.listen(
        (msg) => unawaited(sync.aplicarRemoto(msg)),
        onError: (Object e) =>
            debugPrint('[wear-timer] el canal se quejó — $e'),
      );
  ref.onDispose(sub.cancel);
});
