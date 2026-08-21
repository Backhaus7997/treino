import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'watch_bridge.dart';

/// Abre la app del Apple Watch cuando el atleta arranca un entreno DESDE EL
/// TELÉFONO, aunque el reloj tenga la app cerrada.
///
/// ── Por qué NO va dentro de [WatchNudgeService] ──────────────────────────
///
/// `nudge()` corta en `isReachable == false` — y "la app del reloj está
/// cerrada" es EXACTAMENTE ese caso. O sea que el aviso existente se descarta
/// justo en el único escenario que esto viene a resolver. Comparten los gates
/// de `isSupported` / `isPaired`, pero el de alcanzabilidad los separa: acá
/// pedirlo sería pedir que el reloj ya esté despierto para poder despertarlo.
///
/// ── Falla en silencio, a propósito ──────────────────────────────────────
///
/// Decisión del dueño: si el reloj está apagado, sin batería, no emparejado, o
/// el atleta nunca dio permiso de Salud, no se le muestra NADA. El entreno
/// arranca igual en el teléfono. Esto es un agregado, no un requisito.
///
/// Silencio para el usuario no es silencio para el que debuggea: el lado Swift
/// escribe cada rechazo con su motivo a `os_log`, y acá queda un `debugPrint`.
/// La credencial del reloj se pasó una tarde entera rota porque un `catch (_)`
/// tiraba el diagnóstico a la basura.
class WatchLauncherService {
  WatchLauncherService({
    required WatchBridge bridge,
    MethodChannel? channel,
  })  : _bridge = bridge,
        _channel = channel ?? const MethodChannel(channelName);

  final WatchBridge _bridge;
  final MethodChannel _channel;

  /// Debe coincidir con `WatchLauncher.channelName` del lado Swift.
  static const String channelName = 'com.backhaus.treino/watch_launcher';

  /// Idem con `WatchLauncher.launchMethod`.
  static const String launchMethod = 'launchWatchWorkout';

  /// Intenta abrir la app del reloj. Devuelve si lo logró.
  ///
  /// El resultado es para tests y logs, no para la UI: ningún llamador debería
  /// cambiar lo que ve el atleta según esto.
  Future<bool> launchWorkout() async {
    try {
      if (!await _bridge.isSupported) return false;
      // Sin reloj emparejado no hay nada que despertar, y así se evita cruzar
      // el canal nativo al pedo en cada arranque de entreno.
      if (!await _bridge.isPaired) return false;

      final launched = await _channel.invokeMethod<bool>(launchMethod);
      return launched ?? false;
    } catch (e) {
      // Incluye MissingPluginException: en Android, en tests, y en cualquier
      // build donde el canal no esté registrado, esto tiene que ser inerte.
      debugPrint('[watchLauncher] no se pudo abrir el reloj: $e');
      return false;
    }
  }
}
