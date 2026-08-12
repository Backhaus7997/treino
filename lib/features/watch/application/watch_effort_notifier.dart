import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/watch_bridge.dart';
import '../domain/watch_effort.dart';

/// El último esfuerzo que publicó el reloj.
///
/// Change `watch-workout-session`, fase F4.
///
/// **No persiste nada.** Vive en memoria mientras dura el entreno y muere con
/// la app. Es lo que mantiene intacta D1: el ciclo no toca Firestore.
///
/// Es un `ValueNotifier` y no un provider con estado propio porque el dato
/// cambia cada pocos segundos y solo lo mira una fila de la pantalla del
/// player. Un rebuild de todo el player cada 5 segundos por un dato secundario
/// sería exactamente lo que `docs/performance.md` pide evitar.
class WatchEffortNotifier extends ValueNotifier<WatchEffort?> {
  WatchEffortNotifier({required Stream<Map<String, dynamic>> contextStream})
      : super(null) {
    _sub = contextStream.listen(
      _onContext,
      // Un error del canal de plataforma NO puede matar la suscripción: si se
      // cae, el atleta pierde el dato para el resto del entreno y no hay
      // ningún síntoma visible de por qué.
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  late final StreamSubscription<Map<String, dynamic>> _sub;

  void _onContext(Map<String, dynamic> context) {
    final effort = WatchEffort.tryParse(context);
    // Un contexto ajeno —o roto— no pisa el último esfuerzo bueno con un null.
    // El canal lo comparte con la credencial del reloj.
    if (effort == null) return;
    value = effort;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// El notifier, vivo mientras haya alguien mirando.
final watchEffortNotifierProvider = Provider<WatchEffortNotifier>((ref) {
  final bridge = WatchBridge();
  final notifier = WatchEffortNotifier(contextStream: bridge.contextStream);
  ref.onDispose(notifier.dispose);
  return notifier;
});
