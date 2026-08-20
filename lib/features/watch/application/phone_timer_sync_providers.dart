import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/treino_link.dart';
import '../domain/wear_timer_sync.dart';
import 'watch_bridge_provider.dart';

/// Lo que el RELOJ le pide al teléfono sobre el ejercicio por tiempo.
sealed class WatchTimerCommand {
  const WatchTimerCommand();
}

/// Arrancó allá: acá hay que arrancar con [seconds] restantes.
class WatchTimerStart extends WatchTimerCommand {
  const WatchTimerStart(this.seconds);
  final int seconds;
}

/// Se canceló allá.
class WatchTimerCancel extends WatchTimerCommand {
  const WatchTimerCancel();
}

/// Avisa al reloj lo que pasa con el temporizador de este lado.
///
/// El instante de arranque viaja además de la duración: el mensaje tarda en
/// cruzar y sin eso los dos aparatos mostrarían números corridos. Ver
/// [wearRemainingSeconds].
class PhoneTimerSync {
  const PhoneTimerSync(this._link);

  final TreinoLink _link;

  void arranco(int seconds) {
    if (seconds <= 0) return;
    unawaited(_link.send(TreinoLink.pathTimerStarted, {
      'seconds': seconds,
      'startedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  void cancelo() => unawaited(_link.send(TreinoLink.pathTimerCancelled));
}

final phoneTimerSyncProvider = Provider<PhoneTimerSync>(
  (ref) => PhoneTimerSync(ref.watch(treinoLinkProvider)),
);

/// Los pedidos que llegan DESDE el reloj, ya traducidos.
///
/// El descuento de lo transcurrido se hace acá y no en el widget para que la
/// regla —incluidos los guards de reloj desfasado— viva en un solo lugar y se
/// pueda testear sin levantar UI.
final phoneTimerCommandsProvider = StreamProvider<WatchTimerCommand>((ref) {
  return ref.watch(treinoLinkProvider).messages.expand((msg) {
    if (msg.path == TreinoLink.pathTimerCancelled) {
      return const [WatchTimerCancel()];
    }
    if (msg.path != TreinoLink.pathTimerStarted) {
      return const <WatchTimerCommand>[];
    }

    final seconds = (msg.data['seconds'] as num?)?.toInt() ?? 0;
    final startedAt = (msg.data['startedAtEpochMs'] as num?)?.toInt();
    if (seconds <= 0 || startedAt == null) {
      debugPrint('[phone-timer] payload inservible: ${msg.data}');
      return const <WatchTimerCommand>[];
    }

    final restante = wearRemainingSeconds(
      seconds: seconds,
      startedAtEpochMs: startedAt,
      nowEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    // Llegó vencido: arrancar un temporizador de cero sería peor que ignorarlo.
    if (restante <= 0) return const <WatchTimerCommand>[];

    return [WatchTimerStart(restante)];
  });
});
