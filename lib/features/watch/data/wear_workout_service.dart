import 'package:flutter/services.dart';

/// Estado del descanso tal como lo reporta el lado nativo.
///
/// Trae el DEADLINE y el `ahora` con el que se leyó, nunca una cuenta
/// regresiva. Así, cuántas veces corrió el timer de Dart deja de importar: lo
/// que queda se deriva restando, y si la app no ejecutó un solo tick durante
/// todo el descanso, al volver muestra el número correcto igual.
///
/// Medido en un Samsung SM-L500 (Wear OS 6): en una ventana de 522 s con la
/// muñeca baja, la app ejecutó 108 de 522 callbacks. Un contador de ticks
/// habría mostrado ~8 minutos restantes cuando quedaba 1:18.
typedef WearRestState = ({
  /// Instante de fin en el reloj de `SystemClock.elapsedRealtime`
  /// (`CLOCK_BOOTTIME`): monotónico Y sobrevive a la suspensión del SoC.
  int endsAtElapsedMs,
  int remainingMs,
  bool finished,
});

/// Puente Dart → Android para el entreno en el reloj.
///
/// Envoltorio delgado sobre el `MethodChannel`, por los mismos dos motivos que
/// `WatchBridge` del lado de Apple: **testeabilidad** (un MethodChannel no
/// responde en tests; una costura propia se mockea) y **contención** (cambiar
/// el canal toca un solo archivo).
class WearWorkoutService {
  WearWorkoutService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.treino.app/wear_workout/methods';

  final MethodChannel _channel;

  /// Arranca el foreground service que mantiene vivo el proceso durante el
  /// entreno. Sin esto la app se muere: medido, 22.6% de cobertura contra
  /// 100.0% con el servicio puesto.
  ///
  /// Devuelve false —en vez de tirar— cuando el servicio no está declarado en
  /// el manifest de este build. Es un modo de falla real: `startForegroundService`
  /// devuelve null sin excepción, y taparlo hace que el keep-alive degrade en
  /// silencio.
  Future<bool> startWorkout() async {
    final r = await _channel.invokeMapMethod<String, dynamic>(
      'startForegroundService',
      {'withOngoing': true},
    );
    return r?['ok'] as bool? ?? false;
  }

  Future<void> stopWorkout() =>
      _channel.invokeMethod<void>('stopForegroundService');

  /// Arranca un descanso de [seconds].
  ///
  /// `wakeLock: true` mantiene despierto el SoC mientras dura. No es un
  /// capricho: sin eso el dispositivo entra en Doze y la alarma se difiere
  /// —medido, +21m10s—, así que el aviso nunca llega. Con el wakelock acotado
  /// al descanso, el error medido fue de 8 ms.
  Future<void> startRest(int seconds) => _channel.invokeMethod<void>(
        'startRest',
        {'seconds': seconds, 'wakeLock': true},
      );

  Future<void> cancelRest() => _channel.invokeMethod<void>('cancelRest');

  /// Estado actual, o null si no hay descanso en curso.
  ///
  /// El nativo ya descarta un deadline que sobrevivió a un reboot: como
  /// `elapsedRealtime` cuenta desde el arranque, tras reiniciar apuntaría a un
  /// futuro imposible.
  Future<WearRestState?> restState() async {
    final r = await _channel.invokeMapMethod<String, dynamic>('restState');
    final endsAt = r?['restEndsAtElapsedMs'] as int?;
    if (r == null || endsAt == null) return null;
    return (
      endsAtElapsedMs: endsAt,
      remainingMs: r['remainingMs'] as int? ?? 0,
      finished: r['finished'] as bool? ?? false,
    );
  }
}
