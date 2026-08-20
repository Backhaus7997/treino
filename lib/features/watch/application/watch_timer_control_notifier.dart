import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'watch_credential_providers.dart' show watchBridgeProvider;

/// Pedidos del RELOJ para cortar el cronómetro que corre en el TELÉFONO.
///
/// ── Por qué existe una tercera cosa ───────────────────────────────────────
///
/// Ya hay dos canales entre los dispositivos y ninguno servía para esto:
///
/// - `WatchEffortNotifier` trae ESTADO del reloj ("esto es lo que estoy
///   midiendo"). Se colapsa y puede llegar tarde, que para un pulso está bien.
/// - `WatchTimerService` manda órdenes del teléfono AL reloj.
///
/// Esto es una orden del reloj AL teléfono, y es la primera: hasta ahora el
/// reloj nunca le había mandado un mensaje al celular, y del lado Dart
/// `WatchBridge.messageStream` existía sin que lo escuchara nadie.
///
/// Va por mensaje y no por contexto porque una orden que se colapsa o llega
/// diez minutos tarde no cancela nada: marca otra cosa.
///
/// ── Lleva IDENTIDAD y número de secuencia ─────────────────────────────────
///
/// La identidad —ejercicio + número de serie— porque sin ella el teléfono no
/// sabe cuál de sus cuentas cortar y las corta todas.
///
/// La secuencia porque dos cancelaciones seguidas sobre la misma serie tienen
/// que poder distinguirse: con solo la identidad, la segunda no notificaría a
/// nadie. Mismo motivo por el que `externalRefresh` del lado Swift es un
/// contador.
/// Un pedido concreto: cortá la cuenta de ESTA serie.
class WatchTimerCancelRequest {
  const WatchTimerCancelRequest({
    required this.secuencia,
    required this.exerciseId,
    required this.setNumber,
  });

  /// Sube con cada pedido. Dos cancelaciones seguidas sobre la misma serie
  /// tienen que poder distinguirse; con solo la identidad, la segunda no
  /// notificaría a nadie y el cronómetro se quedaría corriendo.
  final int secuencia;

  final String exerciseId;
  final int setNumber;

  /// Si este pedido es para esa fila.
  ///
  /// La identidad NO es opcional. Sin ella el teléfono no sabe cuál cuenta
  /// cortar y las corta todas: con navegación libre el atleta puede tener dos
  /// filas por tiempo activas, y cancelar la de la muñeca le mataría también la
  /// plancha que está aguantando.
  bool aplicaA({required String exerciseId, required int setNumber}) =>
      this.exerciseId == exerciseId && this.setNumber == setNumber;
}

class WatchTimerControlNotifier
    extends ValueNotifier<WatchTimerCancelRequest?> {
  WatchTimerControlNotifier({
    required Stream<Map<String, dynamic>> messageStream,
  }) : super(null) {
    _sub = messageStream.listen(
      _onMessage,
      // Un error del canal de plataforma NO puede matar la suscripción: si se
      // cae, el atleta pierde la cancelación para el resto del entreno y no hay
      // ningún síntoma visible de por qué.
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  /// Discrimina esta orden de cualquier otra que viaje por el mismo canal.
  ///
  /// Es distinto del `kind` de ida (`watchTimer`) a propósito: los canales son
  /// direccionales y no se cruzan, así que reusar el mismo sería seguro, pero
  /// un log no dejaría ver de qué lado salió el mensaje. Lo escribe
  /// `PhoneTimerMirror.cancelRequestMessage` en Swift.
  static const String kind = 'watchTimerControl';
  static const String actionCancel = 'cancel';

  late final StreamSubscription<Map<String, dynamic>> _sub;

  int _secuencia = 0;

  void _onMessage(Map<String, dynamic> message) {
    if (message['kind'] != kind) return;
    if (message['action'] != actionCancel) return;

    // Un pedido sin identidad se IGNORA. Los dos lados viajan en el mismo IPA,
    // así que un reloj que no la mande es un reloj desactualizado — y cancelar
    // la cuenta equivocada es peor que no cancelar ninguna: en el primer caso
    // el atleta pierde una serie que estaba haciendo, en el segundo agarra el
    // teléfono.
    final exerciseId = message['exerciseId'];
    final setNumber = message['setNumber'];
    if (exerciseId is! String || exerciseId.isEmpty) return;
    if (setNumber is! int || setNumber <= 0) return;

    _secuencia += 1;
    value = WatchTimerCancelRequest(
      secuencia: _secuencia,
      exerciseId: exerciseId,
      setNumber: setNumber,
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// El notifier, vivo mientras viva la app.
///
/// Se lee de forma eager en `app.dart`, igual que el de esfuerzo: si naciera al
/// abrir el player, una cancelación mandada desde la muñeca con el teléfono en
/// otra pantalla no llegaría nunca. Ese fue exactamente el bug de `eaf700a6`.
final watchTimerControlNotifierProvider =
    Provider<WatchTimerControlNotifier>((ref) {
  final bridge = ref.watch(watchBridgeProvider);
  final notifier = WatchTimerControlNotifier(
    messageStream: bridge.messageStream,
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});
