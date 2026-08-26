import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Un aviso que cruza entre el teléfono y el reloj.
class TreinoLinkMessage {
  const TreinoLinkMessage({required this.path, required this.data});

  /// Siempre empieza con `/treino/`.
  final String path;

  final Map<String, dynamic> data;

  @override
  String toString() => 'TreinoLinkMessage($path, $data)';
}

/// Canal propio entre el teléfono y el reloj.
///
/// ## Por qué no se usa `watch_connectivity` para esto
///
/// Ese plugin manda los mensajes con un path SIN barra inicial
/// (`watch_connectivity`), mientras que para los DataItems usa `/`. Play
/// Services despacha a los `WearableListenerService` del manifest armando un
/// Intent con URI `wear://<nodo>/<path>`, y con un path sin barra esa URI queda
/// malformada: ningún filtro la matchea. El listener de runtime sí recibe todo,
/// y por eso los avisos funcionan con la app abierta y el servicio declarativo
/// no se despierta nunca.
///
/// Conclusión medida en hardware: con ese plugin es IMPOSIBLE que el reloj
/// reaccione con la app cerrada. Este canal existe para eso.
///
/// El payload viaja como JSON y no como serialización de Java, así que el
/// mismo mensaje se lee desde Dart, desde un servicio Kotlin sin engine de
/// Flutter, y eventualmente desde Swift.
class TreinoLink {
  TreinoLink({MethodChannel? methods, EventChannel? messages})
      : _methods = methods ?? const MethodChannel(_channelMethods),
        _messages = messages ?? const EventChannel(_channelMessages);

  static const String _channelMethods = 'treino/link';
  static const String _channelMessages = 'treino/link/messages';

  /// Prefijo de todos los paths. Lo espeja el intent-filter del manifest.
  static const String pathPrefix = '/treino';

  /// El teléfono arrancó un entreno. Es lo que despierta al companion.
  static const String pathWorkoutStarted = '$pathPrefix/workout-started';

  /// Arrancó un ejercicio POR TIEMPO, de cualquiera de los dos lados.
  ///
  /// El payload lleva `seconds` y `startedAtEpochMs`. Los dos, y no sólo la
  /// duración, porque el mensaje tarda en cruzar: con el instante de arranque el
  /// receptor descuenta lo que ya pasó y los dos temporizadores muestran el
  /// mismo número en vez de quedar corridos por la latencia del canal.
  static const String pathTimerStarted = '$pathPrefix/timer-started';

  /// Se canceló el ejercicio por tiempo. Sin payload: cancelar es cancelar.
  static const String pathTimerCancelled = '$pathPrefix/timer-cancelled';

  final MethodChannel _methods;
  final EventChannel _messages;

  /// Manda [data] por [path]. Devuelve si había algún nodo al que mandárselo.
  ///
  /// Nunca tira: un aviso que no sale no puede romper al que lo manda.
  Future<bool> send(String path, [Map<String, dynamic> data = const {}]) async {
    try {
      final ok = await _methods.invokeMethod<bool>('send', {
        'path': path,
        'payload': jsonEncode(data),
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[treino-link] no se pudo mandar $path — $e');
      return false;
    }
  }

  /// Los avisos que llegan del otro lado, mientras esta app corre.
  ///
  /// Lo que llega con la app CERRADA no pasa por acá: eso lo atiende el
  /// `WearableListenerService` del manifest, que es otro proceso y otra vida.
  Stream<TreinoLinkMessage> get messages =>
      _messages.receiveBroadcastStream().map((e) {
        final mapa = Map<String, dynamic>.from(e as Map);
        final payload = mapa['payload'] as String? ?? '{}';
        return TreinoLinkMessage(
          path: mapa['path'] as String? ?? '',
          data: _leer(payload),
        );
      });

  /// Un payload roto no puede matar el stream: se anota y llega vacío.
  static Map<String, dynamic> _leer(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (e) {
      debugPrint('[treino-link] payload ilegible — $e');
      return const {};
    }
  }
}
